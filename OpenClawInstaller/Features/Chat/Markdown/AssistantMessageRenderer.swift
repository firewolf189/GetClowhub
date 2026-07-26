import SwiftUI
import AppKit
import Foundation
import MarkdownUI
import os.log

let chatRenderPerfLog = Logger(subsystem: "com.openclaw.installer", category: "SessionSwitchPerformance")

func dashboardElapsedMillisecondsText(since start: ContinuousClock.Instant) -> String {
    let duration = start.duration(to: ContinuousClock.now)
    let components = duration.components
    let milliseconds = Double(components.seconds) * 1_000
        + Double(components.attoseconds) / 1_000_000_000_000_000
    return String(format: "%.1f", milliseconds)
}

// MARK: - Assistant Markdown Rendering

enum MarkdownRenderMode {
    /// Streaming draft: raw text, cheapest possible per-token updates.
    case plainText
    /// Completed message default: pure-SwiftUI MarkdownUI. No platform view
    /// participates in layout — this is the structural fix for the
    /// SwiftUI<->AppKit layout livelocks (five incidents, 2026-07-21..24).
    case markdownUI
    /// Completed message containing math/LaTeX or raw HTML blocks, which
    /// MarkdownUI cannot render — the only remaining WKWebView user.
    case webView
}

enum MarkdownRenderPolicy {
    static let heightUpdateThreshold: CGFloat = 4
    static let recentRichMessageLimit = 6

    static func mode(for content: String, isStreaming: Bool, allowsWebView: Bool = true) -> MarkdownRenderMode {
        if isStreaming { return .plainText }
        if allowsWebView && requiresWebView(content) { return .webView }
        return .markdownUI
    }

    static func shouldApplyMeasuredHeight(current: CGFloat, measured: CGFloat) -> Bool {
        abs(current - measured) >= heightUpdateThreshold
    }

    static func isComplexMarkdown(_ content: String) -> Bool {
        requiresWebView(content)
    }

    static func recentRichMessageIds(in messages: [ChatMessage]) -> Set<UUID> {
        var ids: Set<UUID> = []

        for message in messages.reversed() {
            guard ids.count < recentRichMessageLimit else { break }
            guard message.role == .assistant,
                  message.taskStatus == .completed,
                  requiresWebView(message.content) else {
                continue
            }
            ids.insert(message.id)
        }

        return ids
    }

    private static func requiresWebView(_ content: String) -> Bool {
        // Tables intentionally NOT included: MarkdownUI renders GFM tables
        // natively, and the webview's async height measurement was the source
        // of the phantom-blank-space bug on emoji tables (v1.1.77).
        containsMathSyntax(content)
            || containsHTMLBlock(content)
    }

    private static func containsMarkdownTable(_ content: String) -> Bool {
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard lines.count >= 2 else { return false }

        for index in 0..<(lines.count - 1) {
            let header = lines[index]
            let separator = lines[index + 1]
                .trimmingCharacters(in: .whitespaces)

            if header.contains("|"),
               separator.contains("|"),
               separator.contains("-"),
               separator.allSatisfy({ char in
                   char == "|" || char == "-" || char == ":" || char == " "
               }) {
                return true
            }
        }
        return false
    }

    private static func containsMathSyntax(_ content: String) -> Bool {
        if content.contains("$$")
            || content.contains(#"\("#)
            || content.contains(#"\["#)
            || content.contains(#"\begin{"#) {
            return true
        }

        let pattern = #"(?<![A-Za-z0-9])\$[^\n$]{1,160}\$(?![A-Za-z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }

    private static func containsHTMLBlock(_ content: String) -> Bool {
        let pattern = #"<\s*(table|thead|tbody|tr|td|th|div|details|summary|img|video|audio|iframe|style|script|br|hr)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return regex.firstMatch(in: content, range: range) != nil
    }
}

private struct MessageRenderModel {
    enum Renderer {
        case plainText
        case markdownUI
        case webViewFallback
    }

    let content: String
    let isStreaming: Bool
    let renderer: Renderer

    static func build(content: String, isStreaming: Bool, allowsRichMarkdown: Bool) -> MessageRenderModel {
        let mode = MarkdownRenderPolicy.mode(
            for: content,
            isStreaming: isStreaming,
            allowsWebView: allowsRichMarkdown
        )
        switch mode {
        case .plainText:
            return MessageRenderModel(content: content, isStreaming: isStreaming, renderer: .plainText)
        case .markdownUI:
            return MessageRenderModel(content: content, isStreaming: isStreaming, renderer: .markdownUI)
        case .webView:
            return MessageRenderModel(content: content, isStreaming: isStreaming, renderer: .webViewFallback)
        }
    }
}

struct AssistantMessageContentView: View {
    let content: String
    let isStreaming: Bool
    let allowsRichMarkdown: Bool
    /// Absolute workspace path used to resolve relative in-prose file
    /// references so they can be turned into tappable links.
    let workspaceRootPath: String?
    /// Invoked when the user clicks an in-prose document link.
    let onOpenFileReference: ((String) -> Void)?
    /// Render the whole message as a single selectable Text so a drag can span
    /// blocks. Off by default: it trades block layout for a continuous
    /// selection, so it is a per-message user choice, not the reading mode.
    let prefersFullMessageSelection: Bool

    init(
        content: String,
        isStreaming: Bool,
        allowsRichMarkdown: Bool = true,
        workspaceRootPath: String? = nil,
        onOpenFileReference: ((String) -> Void)? = nil,
        prefersFullMessageSelection: Bool = false
    ) {
        self.content = content
        self.isStreaming = isStreaming
        self.allowsRichMarkdown = allowsRichMarkdown
        self.workspaceRootPath = workspaceRootPath
        self.onOpenFileReference = onOpenFileReference
        self.prefersFullMessageSelection = prefersFullMessageSelection
    }

    var body: some View {
        let renderModel = MessageRenderModel.build(
            content: content,
            isStreaming: isStreaming,
            allowsRichMarkdown: allowsRichMarkdown
        )

        if prefersFullMessageSelection, !renderModel.isStreaming {
            // Cross-block selection: every other renderer lays the message out
            // as SIBLING views (MarkdownUI one per block, WebView one document),
            // and `.textSelection` cannot span siblings — dragging from a
            // paragraph into a list selected only the paragraph. Collapsing the
            // message into ONE Text makes the drag continuous.
            CrossBlockSelectableMessageText(
                content: renderModel.content,
                workspaceRootPath: workspaceRootPath,
                onOpenFileReference: onOpenFileReference
            )
                .onAppear {
                    logRenderMode("cross_block_selection")
                }
        } else {
            renderedBody(for: renderModel)
        }
    }

    @ViewBuilder
    private func renderedBody(for renderModel: MessageRenderModel) -> some View {
        switch renderModel.renderer {
        case .webViewFallback:
            SelectableMarkdownView(
                content: renderModel.content,
                copyFallbackText: renderModel.content
            )
                .onAppear {
                    logRenderMode("webview")
                }
        case .markdownUI:
            // Claude-style inline document links: rewrite resolvable file
            // paths in the prose into markdown links, render them underlined,
            // and intercept the custom scheme to preview in-app.
            Markdown(MessageFileReferences.linkify(
                content: renderModel.content,
                workspaceRoot: workspaceRootPath
            ))
                .markdownTextStyle(\.text) {
                    FontSize(14)
                }
                .markdownTextStyle(\.link) {
                    UnderlineStyle(.single)
                    ForegroundColor(.accentColor)
                }
                .environment(\.openURL, OpenURLAction { url in
                    if let path = MessageFileReferences.path(fromLinkURL: url) {
                        if let onOpenFileReference {
                            onOpenFileReference(path)
                        } else {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                        return .handled
                    }
                    return .systemAction
                })
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    logRenderMode("markdown_ui")
                }
        case .plainText:
            Text(verbatim: renderModel.content)
                .font(.system(size: 14))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    logRenderMode("plain_text")
                }
        }
    }

    private func logRenderMode(_ mode: String) {
        chatRenderPerfLog.info("phase=assistant_content_render_mode mode=\(mode, privacy: .public) content_length=\(content.count, privacy: .public) is_streaming=\(isStreaming, privacy: .public) allows_rich_markdown=\(allowsRichMarkdown, privacy: .public)")
    }
}

// MARK: - Cross-Block Selectable Message

/// One `Text` for the whole message, so a drag selects continuously across
/// paragraphs, lists and headings — what MarkdownUI's per-block views cannot do.
///
/// Inline markup (bold, italic, code spans, links) still renders; block syntax
/// stays as source text (`- `, `## `), which is also what lands on the clipboard.
/// Pure SwiftUI on purpose: the previous cross-block implementation hosted an
/// NSTextView per message and fed the SwiftUI<->AppKit layout livelock.
struct CrossBlockSelectableMessageText: View {
    let content: String
    let workspaceRootPath: String?
    let onOpenFileReference: ((String) -> Void)?

    var body: some View {
        Text(attributedContent)
            .font(.system(size: 14))
            .lineSpacing(2)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .environment(\.openURL, OpenURLAction { url in
                if let path = MessageFileReferences.path(fromLinkURL: url) {
                    if let onOpenFileReference {
                        onOpenFileReference(path)
                    } else {
                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                    }
                    return .handled
                }
                return .systemAction
            })
    }

    private var attributedContent: AttributedString {
        let linkified = MessageFileReferences.linkify(
            content: content,
            workspaceRoot: workspaceRootPath
        )
        // `inlineOnlyPreservingWhitespace` is what keeps this ONE text run:
        // block-level parsing would split the message into paragraphs again.
        guard var parsed = try? AttributedString(
            markdown: Self.strippingCodeFences(linkified),
            options: AttributedString.MarkdownParsingOptions(
                allowsExtendedAttributes: false,
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) else {
            return AttributedString(content)
        }
        // Match the rendered mode's link affordance; AttributedString links are
        // otherwise indistinguishable from body text here.
        let linkRanges = parsed.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            parsed[range].underlineStyle = .single
        }
        return parsed
    }

    /// Drops ``` fence lines before inline parsing. Left in, the fence turns the
    /// whole block into ONE inline-code run and its newlines are normalized
    /// away — so the code collapsed onto a single line and copying it lost the
    /// line structure. Without the fences the inner lines stay ordinary text
    /// lines, which is exactly what should land on the clipboard.
    static func strippingCodeFences(_ markdown: String) -> String {
        guard markdown.contains("```") else { return markdown }
        let kept = markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
        return kept.joined(separator: "\n")
    }
}

// MARK: - Native Markdown View (lightweight, no WKWebView)

/// Renders markdown using SwiftUI's native AttributedString.
/// Zero WKWebView overhead — no process spawn, no HTML parsing, no height measurement.
struct NativeMarkdownView: View {
    let content: String

    var body: some View {
        Text(attributedContent)
            .font(DashboardTypography.message)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributedContent: AttributedString {
        (try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(content)
    }
}

// The AppKit text-selection bridge that used to live here was deleted on
// 2026-07-26: cross-block selection is now pure SwiftUI
// (CrossBlockSelectableMessageText), and hosting an NSTextView per message was
// what fed the SwiftUI<->AppKit layout livelock.

/// Cmd+C for any focused AppKit text view (composer, inline editor). The
/// per-message `activeTextView` registration went away with the bridge above.
enum NativeSelectableTextSelectionRegistry {
    static func copySelectedTextFromFirstResponder(_ sender: Any?) -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              textView.selectedRanges.contains(where: { $0.rangeValue.length > 0 }) else {
            return false
        }
        textView.copy(sender)
        return true
    }

}

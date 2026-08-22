import SwiftUI
import SwiftTerm
import UniformTypeIdentifiers
import AVKit
import Combine
import Quartz
import AppKit
import WebKit
import os.log

// Split from DashboardView.swift — file move only, no behavior change.

/// Borderless message-action icon (copy / rewind) with a subtle per-icon hover
/// highlight — matches the macOS / Claude action-bar look. Row-level show/hide
/// (fade in on message hover) is handled by the parent via opacity.
/// Shared by the main chat bubbles and the Help assistant window.
struct MessageActionIcon: View {
    let systemName: String
    var tint: SwiftUI.Color = .secondary
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundColor(tint)
                .frame(width: 22, height: 16)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(hovering ? SwiftUI.Color.primary.opacity(0.08) : SwiftUI.Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
        }
        .animation(.easeInOut(duration: 0.12), value: hovering)
        .unifiedTooltip(UnifiedTooltipContent(title: help))
    }
}

struct ChatBubble: View, Equatable {
    let message: ChatMessageRowModel
    /// Confirmed edit-resend for a user message. The destructive rewind happens
    /// only after the inline editor's confirm action calls this callback.
    var onConfirmEditResend: ((UUID, String) -> Void)? = nil
    /// Cancel the in-flight run for this message. When set, a cancel button
    /// appears next to the streaming spinner so a run can be stopped mid-stream.
    var onCancel: ((UUID) -> Void)? = nil
    /// Retry the shared gateway connection for a transport-lost run.
    var onRetryConnection: ((UUID) -> Void)? = nil
    /// Preview a referenced document in-app (right inspector).
    var onOpenFileReference: ((String) -> Void)? = nil
    @State private var isHovering = false
    @State private var cachedMediaURLs: [URL] = []
    @State private var lastMediaScanContent: String = ""
    @State private var isEditingForResend = false
    @State private var editDraft = ""
    @State private var isRichMarkdownActivated = false
    /// Per-bubble, LOCAL on purpose: cross-block selection swaps this message's
    /// body for a single Text. Keeping it out of the timeline snapshot means
    /// toggling it re-renders one row instead of rebuilding every message
    /// (that rebuild was the livelock amplifier).
    @State private var prefersFullMessageSelection = false

    /// Visual ack for the copy button — flips to `true` for ~1.5s after a
    /// successful clipboard write, swaps the icon to a green checkmark, and
    /// surfaces a "已复制" label. Without this, clicking the button gave
    /// zero feedback (a user-reported bug — they couldn't tell whether the
    /// copy actually fired).
    @State private var copied = false
    /// In-flight reset task for `copied`. Re-clicking the button while a
    /// previous ack is still showing should restart the 1.5s window rather
    /// than have both timers fight each other.
    @State private var copyResetTask: DispatchWorkItem?

    /// Pending "hide the action icons" task. The icons don't vanish the instant
    /// the cursor leaves the bubble — that made them impossible to reach
    /// ("悬停时间太短"). Instead we wait out a short grace period; moving the
    /// cursor back in (or onto the icons) cancels the hide so they stay put.
    @State private var hoverHideTask: DispatchWorkItem?

    static func == (lhs: ChatBubble, rhs: ChatBubble) -> Bool {
        lhs.message == rhs.message
    }

    /// Cached regex for media URL detection (compiled once, reused)
    private static let mediaFileRegex: NSRegularExpression? = {
        let mediaExtensions = [
            "mp4", "mov", "avi", "mkv", "webm", "m4v",
            "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff",
            "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff",
        ]
        let extPattern = mediaExtensions.joined(separator: "|")
        let filePattern = "(/[^\\s\"'`<>()\\[\\]]+\\.(?:\(extPattern)))(?=[\\s\"'`.,;:!?)\\]\\n]|$)"
        return try? NSRegularExpression(pattern: filePattern, options: [.caseInsensitive, .anchorsMatchLines])
    }()

    /// Format a message timestamp: "HH:mm" if the message is from today, or
    /// "MM-dd HH:mm" if it's older. Cached formatters keep this cheap on
    /// scroll — Date↦string allocation per row is fine but we don't want
    /// to spin up a fresh DateFormatter each time.
    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let dateAndTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()

    static func formatTimestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return timeOnlyFormatter.string(from: date)
        }
        return dateAndTimeFormatter.string(from: date)
    }

    /// Scan for media file URLs — only called from .onChange, result stored in cachedMediaURLs
    private static func scanMediaURLs(in text: String) -> [URL] {
        guard let regex = mediaFileRegex else { return [] }
        var urls: [URL] = []
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            if let range = Range(captureRange, in: text) {
                let path = String(text[range])
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path), !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 60) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Attachment thumbnails (user-attached files)
                if !message.attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.attachments, id: \.absoluteString) { url in
                            AttachmentThumbnail(url: url)
                        }
                    }
                }

                if showsTopWorkStatus {
                    WorkStatusHeader(
                        start: message.timestamp,
                        end: message.completedAt,
                        activityEvents: message.activityEvents,
                        runState: message.runState,
                        onRetry: { onRetryConnection?(message.id) }
                    )
                }

                if !message.content.isEmpty {
	                    // Bubble body: prefer native MarkdownUI for ordinary
	                    // assistant text so session switches and streaming do
	                    // not cold-mount a WKWebView for every message. Fall
	                    // back to WebKit only for complex content that native
	                    // MarkdownUI cannot represent well here (tables, math,
	                    // raw HTML).
                    // Bubble + action row share ONE hover zone (the inner
                    // VStack's `.onHover`). A single source of truth for
                    // `isHovering` means moving the cursor from the bubble
                    // down onto the icons never crosses a "dead gap" that
                    // would flip hover off and hide the row mid-reach — the
                    // old two-`onHover` setup (bubble toggled true/false,
                    // row only set true) raced and dropped clicks.
                    //
                    // spacing:3 tucks the icons right under the bubble.
                    // NO negative padding: `.padding(.top, -6)` shifted the
                    // row's *visual* position up but left its hit-test
                    // region at the layout slot, so clicks landed in dead
                    // space ("点击没有反应"). Positive spacing keeps both
                    // aligned and keeps the row clear of the WKWebView's
                    // click-capturing frame above it.
                    VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
	                        Group {
		                            if message.role == .assistant {
                                    AssistantMessageContentView(
                                        content: message.content,
                                        isStreaming: isStreamingState,
                                        allowsRichMarkdown: message.allowsRichMarkdown || isRichMarkdownActivated,
                                        workspaceRootPath: message.workspaceRootPath,
                                        onOpenFileReference: onOpenFileReference,
                                        prefersFullMessageSelection: prefersFullMessageSelection
                                    )
	                                    .fixedSize(horizontal: false, vertical: true)
			                                    .padding(10)
	                                    .background(message.isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor)
	                                    .cornerRadius(12)
	                            } else if isEditingForResend {
                                InlineUserMessageEditor(
                                    text: $editDraft,
                                    onCommit: confirmEditResend,
                                    onCancel: cancelEditResend
                                )
	                                .frame(minHeight: 76)
	                                .padding(8)
	                                .background(message.isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor)
		                                .cornerRadius(12)
	                            } else {
                                    // Pure SwiftUI: user rows carried an
                                    // NSTextView host per message, feeding the
                                    // SwiftUI<->AppKit layout livelock.
                                    Text(verbatim: message.content)
                                        .font(.system(size: 14))
                                        .lineSpacing(2)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
			                                    .padding(10)
			                                    .background(message.isJumpHighlighted ? jumpHighlightBackgroundColor : bubbleBackgroundColor)
                                        .cornerRadius(12)
                            }
                        }
                        .contextMenu {
                            Button(action: { performCopy(message.content) }) {
                                Label(I18n.t("common.action.copy"), systemImage: "square.on.square")
                            }
                            if message.role == .assistant, !message.content.isEmpty {
                                Button(action: { prefersFullMessageSelection.toggle() }) {
                                    Label(
                                        prefersFullMessageSelection ? "退出跨段选择" : "跨段选择文本",
                                        systemImage: "selection.pin.in.out"
                                    )
                                }
                            }
                        }

                        if message.role == .assistant, !message.fileReferences.isEmpty {
                            MessageFileChipsRow(paths: message.fileReferences, onOpen: onOpenFileReference)
                        }

                        // Action row: copy + (assistant) rewind. Shown only
                        // for TERMINAL-state messages (streaming bubbles get
                        // the cancel row below instead). Hidden until the
                        // wrapper is hovered, then fades in; `copied` keeps
                        // the ✓ up briefly after the cursor leaves.
                        // `allowsHitTesting` is gated on visibility so the
                        // transparent row never silently eats clicks.
                        if !isStreamingState && !message.content.isEmpty && !isEditingForResend {
                            HStack(spacing: 2) {
                                MessageActionIcon(
                                    systemName: copied ? "checkmark" : "square.on.square",
                                    tint: copied ? .green : .secondary,
                                    help: copied ? "已复制" : "复制",
                                    action: { performCopy(message.content) }
	                                )
                                if canActivateRichMarkdown {
                                    MessageActionIcon(
                                        systemName: "doc.richtext",
                                        tint: .secondary,
                                        help: "渲染复杂内容",
                                        action: { isRichMarkdownActivated = true }
                                    )
                                }
                                // Cross-block selection. Rendered blocks are
                                // separate views, so a drag stops at the first
                                // block boundary; this collapses the message
                                // into one selectable Text.
                                if message.role == .assistant {
                                    MessageActionIcon(
                                        systemName: "selection.pin.in.out",
                                        tint: prefersFullMessageSelection ? .accentColor : .secondary,
                                        help: prefersFullMessageSelection ? "退出跨段选择" : "跨段选择文本",
                                        action: { prefersFullMessageSelection.toggle() }
                                    )
                                }
                                // Edit & resend only makes sense for the user's
                                // own messages (you edit your prompt, not the
                                // assistant's output), so the rewind icon is
                                // gated to .user bubbles.
                                if onConfirmEditResend != nil && message.role == .user {
                                    MessageActionIcon(
                                        systemName: "arrow.uturn.backward",
                                        tint: .secondary,
                                        help: "编辑重发",
                                        action: { beginEditResend() }
                                    )
                                }
                                if let ts = message.timestamp {
                                    Text(Self.formatTimestamp(ts))
                                        .font(DashboardTypography.messageMeta)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                        .padding(.leading, 4)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
                            .opacity(isHovering || copied ? 1.0 : 0.0)
                            .allowsHitTesting(isHovering || copied)
                            .animation(.easeInOut(duration: 0.15), value: isHovering)
                            .animation(.easeInOut(duration: 0.18), value: copied)
                        }
                    }
                    .onHover { hovering in
                        if hovering {
                            // Entered the bubble/toolbar zone — cancel any pending
                            // hide and reveal the icons right away.
                            hoverHideTask?.cancel()
                            hoverHideTask = nil
                            withAnimation(.easeInOut(duration: 0.15)) {
                                isHovering = true
                            }
                        } else {
                            // Left the zone — keep the icons up for a grace period
                            // so the cursor has time to travel to them and click.
                            // Re-entering cancels this (see the `hovering` branch).
                            hoverHideTask?.cancel()
                            let task = DispatchWorkItem {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isHovering = false
                                }
                            }
                            hoverHideTask = task
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
                        }
                    }
                }

                // Detected media files from assistant response
                if !cachedMediaURLs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cachedMediaURLs, id: \.absoluteString) { url in
                            AttachmentThumbnail(url: url)
                        }
                    }
                }
            }

            if message.role == .assistant { Spacer(minLength: 60) }
        }
        .onAppear {
            logBubbleAppear()
            // Initial scan for media URLs when bubble first appears
            if message.role == .assistant && !message.isStreamingDraft && lastMediaScanContent != message.content {
                lastMediaScanContent = message.content
                cachedMediaURLs = ChatBubble.scanMediaURLs(in: message.content)
            }
        }
        .onChange(of: message.content) { newContent in
            // Only re-scan for media URLs when content actually changes
            guard message.role == .assistant, !message.isStreamingDraft, newContent != lastMediaScanContent else { return }
            lastMediaScanContent = newContent
            cachedMediaURLs = ChatBubble.scanMediaURLs(in: newContent)
        }
    }

    private func logBubbleAppear() {
        chatRenderPerfLog.info("phase=bubble_appear message=\(message.id.uuidString, privacy: .public) role=\(message.role.rawValue, privacy: .public) status=\(message.taskStatus.rawValue, privacy: .public) content_length=\(message.content.count, privacy: .public) attachment_count=\(message.attachments.count, privacy: .public) activity_count=\(message.activityEvents.count, privacy: .public) allows_rich_markdown=\(message.allowsRichMarkdown || isRichMarkdownActivated, privacy: .public)")
    }

    private var bubbleBackgroundColor: SwiftUI.Color {
        message.role == .user
            ? Color.gray.opacity(0.14)
            : Color(NSColor.controlBackgroundColor)
    }

    private var jumpHighlightBackgroundColor: SwiftUI.Color {
        Color.gray.opacity(0.42)
    }

    /// True while the message is still being generated — covers both the
    /// foreground `.loading` and `.background` (running detached) statuses.
    /// Used to gate the hover toolbar; we don't want a stale "Copy
    /// half-streamed text" affordance.
    private var isStreamingState: Bool {
        message.role == .assistant
            && (message.runPhase?.isTerminal == false
                || message.isStreamingDraft
                || message.taskStatus == .loading
                || message.taskStatus == .background)
    }

    private var showsTopWorkStatus: Bool {
        message.role == .assistant
            && (isStreamingState || message.completedAt != nil)
    }

    private func beginEditResend() {
        editDraft = message.content
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingForResend = true
            isHovering = true
            // Tell the composer to release focus, otherwise SwiftUI's
            // @FocusState keeps asserting it and the caret ends up back in the
            // bottom input while the user is editing a history message.
            NotificationCenter.default.post(name: .gchChatInlineEditingChanged, object: true)
        }
    }

    private var canActivateRichMarkdown: Bool {
        message.role == .assistant
            && !isStreamingState
            && !message.allowsRichMarkdown
            && !isRichMarkdownActivated
            && MarkdownRenderPolicy.isComplexMarkdown(message.content)
    }

    private func cancelEditResend() {
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingForResend = false
        }
        editDraft = ""
        NotificationCenter.default.post(name: .gchChatInlineEditingChanged, object: false)
    }

    private func confirmEditResend() {
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelEditResend()
            return
        }
        withAnimation(.easeInOut(duration: 0.16)) {
            isEditingForResend = false
        }
        onConfirmEditResend?(message.id, trimmed)
        editDraft = ""
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Copy + show the "已复制" ack for 1.5s. Both the bubble toolbar
    /// button and the contextMenu "Copy" item route through here so the
    /// feedback is consistent across entry points.
    private func performCopy(_ text: String) {
        copyToClipboard(text)
        withAnimation(.easeInOut(duration: 0.18)) {
            copied = true
        }
        // Restart the 1.5s reset window on every click so rapid
        // repeated clicks don't get clipped by a stale reset firing
        // mid-animation.
        copyResetTask?.cancel()
        let task = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.18)) {
                copied = false
            }
        }
        copyResetTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }
}

private struct InlineUserMessageEditor: View {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            InlineMessageEditorTextView(
                text: $text,
                onCommit: onCommit,
                onCancel: onCancel
            )
            .frame(minHeight: 54, maxHeight: 160)

            HStack(spacing: 6) {
                Spacer(minLength: 0)

                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("catalog.action.cancel")))

                Button(action: onCommit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(NSColor.windowBackgroundColor))
                        .frame(width: 26, height: 24)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(0.62))
                        }
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.tooltip.confirmAndSend")))
            }
        }
    }
}

private struct InlineMessageEditorTextView: NSViewRepresentable {
    @Binding var text: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        let textView = CommitAwareTextView()
        textView.identifier = NSUserInterfaceItemIdentifier("inlineMessageEditorTextView")
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.onCancel = onCancel
        textView.string = text
        textView.font = NSFont.systemFont(ofSize: 16)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.insertionPointColor = NSColor.labelColor

        scrollView.documentView = textView

        // Claim focus RELIABLY. A single async hop was not enough: at
        // makeNSView time the view is not in a window yet, and inside the
        // lazily-built chat timeline it can take several runloop turns to get
        // there — `textView.window` was nil, the call silently no-opped, and
        // the caret stayed in the main composer.
        claimFocus(for: textView, coordinator: context.coordinator, attempt: 0)

        return scrollView
    }

    private func claimFocus(for textView: NSTextView, coordinator: Coordinator, attempt: Int) {
        guard attempt < 20, !coordinator.hasClaimedFocus else { return }
        DispatchQueue.main.async {
            if let window = textView.window {
                window.makeFirstResponder(textView)
                coordinator.hasClaimedFocus = true
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                claimFocus(for: textView, coordinator: coordinator, attempt: attempt + 1)
            }
        }
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CommitAwareTextView else { return }
        if !context.coordinator.hasClaimedFocus {
            claimFocus(for: textView, coordinator: context.coordinator, attempt: 0)
        }
        textView.onCommit = onCommit
        textView.onCancel = onCancel
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        /// Set once the text view has actually become first responder.
        var hasClaimedFocus = false
        @Binding var text: String

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }

    final class CommitAwareTextView: NSTextView {
        var onCommit: (() -> Void)?
        var onCancel: (() -> Void)?

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36,
               !event.modifierFlags.contains(.shift),
               !hasMarkedText() {
                onCommit?()
                return
            }

            if event.keyCode == 53 {
                onCancel?()
                return
            }

            super.keyDown(with: event)
        }
    }
}

// MARK: - Typewriter Text for Streaming

class TypewriterEngine: ObservableObject {
    @Published var displayed: String = ""
    private var target: String = ""
    private var visibleLength: Int = 0
    private var timer: Timer?

    func setTarget(_ text: String) {
        target = text
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        if visibleLength < target.count {
            // Type 15 chars at a time to reduce CPU usage during long streaming output
            visibleLength = min(visibleLength + 15, target.count)
            displayed = String(target.prefix(visibleLength))
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }
}

struct TypewriterText: View {
    let fullText: String
    @StateObject private var engine = TypewriterEngine()

    var body: some View {
        Text(engine.displayed)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            engine.setTarget(fullText)
        }
        .onChange(of: fullText) { newText in
            engine.setTarget(newText)
        }
        .onDisappear {
            engine.stop()
        }
    }
}

// MARK: - Attachment Thumbnail (in chat bubble)

struct AttachmentThumbnail: View {
    let url: URL

    private var fileType: AttachmentFileType {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg"].contains(ext) {
            return .image
        } else if ["mp4", "mov", "avi", "mkv", "webm", "m4v"].contains(ext) {
            return .video
        } else if ["mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff"].contains(ext) {
            return .audio
        }
        return .other
    }

    enum AttachmentFileType {
        case image, video, audio, other
    }

    var body: some View {
        Button(action: { NSWorkspace.shared.open(url) }) {
            switch fileType {
            case .image:
                if let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 300)
                        .cornerRadius(8)
                } else {
                    fileIcon
                }
            case .video:
                InlineVideoPlayer(url: url)
            case .audio:
                InlineAudioPlayer(url: url)
            case .other:
                fileIcon
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private var fileIcon: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
            Text(url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var iconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        case "json", "xml", "yaml", "yml", "toml", "ini", "env", "conf", "properties": return "curlybraces"
        case "md", "txt", "log": return "doc.plaintext"
        case "xmind": return "brain.head.profile"
        case "py", "js", "ts", "swift", "java", "go", "rs", "c", "cpp", "h",
             "rb", "php", "sh", "sql", "r", "jsx", "tsx", "vue": return "chevron.left.forwardslash.chevron.right"
        case "html", "htm", "css", "scss": return "globe"
        case "ipynb": return "book.closed.fill"
        default: return "doc.fill"
        }
    }
}

// MARK: - Inline Video Player

struct InlineVideoPlayer: View {
    let url: URL
    @State private var showPlayer = false
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            if showPlayer {
                NativeVideoPlayerView(url: url)
                    .frame(width: 280, height: 180)
                    .cornerRadius(8)
            } else {
                // Thumbnail placeholder with play button
                ZStack {
                    if let thumb = thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 280, height: 180)
                            .clipped()
                    } else {
                        Rectangle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 280, height: 180)
                        Image(systemName: "film")
                            .font(.system(size: 30))
                            .foregroundColor(.secondary)
                    }

                    // Play button overlay
                    Button(action: { showPlayer = true }) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)

                    // File name
                    VStack {
                        Spacer()
                        HStack {
                            Text(url.lastPathComponent)
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(4)
                            Spacer()
                        }
                        .padding(6)
                    }
                }
                .frame(width: 280, height: 180)
                .cornerRadius(8)
            }
        }
        .onAppear { generateThumbnail() }
    }

    private func generateThumbnail() {
        Task.detached {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 560, height: 360)
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                await MainActor.run {
                    thumbnail = nsImage
                }
            }
        }
    }
}

// MARK: - Native Video Player (NSViewRepresentable)

struct NativeVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.controlsStyle = .inline
        let player = AVPlayer(url: url)
        playerView.player = player
        player.play()
        return playerView
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {}

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

// MARK: - Inline Audio Player

struct InlineAudioPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timeObserver: Any?

    var body: some View {
        HStack(spacing: 10) {
            // Play/Pause button
            Button(action: { togglePlayback() }) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                // File name
                Text(url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(.primary)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(NSColor.separatorColor))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: duration > 0 ? geo.size.width * (currentTime / duration) : 0, height: 4)
                    }
                }
                .frame(height: 4)

                // Time labels
                HStack {
                    Text(formatTime(currentTime))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatTime(duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .frame(width: 260)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .onDisappear { cleanup() }
    }

    private func ensurePlayer() {
        guard player == nil else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer

        // Get duration
        Task {
            if let asset = avPlayer.currentItem?.asset {
                let dur = try? await asset.load(.duration)
                if let dur = dur {
                    await MainActor.run {
                        duration = CMTimeGetSeconds(dur)
                    }
                }
            }
        }

        // Periodic time observer
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            currentTime = CMTimeGetSeconds(time)
        }

        // Reset when playback ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            isPlaying = false
            avPlayer.seek(to: .zero)
            currentTime = 0
        }
    }

    private func togglePlayback() {
        ensurePlayer()
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func cleanup() {
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Attachment Preview (in input bar)

struct AttachmentPreview: View {
    let url: URL
    let onRemove: () -> Void

    private var isImage: Bool {
        // Directories never read as images, even if the path happens to end in .png.
        if isDirectory { return false }
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "bmp", "webp", "heic", "tiff", "svg"].contains(ext)
    }

    /// True iff the URL points at an existing directory. Stat'd once per render —
    /// fine for the small N of attached items shown in the chip strip.
    private var isDirectory: Bool {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isImage, let nsImage = NSImage(contentsOf: url) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipped()
                    .cornerRadius(8)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                            .frame(width: 40, height: 40)
                        if isDirectory {
                            WorkspaceFolderIcon(isExpanded: false, size: 20)
                        } else {
                            Image(systemName: fileIconName)
                                .font(.system(size: 20, weight: .regular))
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(attachmentTypeLabel)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 22)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .frame(width: 206, height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }

            // Remove button
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.black.opacity(0.82)))
            }
            .buttonStyle(.plain)
            .unifiedTooltip(UnifiedTooltipContent(title: I18n.t("dashboard.tooltip.removeAttachment")))
            .padding(.top, 4)
            .padding(.trailing, 5)
        }
    }

    private var attachmentTypeLabel: String {
        if isDirectory { return "FOLDER" }
        let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? "FILE" : ext.uppercased()
    }

    private var fileIconName: String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx": return "doc.text.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        case "mp3", "wav", "m4a", "aac", "flac": return "music.note"
        case "mp4", "mov", "avi", "mkv", "webm": return "film.fill"
        default: return "doc.fill"
        }
    }
}


extension Notification.Name {
    /// Posted with `true` when an inline history-message edit begins and
    /// `false` when it ends, so the main composer can yield/reclaim focus.
    static let gchChatInlineEditingChanged = Notification.Name("gchChatInlineEditingChanged")
}

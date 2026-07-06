import SwiftUI
import AppKit
import WebKit
import Foundation
import os.log

// MARK: - Selectable Markdown View (WKWebView-based, used by HelpAssistantWindow)


/// Cache for rendered Markdown HTML to avoid repeated parsing during SwiftUI layout cycles.
private let markdownHTMLCache = makeMarkdownHTMLCache()
/// Cache for measured heights to avoid 22pt → actual height jump when LazyVStack recreates views.
private let markdownHeightCache = makeMarkdownHeightCache()

private func makeMarkdownHTMLCache() -> NSCache<NSString, NSString> {
    let markdownHTMLCache = NSCache<NSString, NSString>()
    markdownHTMLCache.countLimit = 120
    markdownHTMLCache.totalCostLimit = 8 * 1024 * 1024
    return markdownHTMLCache
}

private func makeMarkdownHeightCache() -> NSCache<NSString, NSNumber> {
    let markdownHeightCache = NSCache<NSString, NSNumber>()
    markdownHeightCache.countLimit = 240
    return markdownHeightCache
}

private func setCachedMarkdownHTML(_ html: String, forKey cacheKey: NSString) {
    markdownHTMLCache.setObject(html as NSString, forKey: cacheKey, cost: html.utf8.count)
}

/// Renders markdown as selectable rich text via WKWebView. Supports
/// free multi-line drag-selection across paragraphs, lists and tables
/// (HTML body carries `-webkit-user-select: text` and WebKit's native
/// selection model handles cross-block ranges).
///
/// Streaming updates: `_MarkdownWebView` mutates `document.body.innerHTML`
/// via JS on every content delta — no `loadHTMLString` reload, no flash.
/// The 500 ms throttle the previous version had was a workaround for
/// the reload-flash; with DOM mutations the per-update cost is small
/// (~5–30 ms for markdown→HTML build + a single JS bridge call), so we
/// just pipe `content` straight through and let SwiftUI's natural body
/// re-eval rate (bounded by the upstream `sendChatMessage` throttle of
/// ~100 ms) drive updates.
struct SelectableMarkdownView: View {
    let content: String
    let copyFallbackText: String
    var onReady: (() -> Void)? = nil
    @State private var height: CGFloat
    @State private var isWebViewReady = false
    @State private var pendingWebViewReadyTask: DispatchWorkItem?
    @State private var webViewMountStart: ContinuousClock.Instant = ContinuousClock.now

    init(content: String, copyFallbackText: String? = nil, onReady: (() -> Void)? = nil) {
        self.content = content
        self.copyFallbackText = copyFallbackText ?? content
        self.onReady = onReady
        // Use cached height to prevent 22pt → actual height jump on LazyVStack recreation
        let heightKey = "\(content.hashValue)" as NSString
        if let cached = markdownHeightCache.object(forKey: heightKey) {
            _height = State(initialValue: CGFloat(cached.doubleValue))
        } else {
            // Estimate initial height from content length so the frame is
            // roughly the right size before WKWebView reports its measured
            // height. Without this estimate, the frame is locked at 22pt
            // (one line) until the WebView's JS callback fires — and on
            // macOS 26 we've observed that callback can stall for several
            // seconds (or never arrive), leaving content visibly clipped
            // to a sliver and the bubble appearing empty.
            //
            // Heuristic: ~60 chars per visual line, ~18pt line height,
            // 20pt total padding. Newlines count for an extra line each.
            // Capped at 600pt so we don't reserve a huge frame for a
            // message that turns out to be short.
            let lineCount = max(1, content.split(separator: "\n").count)
            let estimatedLines = max(Double(lineCount),
                                     ceil(Double(content.count) / 60.0))
            // Line-height only (≈13px × 1.6 ≈ 21pt). The bubble's 10pt padding
            // is applied OUTSIDE this view (in ChatBubble), so DON'T add it
            // here — the old `+ 20` double-counted the padding, and when the
            // async JS height measurement is delayed (LazyVStack rows mount at
            // width 0), that too-tall estimate stuck and left ~16pt of phantom
            // space below the text, pushing the action icons far away. A small
            // +4 guards single-line wraps from a 1px clip before measurement.
            let estimatedHeight = min(600.0, estimatedLines * 21.0 + 4.0)
            _height = State(initialValue: CGFloat(max(21.0, estimatedHeight)))
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !isWebViewReady && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NativeMarkdownView(content: content)
                    .opacity(0.94)
                    .transition(.opacity)
            }

            _MarkdownWebView(
                content: content,
                copyFallbackText: copyFallbackText,
                dynamicHeight: $height,
                onRendered: {
                    markWebViewReadyAfterPaint()
                    onReady?()
                }
            )
            .opacity(isWebViewReady ? 1 : 0.01)
        }
        .frame(height: max(height, 22))
        .onAppear {
            webViewMountStart = ContinuousClock.now
            chatRenderPerfLog.info("phase=webview_markdown_mount content_length=\(content.count, privacy: .public) initial_height=\(String(format: "%.1f", Double(height)), privacy: .public)")
        }
        .onChange(of: content) { _ in
            if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pendingWebViewReadyTask?.cancel()
                isWebViewReady = false
                webViewMountStart = ContinuousClock.now
            }
        }
        .onDisappear {
            pendingWebViewReadyTask?.cancel()
            pendingWebViewReadyTask = nil
        }
            .onChange(of: height) { newHeight in
                if newHeight > 22 {
                    let elapsedText = dashboardElapsedMillisecondsText(since: webViewMountStart)
                    chatRenderPerfLog.info("phase=webview_height_changed content_length=\(content.count, privacy: .public) height=\(String(format: "%.1f", Double(newHeight)), privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
                    onReady?()
                }
            }
    }

    private func markWebViewReadyAfterPaint() {
        pendingWebViewReadyTask?.cancel()
        let task = DispatchWorkItem {
            if !isWebViewReady {
                let elapsedText = dashboardElapsedMillisecondsText(since: webViewMountStart)
                chatRenderPerfLog.info("phase=webview_markdown_ready content_length=\(content.count, privacy: .public) height=\(String(format: "%.1f", Double(height)), privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
                withAnimation(.easeInOut(duration: 0.12)) {
                    isWebViewReady = true
                }
            }
        }
        pendingWebViewReadyTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: task)
    }
}

/// WKWebView subclass that forwards scroll events to the parent view,
/// allowing the outer SwiftUI ScrollView to handle page scrolling.
private class ScrollThroughWebView: WKWebView {
    /// Called when the view's width changes (throttled), for height re-measurement.
    var onResize: (() -> Void)?
    var copyFallbackText: String = ""
    private var resizeWorkItem: DispatchWorkItem?

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.size.width
        super.setFrameSize(newSize)
        // Only trigger on width changes (height is managed by dynamicHeight binding)
        if abs(newSize.width - oldWidth) > 1 {
            resizeWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.onResize?()
            }
            resizeWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        }
    }

    override func mouseDown(with event: NSEvent) {
        markActiveForCopy()
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        markActiveForCopy()
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        markActiveForCopy()
        super.mouseUp(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let isCommandC = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            && event.charactersIgnoringModifiers?.lowercased() == "c"
        guard isCommandC, !copyFallbackText.isEmpty else {
            return super.performKeyEquivalent(with: event)
        }

        copySelectionOrFallback(allowFallback: true)
        return true
    }

    func copySelectionOrFallback(allowFallback: Bool, completion: ((Bool) -> Void)? = nil) {
        evaluateJavaScript("window.getSelection().toString()") { [weak self] result, _ in
            guard let self else { return }
            let selected = (result as? String) ?? ""
            let textToCopy: String
            if selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textToCopy = allowFallback ? copyFallbackText : ""
            } else {
                textToCopy = selected
            }

            guard !textToCopy.isEmpty else {
                completion?(false)
                return
            }

            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
            self.clearSelectionAfterCopy()
            completion?(true)
        }
    }

    func prepareForReuseOrDismantle() {
        resizeWorkItem?.cancel()
        resizeWorkItem = nil
        onResize = nil
        copyFallbackText = ""
        stopLoading()
        navigationDelegate = nil
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    private func markActiveForCopy() {
        WebViewMarkdownSelectionRegistry.markActive(self)
        window?.makeFirstResponder(self)
    }

    private func clearSelectionAfterCopy() {
        evaluateJavaScript("window.getSelection().removeAllRanges()")
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }
}

enum WebViewMarkdownSelectionRegistry {
    private static weak var activeWebView: ScrollThroughWebView?

    fileprivate static func markActive(_ webView: ScrollThroughWebView) {
        activeWebView = webView
    }

    fileprivate static func clearIfActive(_ webView: ScrollThroughWebView) {
        if activeWebView === webView {
            activeWebView = nil
        }
    }

    static func copyActiveSelection() -> Bool {
        guard let activeWebView,
              NSApp.keyWindow?.firstResponder === activeWebView else { return false }
        activeWebView.copySelectionOrFallback(allowFallback: false)
        return true
    }
}

private struct _MarkdownWebView: NSViewRepresentable {
    let content: String
    let copyFallbackText: String
    @Binding var dynamicHeight: CGFloat
    var onRendered: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(dynamicHeight: $dynamicHeight, onRendered: onRendered)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = ScrollThroughWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.copyFallbackText = copyFallbackText

        // Wire resize callback to re-measure height when window width changes
        webView.onResize = { [weak webView, weak coordinator = context.coordinator] in
            guard let webView = webView, let coordinator = coordinator else { return }
            coordinator.remeasureHeight(webView: webView)
        }

        let isDark = (colorScheme == .dark)

        // Always paint the full HTML envelope (CSS + MathJax + body) on
        // first mount — synchronously, no transparent shell, no async
        // round trip. This gives the WKWebView a complete styled
        // document immediately. Every subsequent content delta updates
        // the body via JS DOM mutation (see `updateNSView` →
        // `Coordinator.injectBodyHTML`), so we never reload the page,
        // never flash, and never see the "blank then re-render" the
        // previous loadHTMLString-on-every-update path produced.
        //
        // For empty starting content (streaming placeholder before the
        // first delta), `MarkdownHTML.buildHTML("")` is essentially the
        // envelope alone — cheap to build, fine to display as an empty
        // bubble for the brief moment before the first delta arrives.
        let contentHash = content.hashValue
        let cacheKey = "\(isDark ? "d" : "l"):\(contentHash)" as NSString
        let html: String
        if let cachedHTML = markdownHTMLCache.object(forKey: cacheKey) {
            html = cachedHTML as String
        } else {
            html = MarkdownHTML.buildHTML(content, isDark: isDark)
            setCachedMarkdownHTML(html, forKey: cacheKey)
        }
        context.coordinator.lastSource = content
        if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.coordinator.lastRenderedNonEmptySource = content
        }
        context.coordinator.lastIsDark = isDark
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        if let webView = nsView as? ScrollThroughWebView {
            WebViewMarkdownSelectionRegistry.clearIfActive(webView)
            webView.prepareForReuseOrDismantle()
        } else {
            nsView.stopLoading()
            nsView.navigationDelegate = nil
        }
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let isDark = (colorScheme == .dark)
        let coordinator = context.coordinator
        coordinator.onRendered = onRendered
        if let webView = webView as? ScrollThroughWebView {
            webView.copyFallbackText = copyFallbackText
        }

        // Bail when nothing meaningful changed (SwiftUI re-evaluates
        // bodies aggressively).
        guard content != coordinator.lastSource || isDark != coordinator.lastIsDark else { return }

        // Theme change requires a full reload — the CSS (text color,
        // borders, code background) is embedded in the HTML <style>
        // block, not driven by CSS variables. Rare event (user toggling
        // system appearance); a momentary reload-flash is acceptable.
        let isThemeChange = (isDark != coordinator.lastIsDark)
        coordinator.lastSource = content
        coordinator.lastIsDark = isDark
        coordinator.buildGeneration += 1
        let myGen = coordinator.buildGeneration
        let currentContent = content

        coordinator.buildQueue.async { [weak coordinator] in
            guard let coordinator = coordinator else { return }
            if myGen != coordinator.buildGeneration { return }

            let contentHash = currentContent.hashValue
            let cacheKey = "\(isDark ? "d" : "l"):\(contentHash)" as NSString

            if isThemeChange {
                // Build (or fetch) full HTML, reload entire page.
                let html: String
                if let cached = markdownHTMLCache.object(forKey: cacheKey) {
                    html = cached as String
                } else {
                    html = MarkdownHTML.buildHTML(currentContent, isDark: isDark)
                    setCachedMarkdownHTML(html, forKey: cacheKey)
                }
                DispatchQueue.main.async {
                    if myGen != coordinator.buildGeneration { return }
                    coordinator.isPageLoaded = false
                    coordinator.pendingBodyHTML = nil
                    webView.loadHTMLString(html, baseURL: nil)
                }
                return
            }

            let shouldPreserveRenderedContent = currentContent
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty && !coordinator.lastRenderedNonEmptySource.isEmpty
            if shouldPreserveRenderedContent {
                return
            }

            // Content-only delta. Build just the <body> innards and
            // poke them into the live document via JS. No navigation,
            // no parse-from-scratch, no flash. CSS / MathJax / scripts
            // stay loaded.
            let bodyHTML = MarkdownHTML.convertMarkdown(currentContent)

            // Keep the full-HTML cache warm too, so a future cold mount
            // (LazyVStack recycling, theme toggle and back, etc.) hits
            // the sync path in `makeNSView`.
            if markdownHTMLCache.object(forKey: cacheKey) == nil {
                let fullHTML = MarkdownHTML.buildHTML(currentContent, isDark: isDark)
                setCachedMarkdownHTML(fullHTML, forKey: cacheKey)
            }

            DispatchQueue.main.async { [weak coordinator] in
                guard let coordinator = coordinator else { return }
                if myGen != coordinator.buildGeneration { return }

                if !coordinator.isPageLoaded {
                    // Initial navigation from makeNSView still in flight.
                    // Stash; `didFinish` will inject when ready.
                    coordinator.pendingBodyHTML = bodyHTML
                    return
                }
                coordinator.injectBodyHTML(bodyHTML, into: webView) {
                    coordinator.remeasureHeight(webView: webView)
                }
            }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastSource: String = ""
        var lastIsDark: Bool = false
        /// Serial queue ensures only one buildHTML runs at a time
        let buildQueue = DispatchQueue(label: "markdown.build", qos: .utility)
        /// Incremented on each loadHTML call; stale builds check this to skip work
        var buildGeneration: Int = 0
        /// Last non-empty markdown source that reached the WebView. Used to
        /// avoid replacing visible content with a transient empty body while
        /// SwiftUI is recycling rows or a session switch is still loading.
        var lastRenderedNonEmptySource: String = ""
        /// True once the WKWebView has finished its initial navigation —
        /// only then are JS DOM mutations safe to evaluate. Updates that
        /// arrive before this flips are stashed in `pendingBodyHTML` and
        /// flushed by `webView(_:didFinish:)`.
        var isPageLoaded: Bool = false
        /// Latest body-HTML waiting on the first navigation to finish.
        /// Always holds the freshest value; older stashes are overwritten.
        var pendingBodyHTML: String?
        var onRendered: (() -> Void)?
        private var dynamicHeight: Binding<CGFloat>

        init(dynamicHeight: Binding<CGFloat>, onRendered: (() -> Void)?) {
            self.dynamicHeight = dynamicHeight
            self.onRendered = onRendered
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isPageLoaded = true
            if let pending = pendingBodyHTML {
                pendingBodyHTML = nil
                injectBodyHTML(pending, into: webView) { [weak self] in
                    self?.measureHeight(webView: webView, attempt: 0)
                }
            } else {
                measureHeight(webView: webView, attempt: 0)
            }
        }

        /// Replace `document.body.innerHTML` with `bodyHTML` and re-run
        /// MathJax typesetting. Body HTML is shipped over the JS bridge
        /// as a JSON-encoded array element so all escaping (quotes,
        /// backslashes, newlines, unicode) is handled by Foundation —
        /// no fragile manual string mangling.
        func injectBodyHTML(_ bodyHTML: String, into webView: WKWebView, completion: (() -> Void)? = nil) {
            guard let data = try? JSONSerialization.data(withJSONObject: [bodyHTML]),
                  let jsonStr = String(data: data, encoding: .utf8) else {
                completion?()
                return
            }
            let js = """
            (function() {
                var arr = \(jsonStr);
                document.body.innerHTML = arr[0];
                if (window.MathJax && window.MathJax.typesetPromise) {
                    window.MathJax.typesetPromise([document.body]).catch(function(){});
                }
            })();
            """
            webView.evaluateJavaScript(js) { _, _ in
                completion?()
            }
        }

        /// Measure content height, retrying if the WKWebView hasn't received
        /// its layout width yet (which would produce an inflated height).
        private func measureHeight(webView: WKWebView, attempt: Int) {
            // Retry until the WebView reports a real layout width. LazyVStack
            // rows can mount at width 0, and WebKit's body.clientWidth lags the
            // native frame by a few runloop ticks. The old code gave up after
            // 2 tries — if width was still 0 then, the (too-tall) estimate
            // stuck forever, leaving phantom space below the text and pushing
            // the action icons far from the message. Retry ~12× over ~2.4s so a
            // freshly-scrolled-in bubble always converges to its true height.
            let maxAttempts = 12
            guard attempt < maxAttempts else { return }
            let delay: TimeInterval = attempt == 0 ? 0.05 : 0.2
            let measureStart = ContinuousClock.now
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                let frameWidth = webView.bounds.width
                guard frameWidth > 10 else {
                    chatRenderPerfLog.info("phase=webview_measure_deferred attempt=\(attempt, privacy: .public) frame_width=\(String(format: "%.1f", Double(frameWidth)), privacy: .public)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak webView] in
                        guard let self = self, let webView = webView else { return }
                        self.measureHeight(webView: webView, attempt: attempt + 1)
                    }
                    return
                }
                self.evaluateHeight(webView: webView) { newHeight, width in
                    let elapsedText = dashboardElapsedMillisecondsText(since: measureStart)
                    chatRenderPerfLog.info("phase=webview_measure_height attempt=\(attempt, privacy: .public) width=\(String(format: "%.1f", Double(width)), privacy: .public) height=\(String(format: "%.1f", Double(newHeight)), privacy: .public) elapsed_ms=\(elapsedText, privacy: .public)")
                    if width > 10 {
                        self.applyHeight(newHeight)
                        self.onRendered?()
                    } else {
                        // Width still ~0, layout not ready — keep retrying.
                        chatRenderPerfLog.info("phase=webview_measure_retry attempt=\(attempt, privacy: .public) width=\(String(format: "%.1f", Double(width)), privacy: .public)")
                        self.measureHeight(webView: webView, attempt: attempt + 1)
                    }
                }
            }
        }

        /// Re-measure height (called on width change / scroll-in). Delegates to
        /// the retrying measureHeight so a width-0 mount still converges.
        func remeasureHeight(webView: WKWebView) {
            measureHeight(webView: webView, attempt: 0)
        }

        private func evaluateHeight(webView: WKWebView, completion: @escaping (CGFloat, CGFloat) -> Void) {
            let js = "JSON.stringify({h:Math.ceil(document.body.scrollHeight),w:document.body.clientWidth})"
            webView.evaluateJavaScript(js) { result, _ in
                guard let jsonStr = result as? String,
                      let data = jsonStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let h = json["h"] as? CGFloat,
                      let w = json["w"] as? CGFloat, h > 0 else { return }
                DispatchQueue.main.async {
                    // +1 guards against sub-pixel scrollHeight under-report
                    // without leaving a visible gap below the text (was +4).
                    completion(h + 1, w)
                }
            }
        }

        private func applyHeight(_ newHeight: CGFloat) {
            // Only update if height actually changed to avoid SwiftUI re-render loop
            if MarkdownRenderPolicy.shouldApplyMeasuredHeight(current: dynamicHeight.wrappedValue, measured: newHeight) {
                dynamicHeight.wrappedValue = newHeight
            }
            if !lastSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastRenderedNonEmptySource = lastSource
            }
            // Cache height for LazyVStack recreation
            let heightKey = "\(lastSource.hashValue)" as NSString
            markdownHeightCache.setObject(NSNumber(value: Double(newHeight)), forKey: heightKey)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

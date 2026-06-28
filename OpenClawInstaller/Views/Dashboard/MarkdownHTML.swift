import Foundation

// MARK: - Markdown → HTML

enum MarkdownHTML {
    // MARK: - Cached Regex Patterns (Performance optimization)

    /// Cached regex for display math patterns ($$...$$)
    private static let displayMathRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\$\\$([\\s\\S]*?)\\$\\$")
    }()

    /// Cached regex for image markdown ![alt](url)
    private static let imageRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)]+)\\)")
    }()

    /// Cached regex for link markdown [text](url)
    private static let linkRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)")
    }()

    /// Cached regex for bold **text** or __text__
    private static let boldAsteriskRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*")
    }()

    private static let boldUnderscoreRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "__(.+?)__")
    }()

    /// Cached regex for italic *text* or _text_
    private static let italicAsteriskRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "(?<!\\*)\\*(?!\\*)(.+?)(?<!\\*)\\*(?!\\*)")
    }()

    private static let italicUnderscoreRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "(?<![\\w])_(.+?)_(?![\\w])")
    }()

    /// Cached regex for strikethrough ~~text~~
    private static let strikethroughRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "~~(.+?)~~")
    }()

    /// Cached regex for inline code `text`
    private static let inlineCodeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: "`([^`]+)`")
    }()

    static func buildHTML(_ markdown: String, isDark: Bool) -> String {
        let textColor = isDark ? "#e0e0e0" : "#1d1d1f"
        let codeBg = isDark ? "rgba(255,255,255,0.16)" : "rgba(0,0,0,0.10)"
        let borderColor = isDark ? "rgba(255,255,255,0.15)" : "rgba(0,0,0,0.15)"
        let tableBg = isDark ? "rgba(255,255,255,0.04)" : "rgba(0,0,0,0.02)"
        let blockquoteBorder = isDark ? "#555" : "#ccc"
        let blockquoteColor = isDark ? "#aaa" : "#666"
        let linkColor = isDark ? "#6cb6ff" : "#0366d6"

        let body = convertMarkdown(markdown)

        return """
        <html><head><meta charset='utf-8'>
        <script src="https://polyfill.io/v3/polyfill.min.js?features=es6"></script>
        <script id="MathJax-script" async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-mml-chtml.js"></script>
        <script>
        window.MathJax = {
            tex: {
                // Inline math uses LaTeX-style \\( ... \\) ONLY — never single
                // '$'. Customer-support content is full of currency ("$5",
                // "$5 ... $10 discount"), and treating '$' as an inline-math
                // delimiter made MathJax parse the text between two dollar
                // signs as a formula — e.g. it hit a literal '#' and rendered
                // the red error "You can't use 'macro parameter character #'
                // in math mode" right in the chat bubble. \\( ... \\) never
                // collides with natural text.
                inlineMath: [['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                processEscapes: true
            },
            svg: {
                fontCache: 'global'
            }
        };
        </script>
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        html, body { background: transparent; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            font-size: 14px; color: \(textColor); line-height: 1.55;
            -webkit-user-select: text; cursor: text;
            word-wrap: break-word; overflow-wrap: break-word;
            overflow: hidden;
        }
        /* Hug the content: strip the first/last block's outer margins so the
           measured WebView height matches the text exactly. Without this the
           leading/trailing <p> margins (+ body padding) left phantom whitespace
           inside the bubble, pushing the action icons far below the message. */
        body > :first-child { margin-top: 0 !important; }
        body > :last-child { margin-bottom: 0 !important; }
        h1 { font-size: 20px; font-weight: 700; margin: 12px 0 6px; }
        h2 { font-size: 17px; font-weight: 700; margin: 10px 0 5px; }
        h3 { font-size: 15px; font-weight: 600; margin: 8px 0 4px; }
        h4, h5, h6 { font-size: 14px; font-weight: 600; margin: 6px 0 3px; }
        p { margin: 6px 0; }
        code {
            font-family: Menlo, Monaco, monospace; font-size: 13px;
            background: \(codeBg); padding: 1px 4px; border-radius: 3px;
        }
        pre {
            background: \(codeBg); padding: 10px; border-radius: 6px;
            overflow-x: auto; margin: 8px 0;
        }
        pre code { background: none; padding: 0; }
        table { border-collapse: collapse; margin: 8px 0; }
        th, td { border: 1px solid \(borderColor); padding: 5px 10px; text-align: left; font-size: 14px; line-height: 1.55; }
        th { font-weight: 600; }
        tr:nth-child(even) { background: \(tableBg); }
        blockquote {
            border-left: 3px solid \(blockquoteBorder);
            margin: 6px 0; padding: 2px 10px; color: \(blockquoteColor);
        }
        a { color: \(linkColor); text-decoration: none; }
        ul, ol { padding-left: 20px; margin: 4px 0; }
        li { margin: 2px 0; }
        hr { border: none; border-top: 1px solid \(borderColor); margin: 10px 0; }
        img { max-width: 100%; }
        .math-formula { margin: 8px 0; }
        </style></head><body>\(body)</body></html>
        """
    }

    // MARK: - Markdown → HTML conversion

    static func convertMarkdown(_ markdown: String) -> String {
        // Extract & preserve display-math blocks ($$...$$) so markdown
        // inline processing doesn't mangle their contents (e.g. `a_b`
        // becoming italic). We deliberately DO NOT extract single-'$'
        // inline math — '$' is currency in customer-support content, and
        // protecting/round-tripping "$5 ... $10" as a formula is exactly
        // what produced the MathJax "macro parameter character #" error.
        // Real inline math is delimited \\( ... \\) (see the MathJax
        // config in buildHTML) and needs no markdown protection.
        var processedMarkdown = markdown
        var mathPlaceholders: [String: String] = [:]
        var mathCounter = 0

        // Extract display math blocks ($$...$$) first
        if let regex = displayMathRegex {
            let nsString = processedMarkdown as NSString
            let matches = regex.matches(in: processedMarkdown, range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                if let mathRange = Range(match.range, in: processedMarkdown) {
                    let placeholder = ":MATHDISPLAY\(mathCounter):"
                    let formula = String(processedMarkdown[mathRange])
                    mathPlaceholders[placeholder] = formula
                    processedMarkdown.replaceSubrange(mathRange, with: placeholder)
                    mathCounter += 1
                }
            }
        }

        let lines = processedMarkdown.components(separatedBy: "\n")
        // Pre-trim all lines once to avoid repeated trimming in inner loops
        let trimmedLines = lines.map { fastTrim($0) }
        var html = ""
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = trimmedLines[i]

            // Code block
            if startsWithBytes(trimmed, 0x60, 0x60, 0x60) { // ```
                var codeContent = ""
                var closed = false
                i += 1
                while i < lines.count {
                    let codeLine = lines[i]
                    if startsWithBytes(trimmedLines[i], 0x60, 0x60, 0x60) { // ```
                        i += 1
                        closed = true
                        break
                    }
                    if !codeContent.isEmpty { codeContent += "\n" }
                    codeContent += codeLine
                    i += 1
                }
                html += "<pre><code>\(escapeHTML(codeContent))</code></pre>"
                // If unclosed, remaining lines were consumed — content is already in codeContent
                continue
            }

            // Empty line
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Table: starts with | and contains |
            if startsWithByte(trimmed, 0x7C) && trimmed.contains("|") { // |
                var tableLines: [String] = []
                while i < lines.count {
                    let tl = trimmedLines[i]
                    if startsWithByte(tl, 0x7C) && tl.contains("|") {
                        tableLines.append(tl)
                        i += 1
                    } else {
                        break
                    }
                }
                html += renderTable(tableLines)
                continue
            }

            // Heading: # to ######
            if startsWithByte(trimmed, 0x23) { // #
                // Fast UTF-8 scan: count '#' then expect space
                var hashCount = 0
                let tUtf8 = trimmed.utf8
                var hIdx = tUtf8.startIndex
                while hIdx < tUtf8.endIndex && tUtf8[hIdx] == 0x23 { // '#'
                    hashCount += 1
                    hIdx = tUtf8.index(after: hIdx)
                }
                if hashCount >= 1 && hashCount <= 6 && hIdx < tUtf8.endIndex && tUtf8[hIdx] == 0x20 {
                    let headingText = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: hashCount + 1)...])
                    html += "<h\(hashCount)>\(processInline(headingText, mathPlaceholders: mathPlaceholders))</h\(hashCount)>"
                    i += 1
                    continue
                }
            }

            // Horizontal rule — require only dashes/stars/underscores + spaces, at least 3 chars
            if trimmed.utf8.count >= 3 && isHorizontalRule(trimmed) {
                html += "<hr>"
                i += 1
                continue
            }

            // Blockquote
            if startsWithByte(trimmed, 0x3E) { // >
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = trimmedLines[i]
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                        i += 1
                    } else if ql == ">" {
                        quoteLines.append("")
                        i += 1
                    } else if ql.hasPrefix(">") {
                        // Handle >text without space after >
                        quoteLines.append(String(ql.dropFirst(1)))
                        i += 1
                    } else {
                        break
                    }
                }
                html += "<blockquote>\(quoteLines.map { processInline($0, mathPlaceholders: mathPlaceholders) }.joined(separator: "<br>"))</blockquote>"
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                html += "<ul>"
                while i < lines.count {
                    let li = trimmedLines[i]
                    if isUnorderedListItem(li) {
                        html += "<li>\(processInline(String(li.dropFirst(2)), mathPlaceholders: mathPlaceholders))</li>"
                        i += 1
                    } else {
                        break
                    }
                }
                html += "</ul>"
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                html += "<ol>"
                while i < lines.count {
                    let li = trimmedLines[i]
                    if let content = orderedListContent(li) {
                        html += "<li>\(processInline(content, mathPlaceholders: mathPlaceholders))</li>"
                        i += 1
                    } else {
                        break
                    }
                }
                html += "</ol>"
                continue
            }

            // Regular paragraph — collect consecutive non-special lines
            var paraLines: [String] = []
            while i < lines.count {
                let pl = trimmedLines[i]
                if pl.isEmpty || startsWithBytes(pl, 0x60, 0x60, 0x60) || startsWithByte(pl, 0x23)
                    || startsWithByte(pl, 0x7C) || startsWithByte(pl, 0x3E)
                    || isUnorderedListItem(pl) || isOrderedListItem(pl)
                    || isHorizontalRule(pl) {
                    break
                }
                paraLines.append(processInline(pl, mathPlaceholders: mathPlaceholders))
                i += 1
            }
            if !paraLines.isEmpty {
                html += "<p>\(paraLines.joined(separator: "<br>"))</p>"
            } else {
                // Safety: if no pattern matched and paragraph collector didn't consume the line,
                // skip it to prevent infinite loop (e.g., a lone "#" without heading text)
                i += 1
            }
        }

        // Restore all math placeholders
        for (placeholder, formula) in mathPlaceholders {
            html = html.replacingOccurrences(of: placeholder, with: formula)
        }

        return html
    }

    // MARK: - Helpers

    /// Fast check if string starts with given ASCII byte. Uses withCString for zero generic overhead.
    @inline(__always)
    private static func startsWithByte(_ s: String, _ byte: UInt8) -> Bool {
        return s.withCString { ptr in
            UInt8(bitPattern: ptr[0]) == byte
        }
    }

    /// Fast check if string starts with given ASCII bytes. Uses withCString for zero generic overhead.
    @inline(__always)
    private static func startsWithBytes(_ s: String, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Bool {
        return s.withCString { ptr in
            UInt8(bitPattern: ptr[0]) == b0 && UInt8(bitPattern: ptr[1]) == b1 && UInt8(bitPattern: ptr[2]) == b2
        }
    }

    /// Fast whitespace trim using direct UTF-8 byte access.
    /// Avoids CFCharacterSetIsLongCharacterMember and generic iterator/subscript overhead in -Onone.
    /// Only trims ASCII whitespace which matches Markdown semantics.
    private static func fastTrim(_ s: String) -> String {
        // Use withUTF8 for direct pointer access — zero overhead, no generic dispatch
        return s.withCString { cstr -> String in
            var len = 0
            while cstr[len] != 0 { len += 1 }
            guard len > 0 else { return "" }
            var lo = 0
            var hi = len - 1
            while lo <= hi {
                let b = UInt8(bitPattern: cstr[lo])
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { lo += 1 }
                else { break }
            }
            guard lo <= hi else { return "" }
            while hi > lo {
                let b = UInt8(bitPattern: cstr[hi])
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { hi -= 1 }
                else { break }
            }
            if lo == 0 && hi == len - 1 { return s }
            let buf = UnsafeBufferPointer(
                start: UnsafeRawPointer(cstr.advanced(by: lo))
                    .assumingMemoryBound(to: UInt8.self),
                count: hi - lo + 1
            )
            return String(decoding: buf, as: UTF8.self)
        }
    }

    private static func isHorizontalRule(_ s: String) -> Bool {
        return s.withCString { ptr in
            var dashes = 0, stars = 0, underscores = 0
            var i = 0
            while ptr[i] != 0 {
                let b = UInt8(bitPattern: ptr[i])
                switch b {
                case 0x2D: dashes += 1
                case 0x2A: stars += 1
                case 0x5F: underscores += 1
                case 0x20: break
                default: return false
                }
                i += 1
            }
            let total = dashes + stars + underscores
            return total >= 3 && (dashes == total || stars == total || underscores == total)
        }
    }

    private static func isUnorderedListItem(_ s: String) -> Bool {
        return s.withCString { ptr in
            let first = UInt8(bitPattern: ptr[0])
            let second = UInt8(bitPattern: ptr[1])
            return second == 0x20 && (first == 0x2D || first == 0x2A || first == 0x2B)
        }
    }

    private static func isOrderedListItem(_ s: String) -> Bool {
        return s.withCString { ptr in
            var i = 0
            var digitCount = 0
            while ptr[i] != 0 {
                let b = UInt8(bitPattern: ptr[i])
                if b >= 0x30 && b <= 0x39 {
                    digitCount += 1; i += 1
                } else if b == 0x2E && digitCount > 0 {
                    return UInt8(bitPattern: ptr[i + 1]) == 0x20
                } else {
                    return false
                }
            }
            return false
        }
    }

    private static func orderedListContent(_ s: String) -> String? {
        return s.withCString { ptr in
            var i = 0
            var digitCount = 0
            while ptr[i] != 0 {
                let b = UInt8(bitPattern: ptr[i])
                if b >= 0x30 && b <= 0x39 {
                    digitCount += 1; i += 1
                } else if b == 0x2E && digitCount > 0 {
                    guard UInt8(bitPattern: ptr[i + 1]) == 0x20 else { return nil }
                    // Return content after "N. "
                    return String(cString: ptr.advanced(by: i + 2))
                } else {
                    return nil
                }
            }
            return nil
        }
    }

    private static func renderTable(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        var html = "<table>"
        var headerDone = false
        for line in lines {
            let inner = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            let cells = inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            // Check if separator row
            let isSeparator = cells.allSatisfy { cell in
                let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":- "))
                return stripped.isEmpty && !cell.isEmpty
            }
            if isSeparator {
                headerDone = true
                continue
            }
            let tag = !headerDone ? "th" : "td"
            html += "<tr>" + cells.map { "<\(tag)>\(processInline($0))</\(tag)>" }.joined() + "</tr>"
        }
        html += "</table>"
        return html
    }

    // MARK: - Inline markdown processing

    private static func processInline(_ text: String, mathPlaceholders: [String: String] = [:]) -> String {
        var result = escapeHTML(text)
        // Fast path: skip regex if no markdown-related characters present
        let hasMarkdownChars = result.utf8.contains(where: { byte in
            byte == 0x5B    // '['  (links/images)
            || byte == 0x2A // '*'  (bold/italic)
            || byte == 0x5F // '_'  (bold/italic)
            || byte == 0x7E // '~'  (strikethrough)
            || byte == 0x60 // '`'  (inline code)
            || byte == 0x21 // '!'  (images)
        })
        guard hasMarkdownChars else { return result }
        // Images ![alt](url)
        if let regex = imageRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<img src=\"$2\" alt=\"$1\">")
        }
        // Links [text](url)
        if let regex = linkRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<a href=\"$2\">$1</a>")
        }
        // Bold **text**
        if let regex = boldAsteriskRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<strong>$1</strong>")
        }
        // Bold __text__
        if let regex = boldUnderscoreRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<strong>$1</strong>")
        }
        // Italic *text*
        if let regex = italicAsteriskRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<em>$1</em>")
        }
        // Italic _text_
        if let regex = italicUnderscoreRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<em>$1</em>")
        }
        // Strikethrough ~~text~~
        if let regex = strikethroughRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<s>$1</s>")
        }
        // Inline code `text`
        if let regex = inlineCodeRegex {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<code>$1</code>")
        }
        return result
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

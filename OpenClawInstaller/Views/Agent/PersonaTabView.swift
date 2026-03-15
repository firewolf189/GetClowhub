import SwiftUI
import Combine

// MARK: - PersonaTabView

struct PersonaTabView: View {
    @StateObject private var viewModel = PersonaViewModel(
        basePath: NSString("~/.openclaw/workspace").expandingTildeInPath
    )
    @State private var showSaveSuccess = false
    @State private var saveSuccessMessage = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Identity Card
                if let identity = viewModel.parsedIdentity {
                    IdentityCardView(identity: identity)
                }

                // Markdown editors
                MarkdownFileEditor(
                    title: "IDENTITY.md",
                    icon: "person.crop.circle",
                    content: $viewModel.identityContent,
                    isDirty: viewModel.identityDirty,
                    onSave: {
                        viewModel.save(file: .identity)
                        showSaveToast(String(format: String(localized: "%@ saved"), "IDENTITY.md"))
                    }
                )

                MarkdownFileEditor(
                    title: "SOUL.md",
                    icon: "heart.fill",
                    content: $viewModel.soulContent,
                    isDirty: viewModel.soulDirty,
                    onSave: {
                        viewModel.save(file: .soul)
                        showSaveToast(String(format: String(localized: "%@ saved"), "SOUL.md"))
                    }
                )

                MarkdownFileEditor(
                    title: "USER.md",
                    icon: "person.fill",
                    content: $viewModel.userContent,
                    isDirty: viewModel.userDirty,
                    onSave: {
                        viewModel.save(file: .user)
                        showSaveToast(String(format: String(localized: "%@ saved"), "USER.md"))
                    }
                )

                MarkdownFileEditor(
                    title: "MEMORY.md",
                    icon: "brain.head.profile",
                    content: $viewModel.memoryContent,
                    isDirty: viewModel.memoryDirty,
                    onSave: {
                        viewModel.save(file: .memory)
                        showSaveToast(String(format: String(localized: "%@ saved"), "MEMORY.md"))
                    }
                )
            }
            .padding(24)
        }
        .overlay(alignment: .top) {
            if showSaveSuccess {
                SuccessToast(message: saveSuccessMessage)
                    .padding(.top, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showSaveSuccess)
        .onAppear { viewModel.loadAll() }
    }

    private func showSaveToast(_ message: String) {
        saveSuccessMessage = message
        showSaveSuccess = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            showSaveSuccess = false
        }
    }
}

// MARK: - Identity Card

struct IdentityCardView: View {
    let identity: ParsedIdentity

    var body: some View {
        HStack(spacing: 16) {
            Text(identity.emoji)
                .font(.system(size: 48))

            VStack(alignment: .leading, spacing: 4) {
                Text(identity.name)
                    .font(.title2)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Text(identity.creature)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if !identity.vibe.isEmpty {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(identity.vibe)
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Markdown File Editor

struct MarkdownFileEditor: View {
    let title: String
    let icon: String
    @Binding var content: String
    let isDirty: Bool
    let onSave: () -> Void

    @State private var isExpanded = true
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { withAnimation { isExpanded.toggle() } }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 16)

                    Image(systemName: icon)
                        .foregroundColor(.accentColor)

                    Text(title)
                        .font(.headline)

                    if isDirty {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 8, height: 8)
                    }

                    Spacer()

                    if isExpanded {
                        HStack(spacing: 8) {
                            if isDirty {
                                Button("Save") {
                                    onSave()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }

                            Button(action: {
                                withAnimation { isEditing.toggle() }
                            }) {
                                Label(isEditing ? "Preview" : "Edit",
                                      systemImage: isEditing ? "eye" : "pencil")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .onTapGesture {} // prevent header toggle
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Content area
            if isExpanded {
                Divider()

                if isEditing {
                    // Edit mode
                    TextEditor(text: $content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 200, maxHeight: 400)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                } else {
                    // Preview mode - render markdown
                    ScrollView {
                        MarkdownRendererView(markdown: content)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 120, maxHeight: 400)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Markdown Renderer

struct MarkdownRendererView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseLines().enumerated()), id: \.offset) { _, element in
                element
            }
        }
    }

    private func parseLines() -> [AnyView] {
        guard !markdown.isEmpty else {
            return [AnyView(Text("(empty)").foregroundColor(.secondary).italic())]
        }

        var views: [AnyView] = []
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var codeLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                if inCodeBlock {
                    // End code block
                    let code = codeLines.joined(separator: "\n")
                    views.append(AnyView(
                        Text(code)
                            .font(.system(.caption, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                    ))
                    codeLines = []
                    inCodeBlock = false
                } else {
                    inCodeBlock = true
                }
                continue
            }

            if inCodeBlock {
                codeLines.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                views.append(AnyView(Spacer().frame(height: 4)))
            } else if trimmed.hasPrefix("# ") {
                views.append(AnyView(
                    Text(renderInline(String(trimmed.dropFirst(2))))
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 4)
                ))
            } else if trimmed.hasPrefix("## ") {
                views.append(AnyView(
                    Text(renderInline(String(trimmed.dropFirst(3))))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.top, 2)
                ))
            } else if trimmed.hasPrefix("### ") {
                views.append(AnyView(
                    Text(renderInline(String(trimmed.dropFirst(4))))
                        .font(.headline)
                        .padding(.top, 2)
                ))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                views.append(AnyView(
                    Divider().padding(.vertical, 4)
                ))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let bulletText = String(trimmed.dropFirst(2))
                views.append(AnyView(
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(renderInline(bulletText))
                    }
                    .padding(.leading, 8)
                ))
            } else if let match = trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                let numberPart = String(trimmed[match])
                let rest = String(trimmed[match.upperBound...])
                views.append(AnyView(
                    HStack(alignment: .top, spacing: 4) {
                        Text(numberPart)
                            .foregroundColor(.secondary)
                        Text(renderInline(rest))
                    }
                    .padding(.leading, 8)
                ))
            } else if trimmed.hasPrefix("> ") {
                let quoteText = String(trimmed.dropFirst(2))
                views.append(AnyView(
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.5))
                            .frame(width: 3)
                        Text(renderInline(quoteText))
                            .foregroundColor(.secondary)
                            .italic()
                            .padding(.leading, 10)
                            .padding(.vertical, 4)
                    }
                ))
            } else {
                views.append(AnyView(
                    Text(renderInline(trimmed))
                ))
            }
        }

        // Handle unclosed code block
        if inCodeBlock && !codeLines.isEmpty {
            let code = codeLines.joined(separator: "\n")
            views.append(AnyView(
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
            ))
        }

        return views
    }

    /// Render inline markdown: **bold**, *italic*, _italic_, `code`, ~~strike~~
    private func renderInline(_ text: String) -> AttributedString {
        var result = AttributedString(text)

        // Bold: **text**
        applyInlinePattern(&result, pattern: #"\*\*(.+?)\*\*"#) { sub in
            sub.font = .body.bold()
        }

        // Bold: __text__
        applyInlinePattern(&result, pattern: #"__(.+?)__"#) { sub in
            sub.font = .body.bold()
        }

        // Italic: *text* (single asterisk, not preceded/followed by *)
        applyInlinePattern(&result, pattern: #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)"#) { sub in
            sub.font = .body.italic()
        }

        // Italic: _text_
        applyInlinePattern(&result, pattern: #"(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#) { sub in
            sub.font = .body.italic()
        }

        // Code: `text`
        applyInlinePattern(&result, pattern: #"`(.+?)`"#) { sub in
            sub.font = .system(.body, design: .monospaced)
            sub.backgroundColor = Color(NSColor.textBackgroundColor).opacity(0.5)
        }

        return result
    }

    private func applyInlinePattern(_ attrStr: inout AttributedString,
                                     pattern: String,
                                     apply: (inout AttributeContainer) -> Void) {
        let plainText = String(attrStr.characters)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: plainText, range: NSRange(plainText.startIndex..., in: plainText))

        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: plainText),
                  let groupRange = Range(match.range(at: 1), in: plainText) else { continue }
            let innerText = String(plainText[groupRange])

            guard let attrFullRange = attrStr.range(of: String(plainText[fullRange])) else { continue }

            var container = AttributeContainer()
            apply(&container)
            let replacement = AttributedString(innerText, attributes: container)
            attrStr.replaceSubrange(attrFullRange, with: replacement)
        }
    }
}

// MARK: - ParsedIdentity

struct ParsedIdentity {
    var name: String = ""
    var creature: String = ""
    var vibe: String = ""
    var emoji: String = "🤖"
}

// MARK: - PersonaViewModel

class PersonaViewModel: ObservableObject {
    enum FileType {
        case identity, soul, user, memory
    }

    let basePath: String

    @Published var identityContent = ""
    @Published var soulContent = ""
    @Published var userContent = ""
    @Published var memoryContent = ""

    // Track original content to detect changes
    private var identityOriginal = ""
    private var soulOriginal = ""
    private var userOriginal = ""
    private var memoryOriginal = ""

    var identityDirty: Bool { identityContent != identityOriginal }
    var soulDirty: Bool { soulContent != soulOriginal }
    var userDirty: Bool { userContent != userOriginal }
    var memoryDirty: Bool { memoryContent != memoryOriginal }

    var parsedIdentity: ParsedIdentity? {
        guard !identityContent.isEmpty else { return nil }
        return Self.parseIdentity(identityContent)
    }

    init(basePath: String) {
        self.basePath = basePath
    }

    func loadAll() {
        identityContent = readFile("IDENTITY.md")
        soulContent = readFile("SOUL.md")
        userContent = readFile("USER.md")
        memoryContent = readFile("MEMORY.md")
        identityOriginal = identityContent
        soulOriginal = soulContent
        userOriginal = userContent
        memoryOriginal = memoryContent
    }

    func save(file: FileType) {
        switch file {
        case .identity:
            writeFile("IDENTITY.md", content: identityContent)
            identityOriginal = identityContent
        case .soul:
            writeFile("SOUL.md", content: soulContent)
            soulOriginal = soulContent
        case .user:
            writeFile("USER.md", content: userContent)
            userOriginal = userContent
        case .memory:
            writeFile("MEMORY.md", content: memoryContent)
            memoryOriginal = memoryContent
        }
    }

    private func readFile(_ name: String) -> String {
        let path = (basePath as NSString).appendingPathComponent(name)
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private func writeFile(_ name: String, content: String) {
        let path = (basePath as NSString).appendingPathComponent(name)
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func parseIdentity(_ content: String) -> ParsedIdentity {
        var identity = ParsedIdentity()
        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- **Name:**") {
                identity.name = trimmed.replacingOccurrences(of: "- **Name:**", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- **Creature:**") {
                identity.creature = trimmed.replacingOccurrences(of: "- **Creature:**", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- **Vibe:**") {
                identity.vibe = trimmed.replacingOccurrences(of: "- **Vibe:**", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- **Emoji:**") {
                let emoji = trimmed.replacingOccurrences(of: "- **Emoji:**", with: "").trimmingCharacters(in: .whitespaces)
                if !emoji.isEmpty { identity.emoji = emoji }
            }
        }
        return identity
    }
}

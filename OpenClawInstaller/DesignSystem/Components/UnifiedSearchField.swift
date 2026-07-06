import SwiftUI

struct UnifiedSearchField: View {
    let placeholder: String
    @Binding private var text: String

    private let height: CGFloat
    private let cornerRadius: CGFloat
    private let clearHelp: String

    @Environment(\.colorScheme) private var colorScheme

    init(
        placeholder: String,
        text: Binding<String>,
        height: CGFloat = 34,
        cornerRadius: CGFloat = 8,
        clearHelp: String = "Clear search"
    ) {
        self.placeholder = placeholder
        self._text = text
        self.height = height
        self.cornerRadius = cornerRadius
        self.clearHelp = clearHelp
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(clearHelp)
            }
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 1)
        )
    }
}

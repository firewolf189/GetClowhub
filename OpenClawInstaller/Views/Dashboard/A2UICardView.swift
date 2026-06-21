import SwiftUI
import AppKit

private enum A2UICardPalette {
    static let morandiKhakiBackground = adaptiveColor(
        light: NSColor(calibratedRed: 0.94, green: 0.89, blue: 0.79, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.23, green: 0.20, blue: 0.16, alpha: 1.0)
    )

    static let morandiKhakiBorder = adaptiveColor(
        light: NSColor(calibratedRed: 0.70, green: 0.63, blue: 0.47, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.58, green: 0.50, blue: 0.36, alpha: 1.0)
    )

    static let innerCardBackground = adaptiveColor(
        light: NSColor(calibratedRed: 0.98, green: 0.94, blue: 0.86, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.29, green: 0.25, blue: 0.20, alpha: 1.0)
    )

    static let mediaBackground = adaptiveColor(
        light: NSColor(calibratedRed: 0.96, green: 0.91, blue: 0.82, alpha: 1.0),
        dark: NSColor(calibratedRed: 0.25, green: 0.22, blue: 0.18, alpha: 1.0)
    )

    private static func adaptiveColor(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}

struct A2UICardView: View {
    let payload: A2UICardPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = payload.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }

            ForEach(Array(payload.components.enumerated()), id: \.offset) { _, component in
                A2UIComponentView(component: component)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(A2UICardPalette.morandiKhakiBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(A2UICardPalette.morandiKhakiBorder.opacity(0.78), lineWidth: 1)
        )
    }
}

struct A2UIComponentView: View {
    let component: A2UIComponent

    var body: some View {
        switch component.component {
        case .card:
            cardBody
        case .text:
            textBody
        case .image:
            imageBody
        case .icon:
            iconBody
        case .list:
            listBody
        case .row:
            rowBody
        case .column:
            columnBody
        case .divider:
            Divider()
        case .unsupported(let name):
            unsupportedBody(name)
        }
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = component.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .textSelection(.enabled)
            }
            if let subtitle = component.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            childColumn
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(A2UICardPalette.innerCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(A2UICardPalette.morandiKhakiBorder.opacity(0.34), lineWidth: 1)
        )
    }

    private var textBody: some View {
        Text(component.displayText)
            .font(.system(size: 14, weight: .regular))
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var imageBody: some View {
        if let url = component.sanitizedURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    fallbackMedia("Image unavailable")
                case .empty:
                    fallbackMedia("Loading image...")
                @unknown default:
                    fallbackMedia("Image unavailable")
                }
            }
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            fallbackMedia("Unsupported image URL")
        }
    }

    private var iconBody: some View {
        Image(systemName: component.iconName)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
    }

    private var listBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(component.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 7) {
                    Circle()
                        .fill(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 4, height: 4)
                        .padding(.top, 7)
                    Text(item)
                        .font(.system(size: 14, weight: .regular))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            childColumn
        }
    }

    private var rowBody: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(component.children.enumerated()), id: \.offset) { _, child in
                A2UIComponentView(component: child)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var columnBody: some View {
        childColumn
    }

    private var childColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(component.children.enumerated()), id: \.offset) { _, child in
                A2UIComponentView(component: child)
            }
        }
    }

    private func unsupportedBody(_ name: String) -> some View {
        Text("Unsupported component: \(name.isEmpty ? "unknown" : name)")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private func fallbackMedia(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(A2UICardPalette.mediaBackground)
            )
    }
}

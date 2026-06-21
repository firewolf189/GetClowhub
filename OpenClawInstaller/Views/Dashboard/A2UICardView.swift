import SwiftUI

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
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
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
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.72))
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
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.65))
            )
    }
}

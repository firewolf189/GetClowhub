import SwiftUI

struct SettingsCollapsibleContent<Content: View>: View {
    private static var expansionAnimation: Animation {
        .easeInOut(duration: 0.18)
    }

    private static var contentTransition: AnyTransition {
        .asymmetric(insertion: .opacity, removal: .identity)
    }

    let isExpanded: Bool
    let spacing: CGFloat
    let content: Content

    init(
        isExpanded: Bool,
        spacing: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if isExpanded {
                VStack(alignment: .leading, spacing: spacing) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(Self.contentTransition)
                .clipped()
            }
        }
        .animation(Self.expansionAnimation, value: isExpanded)
        .clipped()
    }
}

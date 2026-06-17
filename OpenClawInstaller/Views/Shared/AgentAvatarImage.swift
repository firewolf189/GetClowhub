import SwiftUI

struct AgentAvatarImage: View {
    let size: CGFloat

    var body: some View {
        Image("AgentAvatar")
            .resizable()
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

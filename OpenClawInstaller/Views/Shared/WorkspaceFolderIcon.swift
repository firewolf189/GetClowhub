import SwiftUI

struct WorkspaceFolderIcon: View {
    let isExpanded: Bool
    var size: CGFloat = 20

    var body: some View {
        Image(isExpanded ? "WorkspaceFolderOpenIcon" : "WorkspaceFolderClosedIcon")
            .resizable()
            .antialiased(true)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

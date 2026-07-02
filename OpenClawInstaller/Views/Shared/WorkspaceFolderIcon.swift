import SwiftUI

struct WorkspaceFolderIcon: View {
    let isExpanded: Bool
    var size: CGFloat = 20

    private var strokeWidth: CGFloat {
        max(1.35, size * 0.08)
    }

    var body: some View {
        Group {
            if isExpanded {
                OpenWorkspaceFolderShape()
                    .stroke(style: strokeStyle)
            } else {
                ClosedWorkspaceFolderShape()
                    .stroke(style: strokeStyle)
            }
        }
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: strokeWidth,
            lineCap: .round,
            lineJoin: .round
        )
    }
}

struct ClosedWorkspaceFolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        return Path { path in
            path.move(to: CGPoint(x: x + w * 0.17, y: y + h * 0.34))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.31, y: y + h * 0.23),
                control: CGPoint(x: x + w * 0.18, y: y + h * 0.26)
            )
            path.addLine(to: CGPoint(x: x + w * 0.44, y: y + h * 0.23))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.54, y: y + h * 0.32),
                control: CGPoint(x: x + w * 0.49, y: y + h * 0.23)
            )
            path.addLine(to: CGPoint(x: x + w * 0.80, y: y + h * 0.32))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.88, y: y + h * 0.40),
                control: CGPoint(x: x + w * 0.85, y: y + h * 0.32)
            )
            path.addLine(to: CGPoint(x: x + w * 0.88, y: y + h * 0.72))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.78, y: y + h * 0.82),
                control: CGPoint(x: x + w * 0.88, y: y + h * 0.78)
            )
            path.addLine(to: CGPoint(x: x + w * 0.22, y: y + h * 0.82))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.12, y: y + h * 0.72),
                control: CGPoint(x: x + w * 0.12, y: y + h * 0.78)
            )
            path.addLine(to: CGPoint(x: x + w * 0.12, y: y + h * 0.44))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.17, y: y + h * 0.34),
                control: CGPoint(x: x + w * 0.12, y: y + h * 0.38)
            )
            path.closeSubpath()

            path.move(to: CGPoint(x: x + w * 0.13, y: y + h * 0.43))
            path.addLine(to: CGPoint(x: x + w * 0.87, y: y + h * 0.43))
        }
    }
}

struct OpenWorkspaceFolderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        return Path { path in
            path.move(to: CGPoint(x: x + w * 0.17, y: y + h * 0.36))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.31, y: y + h * 0.25),
                control: CGPoint(x: x + w * 0.18, y: y + h * 0.28)
            )
            path.addLine(to: CGPoint(x: x + w * 0.43, y: y + h * 0.25))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.53, y: y + h * 0.34),
                control: CGPoint(x: x + w * 0.48, y: y + h * 0.25)
            )
            path.addLine(to: CGPoint(x: x + w * 0.81, y: y + h * 0.34))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.88, y: y + h * 0.42),
                control: CGPoint(x: x + w * 0.86, y: y + h * 0.34)
            )
            path.addLine(to: CGPoint(x: x + w * 0.88, y: y + h * 0.49))

            path.move(to: CGPoint(x: x + w * 0.13, y: y + h * 0.45))
            path.addLine(to: CGPoint(x: x + w * 0.87, y: y + h * 0.45))

            path.move(to: CGPoint(x: x + w * 0.16, y: y + h * 0.48))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.30, y: y + h * 0.39),
                control: CGPoint(x: x + w * 0.19, y: y + h * 0.42)
            )
            path.addLine(to: CGPoint(x: x + w * 0.83, y: y + h * 0.39))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.89, y: y + h * 0.47),
                control: CGPoint(x: x + w * 0.88, y: y + h * 0.40)
            )
            path.addLine(to: CGPoint(x: x + w * 0.77, y: y + h * 0.78))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.66, y: y + h * 0.84),
                control: CGPoint(x: x + w * 0.74, y: y + h * 0.84)
            )
            path.addLine(to: CGPoint(x: x + w * 0.20, y: y + h * 0.84))
            path.addQuadCurve(
                to: CGPoint(x: x + w * 0.11, y: y + h * 0.74),
                control: CGPoint(x: x + w * 0.12, y: y + h * 0.83)
            )
            path.addLine(to: CGPoint(x: x + w * 0.16, y: y + h * 0.48))
            path.closeSubpath()
        }
    }
}

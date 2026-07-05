import SwiftUI

struct AgentAvatarImage: View {
    let size: CGFloat
    var isExpanded: Bool = false

    var body: some View {
        Group {
            if isExpanded {
                AgentOpenFaceShape()
                    .stroke(style: strokeStyle)
            } else {
                AgentClosedFaceShape()
                    .stroke(style: strokeStyle)
            }
        }
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var strokeStyle: StrokeStyle {
        StrokeStyle(
            lineWidth: max(1.35, size * 0.08),
            lineCap: .round,
            lineJoin: .round
        )
    }
}

private struct AgentClosedFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            drawClosedFace(in: agentFaceDrawingRect(in: rect), into: &path)
        }
    }

    private func drawClosedFace(in rect: CGRect, into path: inout Path) {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        drawClosedEye(in: rect, centerX: x + w * 0.37, into: &path)
        drawClosedEye(in: rect, centerX: x + w * 0.63, into: &path)

        path.move(to: CGPoint(x: x + w * 0.42, y: y + h * 0.57))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.58, y: y + h * 0.57),
            control: CGPoint(x: x + w * 0.50, y: y + h * 0.68)
        )
    }

    private func drawClosedEye(in rect: CGRect, centerX: CGFloat, into path: inout Path) {
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: centerX - w * 0.06, y: y + h * 0.48))
        path.addQuadCurve(
            to: CGPoint(x: centerX + w * 0.06, y: y + h * 0.48),
            control: CGPoint(x: centerX, y: y + h * 0.35)
        )
    }
}

private struct AgentOpenFaceShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            drawOpenFace(in: agentFaceDrawingRect(in: rect), into: &path)
        }
    }

    private func drawOpenFace(in rect: CGRect, into path: inout Path) {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: x + w * 0.31, y: y + h * 0.48))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.43, y: y + h * 0.48),
            control: CGPoint(x: x + w * 0.37, y: y + h * 0.34)
        )

        path.move(to: CGPoint(x: x + w * 0.63, y: y + h * 0.37))
        path.addLine(to: CGPoint(x: x + w * 0.63, y: y + h * 0.49))

        path.move(to: CGPoint(x: x + w * 0.43, y: y + h * 0.55))
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.57, y: y + h * 0.55),
            control: CGPoint(x: x + w * 0.50, y: y + h * 0.50)
        )
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.50, y: y + h * 0.72),
            control: CGPoint(x: x + w * 0.58, y: y + h * 0.72)
        )
        path.addQuadCurve(
            to: CGPoint(x: x + w * 0.43, y: y + h * 0.55),
            control: CGPoint(x: x + w * 0.42, y: y + h * 0.72)
        )
        path.closeSubpath()
    }
}

private func agentFaceDrawingRect(in rect: CGRect) -> CGRect {
    rect.insetBy(dx: -rect.width * 0.42, dy: -rect.height * 0.34)
}

import SwiftUI

// MARK: - Outer Status Rings

struct StatusRingsView: View {
    let phase: JarvisPhase

    @State private var outerRot: Double  = 0
    @State private var middleRot: Double = 0
    @State private var glowPulse: Double = 0.3

    private var accent: Color { phase.accentColor }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                // Outer decorative ring
                AngularRingView(
                    radius: size * 0.47,
                    dashes: 96,
                    dashLength: 4,
                    gapLength: 10,
                    lineWidth: 1,
                    color: accent.opacity(0.18)
                )
                .rotationEffect(.degrees(outerRot))

                // Middle segment ring
                SegmentRingView(
                    radius: size * 0.43,
                    segments: 12,
                    phase: phase
                )
                .rotationEffect(.degrees(-middleRot))

                // Corner brackets - top left
                CornerBracket(corner: .topLeft, color: accent)
                    .frame(width: 60, height: 60)
                    .position(x: 80, y: 80)
                    .opacity(0.8)

                // Corner brackets - top right
                CornerBracket(corner: .topRight, color: accent)
                    .frame(width: 60, height: 60)
                    .position(x: geo.size.width - 80, y: 80)
                    .opacity(0.8)

                // Corner brackets - bottom left
                CornerBracket(corner: .bottomLeft, color: accent)
                    .frame(width: 60, height: 60)
                    .position(x: 80, y: geo.size.height - 80)
                    .opacity(0.8)

                // Corner brackets - bottom right
                CornerBracket(corner: .bottomRight, color: accent)
                    .frame(width: 60, height: 60)
                    .position(x: geo.size.width - 80, y: geo.size.height - 80)
                    .opacity(0.8)
            }
        }
        .onAppear { startRotations() }
        .onChange(of: phase.ringSpeed) { _ in startRotations() }
    }

    private func startRotations() {
        withAnimation(.linear(duration: phase.ringSpeed * 2.5).repeatForever(autoreverses: false)) {
            outerRot = 360
        }
        withAnimation(.linear(duration: phase.ringSpeed * 4).repeatForever(autoreverses: false)) {
            middleRot = 360
        }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            glowPulse = 0.7
        }
    }
}

// MARK: - Segment Ring (status indicators)

struct SegmentRingView: View {
    let radius: CGFloat
    let segments: Int
    let phase: JarvisPhase

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let segAngle = 2 * Double.pi / Double(segments)
            let gap: Double = 0.08

            for i in 0..<segments {
                let startA = Double(i) * segAngle + gap / 2 - .pi / 2
                let endA   = startA + segAngle - gap

                let isHighlighted = phase.isActive && i % 3 == 0

                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .radians(startA),
                    endAngle:   .radians(endA),
                    clockwise:  false
                )

                let color = isHighlighted
                    ? phase.accentColor.opacity(0.8)
                    : phase.accentColor.opacity(0.25)

                ctx.stroke(path, with: .color(color), lineWidth: isHighlighted ? 3 : 1.5)
            }
        }
        .frame(width: radius * 2 + 10, height: radius * 2 + 10)
    }
}

// MARK: - Corner Bracket

enum CornerType { case topLeft, topRight, bottomLeft, bottomRight }

struct CornerBracket: View {
    let corner: CornerType
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let len: CGFloat = size.width * 0.65
            let lw: CGFloat  = 2

            var hPath = Path()
            var vPath = Path()

            switch corner {
            case .topLeft:
                hPath.move(to: .init(x: 0, y: 0))
                hPath.addLine(to: .init(x: len, y: 0))
                vPath.move(to: .init(x: 0, y: 0))
                vPath.addLine(to: .init(x: 0, y: len))
            case .topRight:
                hPath.move(to: .init(x: size.width, y: 0))
                hPath.addLine(to: .init(x: size.width - len, y: 0))
                vPath.move(to: .init(x: size.width, y: 0))
                vPath.addLine(to: .init(x: size.width, y: len))
            case .bottomLeft:
                hPath.move(to: .init(x: 0, y: size.height))
                hPath.addLine(to: .init(x: len, y: size.height))
                vPath.move(to: .init(x: 0, y: size.height))
                vPath.addLine(to: .init(x: 0, y: size.height - len))
            case .bottomRight:
                hPath.move(to: .init(x: size.width, y: size.height))
                hPath.addLine(to: .init(x: size.width - len, y: size.height))
                vPath.move(to: .init(x: size.width, y: size.height))
                vPath.addLine(to: .init(x: size.width, y: size.height - len))
            }

            ctx.stroke(hPath, with: .color(color), lineWidth: lw)
            ctx.stroke(vPath, with: .color(color), lineWidth: lw)
        }
    }
}

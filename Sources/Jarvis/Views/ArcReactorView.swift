import SwiftUI

// MARK: - Arc Reactor (Central animated element)

struct ArcReactorView: View {
    let phase: JarvisPhase
    let audioLevel: Float

    @State private var ring1Angle: Double = 0
    @State private var ring2Angle: Double = 0
    @State private var ring3Angle: Double = 0
    @State private var corePulse: Double = 1.0
    @State private var outerGlow: Double = 0.5
    @State private var innerRotation: Double = 0

    private var accent: Color { phase.accentColor }
    private var speed: Double { phase.ringSpeed }

    var body: some View {
        ZStack {
            // Outer ambient glow
            Circle()
                .fill(accent.opacity(outerGlow * 0.2))
                .frame(width: 340, height: 340)
                .blur(radius: 60)
                .scaleEffect(1 + CGFloat(audioLevel) * 0.3)
                .animation(.easeOut(duration: 0.1), value: audioLevel)

            // Ring 3 — slowest, largest
            AngularRingView(
                radius: 155,
                dashes: 48,
                dashLength: 8,
                gapLength: 6,
                lineWidth: 1,
                color: accent.opacity(0.35)
            )
            .rotationEffect(.degrees(ring3Angle))

            // Ring 2 — medium
            AngularRingView(
                radius: 128,
                dashes: 32,
                dashLength: 12,
                gapLength: 8,
                lineWidth: 1.5,
                color: accent.opacity(0.55)
            )
            .rotationEffect(.degrees(-ring2Angle))

            // Ring 1 — fastest, innermost
            AngularRingView(
                radius: 105,
                dashes: 16,
                dashLength: 18,
                gapLength: 14,
                lineWidth: 2,
                color: accent.opacity(0.75)
            )
            .rotationEffect(.degrees(ring1Angle))

            // Tick ring — static reference
            TickRingView(radius: 165, ticks: 72, color: accent.opacity(0.2))

            // Inner hex pattern
            HexPatternCircle(color: accent, rotation: innerRotation)
                .frame(width: 140, height: 140)
                .clipShape(Circle())

            // Core glow layers
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.95),
                            accent.opacity(0.9),
                            accent.opacity(0.4),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 55
                    )
                )
                .frame(width: 110, height: 110)
                .scaleEffect(corePulse + CGFloat(audioLevel) * 0.15)
                .shadow(color: accent, radius: 30, x: 0, y: 0)
                .shadow(color: accent.opacity(0.5), radius: 60, x: 0, y: 0)
                .animation(.easeOut(duration: 0.06), value: audioLevel)

            // Core inner circle
            Circle()
                .fill(accent)
                .frame(width: 38, height: 38)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
                )
                .shadow(color: accent, radius: 20)

            // Triangle pattern inside core (arc reactor detail)
            ArcReactorTriangles(color: Color.white.opacity(0.5))
                .frame(width: 22, height: 22)
        }
        .frame(width: 340, height: 340)
        .onAppear { startAnimations() }
        .onChange(of: speed) { _ in startAnimations() }
    }

    private func startAnimations() {
        withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
            ring1Angle = 360
        }
        withAnimation(.linear(duration: speed * 1.7).repeatForever(autoreverses: false)) {
            ring2Angle = 360
        }
        withAnimation(.linear(duration: speed * 2.8).repeatForever(autoreverses: false)) {
            ring3Angle = 360
        }
        withAnimation(.linear(duration: speed * 0.6).repeatForever(autoreverses: false)) {
            innerRotation = 360
        }
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            corePulse = 1.06
        }
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            outerGlow = 0.8
        }
    }
}

// MARK: - Dashed Angular Ring

struct AngularRingView: View {
    let radius: CGFloat
    let dashes: Int
    let dashLength: CGFloat
    let gapLength: CGFloat
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    dash: [dashLength, gapLength]
                )
            )
            .frame(width: radius * 2, height: radius * 2)
    }
}

// MARK: - Tick Ring

struct TickRingView: View {
    let radius: CGFloat
    let ticks: Int
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for i in 0..<ticks {
                let angle = Double(i) / Double(ticks) * 2 * .pi - .pi / 2
                let isMajor = i % 6 == 0
                let tickLen: CGFloat = isMajor ? 10 : 5
                let innerR = radius - tickLen
                let outerR = radius

                let p1 = CGPoint(x: center.x + cos(angle) * innerR,
                                 y: center.y + sin(angle) * innerR)
                let p2 = CGPoint(x: center.x + cos(angle) * outerR,
                                 y: center.y + sin(angle) * outerR)

                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)
                ctx.stroke(path, with: .color(color), lineWidth: isMajor ? 1.5 : 0.8)
            }
        }
        .frame(width: radius * 2 + 20, height: radius * 2 + 20)
    }
}

// MARK: - Hex Pattern Circle (inner detail)

struct HexPatternCircle: View {
    let color: Color
    var rotation: Double

    var body: some View {
        Canvas { ctx, size in
            let hexR: CGFloat = 12
            let w = hexR * 2
            let h = hexR * sqrt(3)
            let cols = Int(size.width / w) + 3
            let rows = Int(size.height / h) + 3

            for row in -1..<rows {
                for col in -1..<cols {
                    let ox = (row % 2 == 0) ? 0.0 : w * 0.5
                    let cx = CGFloat(col) * w + ox
                    let cy = CGFloat(row) * h

                    var path = Path()
                    for i in 0..<6 {
                        let a = CGFloat(i) * .pi / 3 - .pi / 6
                        let px = cx + hexR * cos(a)
                        let py = cy + hexR * sin(a)
                        if i == 0 { path.move(to: .init(x: px, y: py)) }
                        else       { path.addLine(to: .init(x: px, y: py)) }
                    }
                    path.closeSubpath()
                    ctx.stroke(path, with: .color(color.opacity(0.25)), lineWidth: 0.6)
                }
            }
        }
        .rotationEffect(.degrees(rotation))
    }
}

// MARK: - Arc Reactor Triangles (core detail)

struct ArcReactorTriangles: View {
    let color: Color

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let r: CGFloat = size.width / 2

            for i in 0..<3 {
                let angle = Double(i) * 2 * .pi / 3
                let p1 = CGPoint(x: center.x + cos(angle) * r,
                                 y: center.y + sin(angle) * r)
                let p2Angle = angle + .pi * 2 / 3
                let p2 = CGPoint(x: center.x + cos(p2Angle) * r,
                                 y: center.y + sin(p2Angle) * r)

                var path = Path()
                path.move(to: center)
                path.addLine(to: p1)
                path.addLine(to: p2)
                path.closeSubpath()
                ctx.fill(path, with: .color(color))
            }
        }
    }
}

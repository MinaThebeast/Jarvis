import SwiftUI

// MARK: - Full Screen Futuristic Background

struct BackgroundView: View {
    let phase: JarvisPhase
    @State private var scanOffset: CGFloat = -300
    @State private var gridPulse: Double = 0.4

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Deep space base
                Color.jarvisDark.ignoresSafeArea()

                // Subtle radial gradient from center
                RadialGradient(
                    colors: [
                        phase.accentColor.opacity(0.08),
                        Color.jarvisDark.opacity(0.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(geo.size.width, geo.size.height) * 0.7
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.5), value: phase.accentColor)

                // Hex grid
                HexGridCanvas(color: phase.accentColor, opacity: gridPulse)
                    .ignoresSafeArea()

                // Moving scanline
                ScanlineView(scanOffset: $scanOffset, geo: geo)
                    .ignoresSafeArea()
            }
        }
        .onAppear { startAnimations() }
        .onChange(of: phase.isActive) { _ in
            withAnimation(.easeInOut(duration: 0.8)) {
                gridPulse = phase.isActive ? 0.65 : 0.4
            }
        }
    }

    private func startAnimations() {
        // Scanline loop
        withAnimation(
            .linear(duration: 8)
            .repeatForever(autoreverses: false)
        ) {
            scanOffset = 2000
        }

        // Grid pulse
        withAnimation(
            .easeInOut(duration: 3)
            .repeatForever(autoreverses: true)
        ) {
            gridPulse = phase.isActive ? 0.75 : 0.5
        }
    }
}

// MARK: - Hex Grid Canvas

struct HexGridCanvas: View {
    let color: Color
    let opacity: Double

    var body: some View {
        Canvas { ctx, size in
            let hexSize: CGFloat = 38
            let w  = hexSize * 2
            let h  = hexSize * sqrt(3)
            let cols = Int(size.width  / w)  + 3
            let rows = Int(size.height / h)  + 3

            for row in -1..<rows {
                for col in -1..<cols {
                    let offsetX = (row % 2 == 0) ? 0.0 : w * 0.5
                    let cx = CGFloat(col) * w + offsetX - w * 0.5
                    let cy = CGFloat(row) * h - h * 0.5

                    var path = Path()
                    for i in 0..<6 {
                        let angle = CGFloat(i) * .pi / 3 - .pi / 6
                        let px = cx + hexSize * cos(angle)
                        let py = cy + hexSize * sin(angle)
                        if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                        else       { path.addLine(to: CGPoint(x: px, y: py)) }
                    }
                    path.closeSubpath()
                    ctx.stroke(path, with: .color(color.opacity(opacity * 0.45)), lineWidth: 0.5)
                }
            }
        }
        .animation(.easeInOut(duration: 1.5), value: opacity)
    }
}

// MARK: - Scanline

struct ScanlineView: View {
    @Binding var scanOffset: CGFloat
    let geo: GeometryProxy

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.jarvisBlue.opacity(0.04),
                        Color.jarvisBlue.opacity(0.08),
                        Color.jarvisBlue.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: geo.size.width, height: 300)
            .offset(y: scanOffset)
            .allowsHitTesting(false)
    }
}

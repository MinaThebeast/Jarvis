import SwiftUI

// MARK: - Circular Waveform

struct WaveformView: View {
    let phase: JarvisPhase
    let audioLevel: Float

    private let barCount = 64
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.05, count: 64)

    private var accent: Color { phase.accentColor }
    private var isActive: Bool { phase.isActive }

    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let baseRadius: CGFloat = 185
            let maxBarLen: CGFloat  = 55

            for i in 0..<barCount {
                let angle  = Double(i) / Double(barCount) * 2 * .pi - .pi / 2
                let amp    = amplitudes[i]
                let barLen = maxBarLen * amp

                let innerR = baseRadius
                let outerR = baseRadius + barLen

                let p1 = CGPoint(x: center.x + cos(angle) * innerR,
                                 y: center.y + sin(angle) * innerR)
                let p2 = CGPoint(x: center.x + cos(angle) * outerR,
                                 y: center.y + sin(angle) * outerR)

                var path = Path()
                path.move(to: p1)
                path.addLine(to: p2)

                let opacity = 0.5 + Double(amp) * 0.5
                ctx.stroke(
                    path,
                    with: .color(accent.opacity(opacity)),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
            }
        }
        .frame(width: 500, height: 500)
        .onReceive(
            Timer.publish(every: 0.06, on: .main, in: .common).autoconnect()
        ) { _ in
            updateAmplitudes()
        }
    }

    private func updateAmplitudes() {
        let base = isActive ? CGFloat(audioLevel) : 0.0
        withAnimation(.easeOut(duration: 0.06)) {
            for i in 0..<barCount {
                // Each bar gets a slightly randomized value around the base level
                let noise: CGFloat = isActive
                    ? .random(in: -0.25...0.25)
                    : .random(in: -0.03...0.03)
                let target = max(0.03, min(1.0, base + noise))
                // Smooth toward target
                amplitudes[i] = amplitudes[i] * 0.55 + target * 0.45
            }
        }
    }
}

// MARK: - Linear Waveform (bottom bar)

struct LinearWaveformView: View {
    let phase: JarvisPhase
    let audioLevel: Float

    private let barCount = 80
    @State private var amplitudes: [CGFloat] = Array(repeating: 0.05, count: 80)

    private var accent: Color { phase.accentColor }
    private var isActive: Bool { phase.isActive }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor(index: i))
                    .frame(width: 3, height: max(4, amplitudes[i] * 60))
                    .animation(.easeOut(duration: 0.06), value: amplitudes[i])
            }
        }
        .frame(height: 60)
        .onReceive(
            Timer.publish(every: 0.07, on: .main, in: .common).autoconnect()
        ) { _ in
            updateAmplitudes()
        }
    }

    private func barColor(index: Int) -> Color {
        let center = barCount / 2
        let dist   = abs(index - center)
        let fade   = 1.0 - Double(dist) / Double(center) * 0.5
        return accent.opacity(fade * (0.4 + Double(amplitudes[index]) * 0.6))
    }

    private func updateAmplitudes() {
        let base = isActive ? CGFloat(audioLevel) : 0.0
        for i in 0..<barCount {
            let noise: CGFloat = isActive
                ? .random(in: -0.3...0.3)
                : .random(in: -0.02...0.02)
            let target = max(0.02, min(1.0, base + noise))
            amplitudes[i] = amplitudes[i] * 0.55 + target * 0.45
        }
    }
}

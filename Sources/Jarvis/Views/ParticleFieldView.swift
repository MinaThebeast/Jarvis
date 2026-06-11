import SwiftUI

// MARK: - Ambient Particle Field

struct ParticleFieldView: View {
    let phase: JarvisPhase
    private let particleCount = 60

    @State private var particles: [Particle] = []

    private struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var opacity: Double
        var speed: CGFloat
        var angle: Double
        var twinklePhase: Double
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                for p in particles {
                    let twinkle = 0.3 + sin(p.twinklePhase) * 0.35
                    var path = Path()
                    path.addEllipse(in: CGRect(
                        x: p.x - p.size / 2,
                        y: p.y - p.size / 2,
                        width: p.size,
                        height: p.size
                    ))
                    ctx.fill(path, with: .color(
                        phase.accentColor.opacity(max(0, twinkle * p.opacity))
                    ))
                }
            }
            .onAppear {
                spawnParticles(in: geo.size)
                startAnimation()
            }
            .onReceive(
                Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
            ) { _ in
                tickParticles(bounds: geo.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func spawnParticles(in size: CGSize) {
        particles = (0..<particleCount).map { _ in
            Particle(
                x:            .random(in: 0...size.width),
                y:            .random(in: 0...size.height),
                size:         .random(in: 1...3.5),
                opacity:      .random(in: 0.2...0.8),
                speed:        .random(in: 0.1...0.6),
                angle:        .random(in: 0...(2 * .pi)),
                twinklePhase: .random(in: 0...(2 * .pi))
            )
        }
    }

    private func startAnimation() {}

    private func tickParticles(bounds: CGSize) {
        for i in 0..<particles.count {
            particles[i].x += cos(particles[i].angle) * particles[i].speed
            particles[i].y += sin(particles[i].angle) * particles[i].speed
            particles[i].twinklePhase += 0.04

            // Wrap around
            if particles[i].x < -10 { particles[i].x = bounds.width + 10 }
            if particles[i].x > bounds.width + 10 { particles[i].x = -10 }
            if particles[i].y < -10 { particles[i].y = bounds.height + 10 }
            if particles[i].y > bounds.height + 10 { particles[i].y = -10 }
        }
    }
}

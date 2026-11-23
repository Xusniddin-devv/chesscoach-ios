import SwiftUI

/// A 1.2 s burst of flat rectangles in the accent and board colours, drawn in one `Canvas`.
/// Plays once; draws nothing when Reduce Motion is on.
struct ConfettiBurst: View {
    static let duration: Double = 1.2
    /// Waits for the sheet to finish sliding up, so the burst plays over a still sheet.
    static let delay: Double = 0.45

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now.addingTimeInterval(ConfettiBurst.delay)
    @State private var done = false
    @State private var particles = (0..<70).map { _ in Particle() }

    struct Particle {
        let angle = Double.random(in: -.pi * 0.85 ... -.pi * 0.15)  // upward fan
        let speed = Double.random(in: 300...620)
        let spin = Double.random(in: -9...9)
        let size = CGSize(width: .random(in: 6...10), height: .random(in: 3...5))
        let color = [DS.Color.accent, DS.Color.boardLight, DS.Color.boardDark].randomElement()!
    }

    var body: some View {
        if !reduceMotion && !done {
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSince(start)
                Canvas { context, size in
                    guard t >= 0, t < Self.duration else { return }
                    let origin = CGPoint(x: size.width / 2, y: 140)  // behind the result line
                    let fade = 1 - max(0, (t - Self.duration * 0.6) / (Self.duration * 0.4))
                    for p in particles {
                        let x = origin.x + cos(p.angle) * p.speed * t
                        let y = origin.y + sin(p.angle) * p.speed * t + 900 * t * t
                        var c = context
                        c.opacity = fade
                        c.translateBy(x: x, y: y)
                        c.rotate(by: .radians(p.spin * t))
                        let rect = CGRect(origin: CGPoint(x: -p.size.width / 2, y: -p.size.height / 2), size: p.size)
                        c.fill(Path(rect), with: .color(p.color))
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task {
                try? await Task.sleep(for: .seconds(Self.delay + Self.duration))
                done = true
            }
        }
    }
}

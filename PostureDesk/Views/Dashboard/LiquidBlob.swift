import SwiftUI

// MARK: - Liquid Blob Shape

/// An organic, continuously morphing blob shape driven by overlapping sine waves.
struct LiquidBlob: Shape {
    var phase: Double
    var intensity: CGFloat = 1.0 // 0 = perfect circle, 1 = full wobble

    private static let pointCount = 8
    // Each point gets unique frequency triplets for non-repeating patterns
    private static let frequencies: [(Double, Double, Double)] = [
        (0.71, 1.31, 2.13), (0.83, 1.17, 1.97),
        (0.67, 1.43, 2.29), (0.79, 1.23, 2.07),
        (0.73, 1.37, 2.19), (0.87, 1.19, 1.91),
        (0.69, 1.41, 2.23), (0.81, 1.29, 2.03),
    ]
    private static let phaseOffsets: [Double] = [
        0, 0.79, 1.57, 2.36, 3.14, 3.93, 4.71, 5.50
    ]

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let baseRadius = min(rect.width, rect.height) / 2
        // 12% amplitude — visible organic wobble at any size
        let amplitude = baseRadius * 0.12 * intensity

        var points: [CGPoint] = []
        let angleStep = (2 * Double.pi) / Double(Self.pointCount)

        for i in 0..<Self.pointCount {
            let f = Self.frequencies[i]
            let po = Self.phaseOffsets[i]
            let wave1 = sin(f.0 * phase + po) * 0.5
            let wave2 = sin(f.1 * phase + po * 1.3) * 0.3
            let wave3 = sin(f.2 * phase + po * 0.7) * 0.2
            let deformation = CGFloat(wave1 + wave2 + wave3)
            let r = baseRadius + amplitude * deformation

            let angle = angleStep * Double(i) - Double.pi / 2
            points.append(CGPoint(
                x: center.x + r * CGFloat(cos(angle)),
                y: center.y + r * CGFloat(sin(angle))
            ))
        }

        return catmullRomPath(points: points)
    }

    private func catmullRomPath(points: [CGPoint]) -> Path {
        let n = points.count
        guard n >= 3 else { return Path() }

        var path = Path()
        path.move(to: points[0])

        let tension: CGFloat = 0.3
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) * tension,
                y: p1.y + (p2.y - p0.y) * tension
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) * tension,
                y: p2.y - (p3.y - p1.y) * tension
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Liquid Orb View

/// Multi-layer organic liquid orb with visible blob morphing, glows, and specular highlight.
struct LiquidOrbView: View {
    let color: Color
    let driftOffset: CGFloat

    @State private var startDate = Date.now

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSince(startDate)
            let breathe = abs(driftOffset) < 5 ? 1.0 + 0.04 * sin(t * 0.6) : 1.0

            ZStack {
                // Layer 1: Outer glow halo — large, soft, slow
                LiquidBlob(phase: t * 0.3, intensity: 0.7)
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.35), color.opacity(0.0)],
                            center: .center,
                            startRadius: 8,
                            endRadius: 40
                        )
                    )
                    .frame(width: 72, height: 72)
                    .blur(radius: 10)

                // Layer 2: Inner glow — medium, richer color
                LiquidBlob(phase: t * 0.5, intensity: 0.9)
                    .fill(
                        RadialGradient(
                            colors: [color.opacity(0.6), color.opacity(0.15)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 20
                        )
                    )
                    .frame(width: 44, height: 44)
                    .blur(radius: 4)

                // Layer 3: Core blob — crisp, visible organic shape
                LiquidBlob(phase: t * 0.8, intensity: 1.0)
                    .fill(
                        RadialGradient(
                            colors: [color, color.opacity(0.7)],
                            center: UnitPoint(x: 0.35, y: 0.3),
                            startRadius: 0,
                            endRadius: 16
                        )
                    )
                    .frame(width: 28, height: 28)

                // Layer 4: Glass refraction edge — lighter rim on the blob
                LiquidBlob(phase: t * 0.8, intensity: 1.0)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.5), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 28, height: 28)

                // Layer 5: Specular highlight — bright dot with slight offset
                let specX = min(max(driftOffset * 0.03, -3), 3)
                LiquidBlob(phase: t * 1.2, intensity: 0.5)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 6, height: 6)
                    .offset(x: specX - 3, y: -4)
                    .blur(radius: 0.5)
            }
            .scaleEffect(breathe)
        }
    }
}

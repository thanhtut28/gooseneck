import SwiftUI

/// Ultra Minimalist Premium Alignment Orb — 2D gyroscope visualization
struct PostureFigure: View {
    let pitchDrift: Double      // X axis: device tilt (forward/backward lean)
    let lidAngleDrift: Double   // Y axis: lid angle change (opening/closing)
    let isDrifting: Bool
    @Environment(\.colorScheme) private var scheme

    private var driftMagnitude: Double {
        abs(pitchDrift) + abs(lidAngleDrift)
    }

    private var driftOffset: CGSize {
        let clampedX = max(min(pitchDrift, 25), -25)
        let clampedY = max(min(lidAngleDrift, 25), -25)

        let scale: CGFloat = 1.8
        var dx = CGFloat(clampedX) * scale
        var dy = CGFloat(-clampedY) * scale  // Negate: positive lid drift = upward on screen

        // Clamp to circular boundary (lens radius 65 minus orb margin)
        let maxRadius: CGFloat = 52
        let dist = sqrt(dx * dx + dy * dy)
        if dist > maxRadius {
            let ratio = maxRadius / dist
            dx *= ratio
            dy *= ratio
        }

        return CGSize(width: dx, height: dy)
    }

    private var themeColor: Color {
        if isDrifting { return DS.Colors.accentWarn }
        if driftMagnitude > 3 { return DS.Colors.accentInfo.opacity(0.8) }
        return DS.Colors.accentGood
    }

    private var tetherOpacity: Double {
        let dx = driftOffset.width
        let dy = driftOffset.height
        let dist = sqrt(dx * dx + dy * dy)
        if dist < 4 { return 0 }
        return min((dist - 4) / 10, 1.0) * 0.5
    }

    var body: some View {
        ZStack {
            // Soft Glass Lens
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 130, height: 130)
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(scheme == .dark ? 0.15 : 0.06), radius: scheme == .dark ? 20 : 12, x: 0, y: scheme == .dark ? 10 : 4)

            // Center Pinpoint
            Circle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 3, height: 3)

            // Tether + Orb — single animation scope for perfect sync
            ZStack {
                // Tether line from center to orb
                TetherShape(offsetX: driftOffset.width, offsetY: driftOffset.height)
                    .stroke(themeColor.opacity(tetherOpacity), lineWidth: 1)
                    .frame(width: 180, height: 180)

                // Alignment Orb
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [themeColor.opacity(0.4), themeColor.opacity(0.0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 32
                            )
                        )
                        .frame(width: 64, height: 64)

                    // Inner glow ring
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [themeColor.opacity(0.3), Color.clear],
                                center: .center,
                                startRadius: 2,
                                endRadius: 16
                            )
                        )
                        .frame(width: 32, height: 32)

                    // Crisp core
                    Circle()
                        .fill(themeColor)
                        .frame(width: 16, height: 16)
                        .shadow(color: themeColor.opacity(0.5), radius: 4, x: 0, y: 0)

                    // Specular highlight
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.white.opacity(0.95), Color.white.opacity(0.0)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 3
                            )
                        )
                        .frame(width: 6, height: 6)
                        .offset(x: -2, y: -2)
                }
                .offset(driftOffset)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: driftOffset.width)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: driftOffset.height)
        }
        .frame(width: 180, height: 180)
    }
}

// MARK: - Tether Shape

/// Animatable line from center to 2D offset position. Uses AnimatablePair
/// so both axes interpolate in sync with the orb's spring animation.
private struct TetherShape: Shape {
    var offsetX: CGFloat
    var offsetY: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(offsetX, offsetY) }
        set {
            offsetX = newValue.first
            offsetY = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let dist = sqrt(offsetX * offsetX + offsetY * offsetY)

        guard dist > 4 else { return Path() }

        // Normalized direction vector
        let nx = offsetX / dist
        let ny = offsetY / dist

        let start = CGPoint(x: center.x + nx * 2, y: center.y + ny * 2)
        let end = CGPoint(x: center.x + offsetX - nx * 9, y: center.y + offsetY - ny * 9)

        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}

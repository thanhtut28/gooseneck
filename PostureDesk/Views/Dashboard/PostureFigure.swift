import SwiftUI

/// Premium abstract Alignment Orb that replaces the original human coach mark.
struct PostureFigure: View {
    let drift: Double
    let isDrifting: Bool
    
    // Smoothly animated properties
    private var driftOffset: CGFloat {
        // Map drift (-25 to +25) to a physical offset within the lens (-40 to +40 points)
        let clamped = max(min(drift, 25), -25)
        return CGFloat(clamped) * 1.8
    }

    private var figureColor: Color {
        if isDrifting { return DS.Colors.accentWarn }
        if abs(drift) > 3 { return DS.Colors.accentInfo.opacity(0.8) } // slightly off-center
        return DS.Colors.accentGood
    }

    var body: some View {
        ZStack {
            // Glass bezel / lens
            Circle()
                .fill(.thinMaterial)
                .frame(width: 130, height: 130)
                .shadow(color: Color.black.opacity(0.2), radius: 15, x: 0, y: 8)
            
            // Bezel rim (liquid glass stroke)
            Circle()
                .stroke(LinearGradient(colors: [Color.white.opacity(0.25), Color.white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                .frame(width: 130, height: 130)

            // Etched Crosshairs
            Crosshairs()
                .stroke(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .frame(width: 110, height: 110)

            // Inner Orb (The active indicator)
            ZStack {
                // Soft outer glow / diffusion
                Circle()
                    .fill(figureColor.opacity(0.25))
                    .frame(width: 48, height: 48)
                    .blur(radius: 8)
                
                // Neon core
                Circle()
                    .fill(figureColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: figureColor.opacity(0.8), radius: 8, x: 0, y: 0)
                
                // Glass highlight on the orb core
                Circle()
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
                    .frame(width: 14, height: 14)
            }
            .offset(x: driftOffset, y: 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: driftOffset)

            // Correction arrow badge (sleek floating pill)
            if isDrifting {
                correctionBadge
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.8, anchor: .center).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isDrifting)
        .frame(width: 180, height: 180)
    }

    private var correctionBadge: some View {
        let arrowIcon = drift > 0 ? "arrow.left" : "arrow.right"
        // Place the badge dynamically pushing inward based on the drift
        let xOffset: CGFloat = drift > 0 ? -65 : 65

        return HStack(spacing: 4) {
             Image(systemName: arrowIcon)
                 .font(.system(size: 11, weight: .bold))
             Text("Align")
                 .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(.white)
        .background(
            Capsule()
                .fill(DS.Colors.accentWarn.opacity(0.85))
                .shadow(color: DS.Colors.accentWarn.opacity(0.5), radius: 8, x: 0, y: 4)
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
        )
        .offset(x: xOffset, y: -45)
    }
}

private struct Crosshairs: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Horizontal line
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        // Vertical line
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

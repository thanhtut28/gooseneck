import SwiftUI

/// Minimal side-view sitting figure that tilts based on posture drift.
/// Shows a clean silhouette with an arrow hint when drifting.
struct PostureFigure: View {
    let drift: Double      // degrees from baseline
    let isDrifting: Bool

    private var tiltAngle: Double {
        // Signed tilt: positive = forward lean, negative = backward lean, clamped ±25°
        let clamped = max(min(drift * 1.5, 25), -25)
        return clamped
    }

    private var figureColor: Color {
        if isDrifting { return DS.Colors.accentWarn }
        if abs(drift) > 3 { return DS.Colors.textSecondary }
        return DS.Colors.accentGood
    }

    var body: some View {
        ZStack {
            // Seated figure
            seatedFigure
                .rotationEffect(.degrees(tiltAngle), anchor: .bottom)
                .animation(.easeInOut(duration: 0.8), value: tiltAngle)

            // Correction arrow (only when drifting)
            if isDrifting {
                correctionArrow
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.5), value: isDrifting)
    }

    private var seatedFigure: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            // Head
            let headCenter = CGPoint(x: w * 0.5, y: h * 0.18)
            let headRadius = w * 0.09
            context.fill(
                Path(ellipseIn: CGRect(
                    x: headCenter.x - headRadius,
                    y: headCenter.y - headRadius,
                    width: headRadius * 2,
                    height: headRadius * 2
                )),
                with: .color(figureColor)
            )

            // Spine (neck to lower back)
            var spine = Path()
            spine.move(to: CGPoint(x: w * 0.5, y: h * 0.27))
            spine.addQuadCurve(
                to: CGPoint(x: w * 0.48, y: h * 0.58),
                control: CGPoint(x: w * 0.5, y: h * 0.42)
            )
            context.stroke(
                spine,
                with: .color(figureColor),
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )

            // Shoulders
            var shoulders = Path()
            shoulders.move(to: CGPoint(x: w * 0.32, y: h * 0.32))
            shoulders.addLine(to: CGPoint(x: w * 0.68, y: h * 0.32))
            context.stroke(
                shoulders,
                with: .color(figureColor),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )

            // Arms (resting on desk)
            var leftArm = Path()
            leftArm.move(to: CGPoint(x: w * 0.32, y: h * 0.32))
            leftArm.addQuadCurve(
                to: CGPoint(x: w * 0.25, y: h * 0.52),
                control: CGPoint(x: w * 0.28, y: h * 0.42)
            )
            context.stroke(leftArm, with: .color(figureColor),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

            var rightArm = Path()
            rightArm.move(to: CGPoint(x: w * 0.68, y: h * 0.32))
            rightArm.addQuadCurve(
                to: CGPoint(x: w * 0.75, y: h * 0.52),
                control: CGPoint(x: w * 0.72, y: h * 0.42)
            )
            context.stroke(rightArm, with: .color(figureColor),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Upper legs (seated)
            var legs = Path()
            legs.move(to: CGPoint(x: w * 0.48, y: h * 0.58))
            legs.addLine(to: CGPoint(x: w * 0.7, y: h * 0.62))
            context.stroke(legs, with: .color(figureColor),
                           style: StrokeStyle(lineWidth: 2.5, lineCap: .round))

            // Lower leg
            var lowerLeg = Path()
            lowerLeg.move(to: CGPoint(x: w * 0.7, y: h * 0.62))
            lowerLeg.addLine(to: CGPoint(x: w * 0.68, y: h * 0.82))
            context.stroke(lowerLeg, with: .color(figureColor),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

            // Chair hint (subtle)
            var chair = Path()
            chair.move(to: CGPoint(x: w * 0.35, y: h * 0.58))
            chair.addLine(to: CGPoint(x: w * 0.35, y: h * 0.85))
            context.stroke(chair, with: .color(DS.Colors.textMuted),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: 100, height: 140)
    }

    private var correctionArrow: some View {
        let arrowIcon = drift > 0 ? "arrow.left" : "arrow.right"
        let xOffset: CGFloat = drift > 0 ? -50 : 50

        return VStack(spacing: 2) {
            Image(systemName: arrowIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.Colors.accentWarn.opacity(0.7))

            Text("readjust")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.accentWarn.opacity(0.5))
        }
        .offset(x: xOffset, y: -10)
    }
}

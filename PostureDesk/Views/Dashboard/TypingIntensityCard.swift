import SwiftUI

struct TypingIntensityCard: View {
    @Environment(PostureViewModel.self) private var viewModel

    private var intensity: Double { viewModel.fatigueMonitor.currentIntensityPercent }
    private var hasBaseline: Bool { viewModel.fatigueMonitor.baselineRMS > 0 }
    private var isFatigued: Bool { viewModel.fatigueMonitor.isFatigued }
    private var history: [Double] { viewModel.fatigueMonitor.intensityHistory }

    private var accentColor: Color {
        if isFatigued { return DS.Colors.accentDanger }
        if intensity > 20 { return DS.Colors.accentWarn }
        return DS.Colors.accentGood
    }

    var body: some View {
        HStack(spacing: 24) {
            // Left: metrics
            VStack(alignment: .leading, spacing: 12) {
                Text("typing")
                    .font(DS.Font.label())
                    .foregroundStyle(DS.Colors.textMuted)
                    .textCase(.uppercase)
                    .tracking(1.5)

                if hasBaseline && intensity > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("+")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Colors.textMuted)
                        Text(String(format: "%.0f", intensity))
                            .font(DS.Font.metric(36))
                            .foregroundStyle(accentColor)
                            .contentTransition(.numericText())
                        Text("%")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Colors.textMuted)
                    }
                } else {
                    Text(hasBaseline ? "normal" : "calibrating")
                        .font(DS.Font.metric(24))
                        .foregroundStyle(hasBaseline ? DS.Colors.accentGood : DS.Colors.textMuted)
                }

                // Level bars
                HStack(spacing: 3) {
                    ForEach(0..<10, id: \.self) { i in
                        let threshold = Double(i) * 10
                        RoundedRectangle(cornerRadius: 1)
                            .fill(intensity > threshold ? barColor(threshold) : DS.Colors.bg)
                            .frame(width: 16, height: 3)
                            .animation(.easeInOut(duration: 0.3).delay(Double(i) * 0.02), value: intensity)
                    }
                }

                Text("vs session baseline")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textMuted)
            }

            Spacer()

            // Right: sparkline when data available, keyboard coach mark otherwise
            if history.count >= 10 {
                intensitySparkline
            } else {
                keyboardCoachMark
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard()
    }

    // MARK: - Sparkline

    private var intensitySparkline: some View {
        // Downsample history to ~60 points for smooth rendering
        let sampled = downsample(history, to: 60)
        let maxVal = max(sampled.max() ?? 1, 10) // At least 10% scale

        return VStack(alignment: .trailing, spacing: 4) {
            Canvas { context, size in
                let w = size.width
                let h = size.height
                guard sampled.count >= 2 else { return }

                let stepX = w / CGFloat(sampled.count - 1)

                // Build path
                var line = Path()
                for (i, val) in sampled.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = h - (CGFloat(val / maxVal) * h * 0.85) - h * 0.05
                    if i == 0 {
                        line.move(to: CGPoint(x: x, y: y))
                    } else {
                        line.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                // Gradient fill under the line
                var fill = line
                fill.addLine(to: CGPoint(x: w, y: h))
                fill.addLine(to: CGPoint(x: 0, y: h))
                fill.closeSubpath()

                let gradient = Gradient(colors: [
                    accentColor.opacity(0.15),
                    accentColor.opacity(0.02),
                ])
                context.fill(fill, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

                // Stroke the line
                context.stroke(line, with: .color(accentColor.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 160, height: 70)

            Text("last 5 min")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Colors.textMuted)
        }
    }

    private func downsample(_ data: [Double], to count: Int) -> [Double] {
        guard data.count > count else { return data }
        let step = Double(data.count) / Double(count)
        return (0..<count).map { i in
            let idx = Int(Double(i) * step)
            return data[min(idx, data.count - 1)]
        }
    }

    // MARK: - Keyboard Coach Mark

    private var keyboardCoachMark: some View {
        let opacity = isFatigued ? 0.25 : 0.08

        return Canvas { context, size in
            let w = size.width
            let h = size.height
            let color = isFatigued ? DS.Colors.accentWarn : DS.Colors.textMuted

            // Hands silhouette (two arcs)
            var leftHand = Path()
            leftHand.move(to: CGPoint(x: w * 0.15, y: h * 0.25))
            leftHand.addQuadCurve(
                to: CGPoint(x: w * 0.45, y: h * 0.35),
                control: CGPoint(x: w * 0.3, y: h * 0.15)
            )
            leftHand.addLine(to: CGPoint(x: w * 0.45, y: h * 0.45))
            leftHand.addQuadCurve(
                to: CGPoint(x: w * 0.15, y: h * 0.35),
                control: CGPoint(x: w * 0.3, y: h * 0.3)
            )
            leftHand.closeSubpath()
            context.fill(leftHand, with: .color(color.opacity(opacity)))

            var rightHand = Path()
            rightHand.move(to: CGPoint(x: w * 0.55, y: h * 0.35))
            rightHand.addQuadCurve(
                to: CGPoint(x: w * 0.85, y: h * 0.25),
                control: CGPoint(x: w * 0.7, y: h * 0.15)
            )
            rightHand.addLine(to: CGPoint(x: w * 0.85, y: h * 0.35))
            rightHand.addQuadCurve(
                to: CGPoint(x: w * 0.55, y: h * 0.45),
                control: CGPoint(x: w * 0.7, y: h * 0.3)
            )
            rightHand.closeSubpath()
            context.fill(rightHand, with: .color(color.opacity(opacity)))

            // Keyboard rows (3 rows of keys)
            let keyH: CGFloat = 6
            let gap: CGFloat = 3
            let rows = [
                (y: h * 0.55, keys: 10, offset: w * 0.1),
                (y: h * 0.55 + keyH + gap, keys: 9, offset: w * 0.14),
                (y: h * 0.55 + 2 * (keyH + gap), keys: 7, offset: w * 0.2),
            ]
            let keyW = (w * 0.8 - CGFloat(10 - 1) * gap) / 10

            for row in rows {
                for k in 0..<row.keys {
                    let rect = CGRect(
                        x: row.offset + CGFloat(k) * (keyW + gap),
                        y: row.y,
                        width: keyW,
                        height: keyH
                    )
                    let path = Path(roundedRect: rect, cornerRadius: 1.5)
                    context.fill(path, with: .color(color.opacity(opacity * 1.5)))
                }
            }
        }
        .frame(width: 160, height: 100)
    }

    private func barColor(_ threshold: Double) -> Color {
        if threshold >= 70 { return DS.Colors.accentDanger }
        if threshold >= 40 { return DS.Colors.accentWarn }
        return DS.Colors.accentGood
    }
}

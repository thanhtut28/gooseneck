import SwiftUI

// MARK: - MacBook Front View (Accelerometer)

/// A SwiftUI Path-drawn MacBook viewed from the front, highlighting the accelerometer sensor.
struct MacBookFrontView: View {
    let isDetected: Bool
    var liveValue: Double? = nil

    @State private var glowPhase: CGFloat = 0

    private var highlightColor: Color {
        isDetected ? DS.Colors.accentGood : DS.Colors.accentInfo
    }

    var body: some View {
        ZStack {
            // Sensor glow (behind the device)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [highlightColor.opacity(0.5), highlightColor.opacity(0)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 50
                    )
                )
                .frame(width: 100, height: 100)
                .offset(y: 38)
                .scaleEffect(isDetected ? 1.0 : 0.8 + 0.4 * glowPhase)
                .opacity(isDetected ? 0.6 : 0.4 + 0.4 * glowPhase)

            // Device drawing
            Canvas { context, size in
                drawMacBookFront(context: context, size: size)
            }

            // Sensor dot
            Circle()
                .fill(highlightColor)
                .frame(width: 8, height: 8)
                .shadow(color: highlightColor.opacity(0.8), radius: 6)
                .offset(y: 38)

            // Live value badge
            if let value = liveValue {
                Text(String(format: "%.1f°", value))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(highlightColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.Colors.cardBg.opacity(0.9), in: Capsule())
                    .overlay(Capsule().stroke(highlightColor.opacity(0.3), lineWidth: 1))
                    .offset(y: 58)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 200, height: 160)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPhase = 1
            }
        }
    }

    private func drawMacBookFront(context: GraphicsContext, size: CGSize) {
        let w = size.width
        let h = size.height
        let strokeColor = DS.Colors.textMuted.opacity(0.25)
        let fillColor = DS.Colors.cardBg.opacity(0.3)

        // Screen bezel
        let screenRect = CGRect(
            x: w * 0.15, y: h * 0.05,
            width: w * 0.70, height: h * 0.55
        )
        let screenPath = Path(roundedRect: screenRect, cornerRadius: 8)
        context.fill(screenPath, with: .color(fillColor))
        context.stroke(screenPath, with: .color(strokeColor), lineWidth: 1.5)

        // Screen inner (display)
        let displayRect = screenRect.insetBy(dx: 6, dy: 6)
        let displayPath = Path(roundedRect: displayRect, cornerRadius: 4)
        context.fill(displayPath, with: .color(DS.Colors.bg.opacity(0.2)))
        context.stroke(displayPath, with: .color(strokeColor.opacity(0.5)), lineWidth: 0.5)

        // Notch
        let notchW: CGFloat = 24
        let notchH: CGFloat = 6
        let notchRect = CGRect(
            x: w * 0.5 - notchW / 2, y: screenRect.minY + 6,
            width: notchW, height: notchH
        )
        let notchPath = Path(roundedRect: notchRect, cornerRadius: 3)
        context.fill(notchPath, with: .color(strokeColor.opacity(0.6)))

        // Base — tapered trapezoid
        let baseTop = screenRect.maxY + 2
        let baseBottom = h * 0.88
        var basePath = Path()
        basePath.move(to: CGPoint(x: w * 0.13, y: baseTop))
        basePath.addLine(to: CGPoint(x: w * 0.87, y: baseTop))
        basePath.addLine(to: CGPoint(x: w * 0.90, y: baseBottom))
        basePath.addLine(to: CGPoint(x: w * 0.10, y: baseBottom))
        basePath.closeSubpath()
        context.fill(basePath, with: .color(fillColor))
        context.stroke(basePath, with: .color(strokeColor), lineWidth: 1.5)

        // Keyboard rows
        let kbTop = baseTop + 6
        let kbLeft = w * 0.18
        let kbRight = w * 0.82
        let keyH: CGFloat = 4
        let keyGap: CGFloat = 3
        let keyCounts = [11, 10, 9]

        for (row, count) in keyCounts.enumerated() {
            let rowY = kbTop + CGFloat(row) * (keyH + keyGap)
            let rowInset = CGFloat(row) * 3
            let rowLeft = kbLeft + rowInset
            let rowRight = kbRight - rowInset
            let totalW = rowRight - rowLeft
            let keyW = (totalW - CGFloat(count - 1) * 2) / CGFloat(count)

            for k in 0..<count {
                let x = rowLeft + CGFloat(k) * (keyW + 2)
                let rect = CGRect(x: x, y: rowY, width: keyW, height: keyH)
                let keyPath = Path(roundedRect: rect, cornerRadius: 1)
                context.fill(keyPath, with: .color(strokeColor.opacity(0.4)))
            }
        }

        // Trackpad
        let tpW: CGFloat = w * 0.28
        let tpH: CGFloat = 12
        let tpRect = CGRect(
            x: w * 0.5 - tpW / 2,
            y: kbTop + 3 * (keyH + keyGap) + 4,
            width: tpW, height: tpH
        )
        let tpPath = Path(roundedRect: tpRect, cornerRadius: 3)
        context.fill(tpPath, with: .color(strokeColor.opacity(0.15)))
        context.stroke(tpPath, with: .color(strokeColor.opacity(0.4)), lineWidth: 0.5)

        // Front lip
        var lipPath = Path()
        let lipY = baseBottom
        lipPath.move(to: CGPoint(x: w * 0.10, y: lipY))
        lipPath.addQuadCurve(
            to: CGPoint(x: w * 0.90, y: lipY),
            control: CGPoint(x: w * 0.5, y: lipY + 6)
        )
        context.stroke(lipPath, with: .color(strokeColor), lineWidth: 1)
    }
}

// MARK: - MacBook Side View (Lid Angle)

/// A SwiftUI Path-drawn MacBook viewed from the side, highlighting the lid angle hinge sensor.
struct MacBookSideView: View {
    let isDetected: Bool
    var angle: Double = 110 // lid angle in degrees
    var liveValue: Double? = nil

    @State private var glowPhase: CGFloat = 0

    private var highlightColor: Color {
        isDetected ? DS.Colors.accentGood : DS.Colors.accentInfo
    }

    var body: some View {
        ZStack {
            // Hinge glow (behind device)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [highlightColor.opacity(0.5), highlightColor.opacity(0)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 45
                    )
                )
                .frame(width: 90, height: 90)
                .offset(x: -24, y: 16)
                .scaleEffect(isDetected ? 1.0 : 0.8 + 0.4 * glowPhase)
                .opacity(isDetected ? 0.6 : 0.4 + 0.4 * glowPhase)

            // Device drawing
            Canvas { context, size in
                drawMacBookSide(context: context, size: size, lidAngle: angle)
            }

            // Hinge dot
            Circle()
                .fill(highlightColor)
                .frame(width: 8, height: 8)
                .shadow(color: highlightColor.opacity(0.8), radius: 6)
                .offset(x: -24, y: 16)

            // Live angle badge
            if let value = liveValue {
                Text(String(format: "%.0f°", value))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(highlightColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DS.Colors.cardBg.opacity(0.9), in: Capsule())
                    .overlay(Capsule().stroke(highlightColor.opacity(0.3), lineWidth: 1))
                    .offset(x: -54, y: -12)
                    .contentTransition(.numericText())
            }
        }
        .frame(width: 200, height: 160)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowPhase = 1
            }
        }
    }

    private func drawMacBookSide(context: GraphicsContext, size: CGSize, lidAngle: Double) {
        let w = size.width
        let h = size.height
        let strokeColor = DS.Colors.textMuted.opacity(0.25)
        let fillColor = DS.Colors.cardBg.opacity(0.3)

        // Hinge point
        let hinge = CGPoint(x: w * 0.38, y: h * 0.60)

        // Base — horizontal panel extending right from hinge
        let baseLength = w * 0.52
        let baseThickness: CGFloat = 5
        let baseEnd = CGPoint(x: hinge.x + baseLength, y: hinge.y)

        var basePath = Path()
        basePath.move(to: CGPoint(x: hinge.x - 4, y: hinge.y - baseThickness / 2))
        basePath.addLine(to: CGPoint(x: baseEnd.x, y: baseEnd.y - baseThickness / 2))
        basePath.addQuadCurve(
            to: CGPoint(x: baseEnd.x, y: baseEnd.y + baseThickness / 2),
            control: CGPoint(x: baseEnd.x + 3, y: baseEnd.y)
        )
        basePath.addLine(to: CGPoint(x: hinge.x - 4, y: hinge.y + baseThickness / 2))
        basePath.closeSubpath()
        context.fill(basePath, with: .color(fillColor))
        context.stroke(basePath, with: .color(strokeColor), lineWidth: 1.5)

        // Screen — angled panel extending up-left from hinge
        let screenLength = w * 0.48
        let screenThickness: CGFloat = 3.5
        let clampedAngle = max(min(lidAngle, 150), 60)
        let angleRad = clampedAngle * .pi / 180

        // Screen extends at the lid angle from horizontal
        let screenDx = -screenLength * CGFloat(cos(angleRad))
        let screenDy = -screenLength * CGFloat(sin(angleRad))
        let screenEnd = CGPoint(x: hinge.x + screenDx, y: hinge.y + screenDy)

        // Perpendicular direction for thickness
        let perpX = CGFloat(sin(angleRad)) * screenThickness / 2
        let perpY = CGFloat(-cos(angleRad)) * screenThickness / 2

        // Offset the screen slightly from hinge for visual gap
        let screenStart = CGPoint(x: hinge.x + screenDx * 0.02, y: hinge.y + screenDy * 0.02)

        var screenPath = Path()
        screenPath.move(to: CGPoint(x: screenStart.x - perpX, y: screenStart.y - perpY))
        screenPath.addLine(to: CGPoint(x: screenEnd.x - perpX, y: screenEnd.y - perpY))
        // Rounded top
        screenPath.addQuadCurve(
            to: CGPoint(x: screenEnd.x + perpX, y: screenEnd.y + perpY),
            control: CGPoint(x: screenEnd.x, y: screenEnd.y - 2)
        )
        screenPath.addLine(to: CGPoint(x: screenStart.x + perpX, y: screenStart.y + perpY))
        screenPath.closeSubpath()
        context.fill(screenPath, with: .color(fillColor))
        context.stroke(screenPath, with: .color(strokeColor), lineWidth: 1.5)

        // Angle arc from base direction to screen direction
        let arcRadius: CGFloat = 32
        let startAngle = Angle(degrees: 0)    // horizontal (base direction to the right)
        let endAngle = Angle(degrees: -clampedAngle)  // screen angle (up from horizontal)

        var arcPath = Path()
        arcPath.addArc(
            center: hinge,
            radius: arcRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true
        )
        let arcStyle = StrokeStyle(
            lineWidth: 1.5,
            lineCap: .round,
            dash: isDetected ? [] : [4, 4]
        )
        context.stroke(arcPath, with: .color(highlightColor.opacity(0.6)), style: arcStyle)

        // Small tick marks at arc ends
        let tickLen: CGFloat = 4
        // Start tick (horizontal)
        var startTick = Path()
        startTick.move(to: CGPoint(x: hinge.x + arcRadius - tickLen, y: hinge.y))
        startTick.addLine(to: CGPoint(x: hinge.x + arcRadius + tickLen, y: hinge.y))
        context.stroke(startTick, with: .color(highlightColor.opacity(0.4)), lineWidth: 1)

        // End tick (along screen direction)
        let endTickX = hinge.x + (arcRadius) * CGFloat(cos(-angleRad))
        let endTickY = hinge.y + (arcRadius) * CGFloat(sin(-angleRad))
        let tickDirX = CGFloat(cos(-angleRad))
        let tickDirY = CGFloat(sin(-angleRad))
        var endTick = Path()
        endTick.move(to: CGPoint(x: endTickX - tickDirX * tickLen, y: endTickY - tickDirY * tickLen))
        endTick.addLine(to: CGPoint(x: endTickX + tickDirX * tickLen, y: endTickY + tickDirY * tickLen))
        context.stroke(endTick, with: .color(highlightColor.opacity(0.4)), lineWidth: 1)

        // Hinge circle
        let hingeCircle = Path(ellipseIn: CGRect(
            x: hinge.x - 4, y: hinge.y - 4, width: 8, height: 8
        ))
        context.fill(hingeCircle, with: .color(strokeColor.opacity(0.5)))
        context.stroke(hingeCircle, with: .color(strokeColor), lineWidth: 1)
    }
}

// MARK: - Island Preview Mockup

/// Static mockup of the Posture Island for the onboarding preview step.
struct IslandPreviewMockup: View {
    var body: some View {
        VStack(spacing: 0) {
            // Top bar indicators
            HStack(spacing: 0) {
                // Left: status dot
                HStack {
                    Spacer()
                    Circle()
                        .fill(DS.Colors.accentGood)
                        .frame(width: 10, height: 10)
                        .shadow(color: DS.Colors.accentGood.opacity(0.5), radius: 6)
                    Spacer()
                }
                .frame(width: 70, height: 36)

                // Notch spacer
                Color.clear.frame(width: 100, height: 36)

                // Right: drift value
                HStack {
                    Spacer()
                    Text("0.0°")
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(DS.Colors.accentGood)
                    Spacer()
                }
                .frame(width: 70, height: 36)
            }

            // Expanded body
            VStack(spacing: 8) {
                HStack {
                    Text("Good Posture")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 4)

                HStack(spacing: 8) {
                    mockWidgetCard("SESSION", value: "0m")
                    mockWidgetCard("BREAK", value: "in 45m")
                }

                Text("Recalibrate")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(width: 240)
        .background(Color.black)
        .clipShape(
            PostureIslandPillShape(
                topCornerRadius: 10,
                bottomCornerRadius: 22
            )
        )
        .shadow(
            color: Color.black.opacity(0.4),
            radius: 16, y: 8
        )
    }

    private func mockWidgetCard(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

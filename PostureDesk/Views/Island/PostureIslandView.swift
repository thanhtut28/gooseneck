import SwiftUI

struct PostureIslandView: View {
    @Environment(PostureViewModel.self) private var viewModel
    @Environment(\.colorScheme) private var colorScheme

    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool

    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var contentVisible = false
    @State private var hoverScale: CGFloat = 1.0
    @State private var surfaceBadgeScale: CGFloat = 1.0

    private let sideExtension: CGFloat = 80
    private let collapsedHeightPadding: CGFloat = 0

    private var barHeight: CGFloat { notchHeight + collapsedHeightPadding }
    private var totalWidth: CGFloat { notchWidth + sideExtension * 2 }

    // iOS Dynamic Island spring parameters
    private var expandSpring: Animation {
        .spring(response: 0.4, dampingFraction: 0.65, blendDuration: 0.02)
    }
    private var collapseSpring: Animation {
        .spring(response: 0.32, dampingFraction: 0.86)
    }

    /// Whether the island is revealed (not hidden by a space transition).
    private var isRevealed: Bool {
        viewModel.islandManager.isRevealed
    }

    var body: some View {
        Group {
            if hasNotch {
                notchLayout
            } else {
                floatingLayout
            }
        }
        .onHover { handleHover($0) }
        .onDisappear { hoverTask?.cancel() }
        .opacity(isRevealed ? 1 : 0)
        .scaleEffect(
            x: isRevealed ? 1.0 : 0.85,
            y: isRevealed ? 1.0 : 0.5,
            anchor: .top
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isRevealed)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Notch Layout

    private var notchLayout: some View {
        VStack(spacing: 0) {
            // Top bar: left indicator + notch spacer + right indicator
            HStack(spacing: 0) {
                leftIndicator
                    .frame(width: sideExtension, height: barHeight)

                Color.clear
                    .frame(width: notchWidth, height: barHeight)

                rightIndicator
                    .frame(width: sideExtension, height: barHeight)
            }

            // Expanded body — morphs out from the pill
            if isExpanded {
                expandedBody
                    .opacity(contentVisible ? 1 : 0)
                    .scaleEffect(contentVisible ? 1 : 0.92, anchor: .top)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8).delay(0.06), value: contentVisible)
                    .transition(.opacity.animation(.easeOut(duration: 0.12)))
            }
        }
        .frame(width: totalWidth)
        .background(islandBackground)
        .clipShape(
            PostureIslandPillShape(
                topCornerRadius: isExpanded ? 12 : 6,
                bottomCornerRadius: isExpanded ? 24 : 14
            )
        )
        .contentShape(
            PostureIslandPillShape(
                topCornerRadius: isExpanded ? 12 : 6,
                bottomCornerRadius: isExpanded ? 24 : 14
            )
        )
        .animation(isExpanded ? expandSpring : collapseSpring, value: isExpanded)
        .scaleEffect(hoverScale, anchor: .top)
    }

    // MARK: - Left Indicator (status dot only)

    private var leftIndicator: some View {
        HStack {
            Spacer()
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.5), radius: 6)
            Spacer()
        }
    }

    // MARK: - Right Indicator (variant-driven)

    private var rightIndicator: some View {
        HStack {
            Spacer()
            Text(minimalRightValue)
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(statusColor)
                .contentTransition(.numericText(value: minimalRightNumeric))
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: minimalRightValue)
            Spacer()
        }
    }

    // MARK: - Expanded Body (widget cards)

    private var expandedBody: some View {
        VStack(spacing: 8) {
            // Status row
            HStack {
                Text(statusText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(islandPrimaryText)
                    .contentTransition(.interpolate)

                Spacer()

                surfaceBadge()
            }
            .padding(.horizontal, 4)

            // Lid-angle nudge
            if viewModel.showSurfaceNudge {
                surfaceNudgeBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Metric widget cards (variant-driven)
            HStack(spacing: 8) {
                widgetCard {
                    Text(expandedCard1Label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(islandSecondaryText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(expandedCard1Value)
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(islandPrimaryText)
                        .contentTransition(.numericText())
                }

                widgetCard {
                    Text(expandedCard2Label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(islandSecondaryText)
                        .textCase(.uppercase)
                        .tracking(0.5)
                    Text(expandedCard2Value)
                        .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(islandPrimaryText)
                        .contentTransition(.numericText())
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                if viewModel.breakTracker.isBreakOverdue {
                    Button {
                        viewModel.recordBreak()
                    } label: {
                        Text("Took a Break")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(islandSecondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(islandChrome)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Took a Break")
                } else {
                    Button {
                        if viewModel.sensorClient.connectionError == nil {
                            viewModel.calibrate()
                        } else {
                            viewModel.start()
                        }
                    } label: {
                        Text(sensorActionTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(islandSecondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(8)
                            .background(islandChrome)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sensorActionTitle)
                    .accessibilityHint(sensorActionHint)
                }

                Button {
                    if viewModel.isPaused {
                        viewModel.resumeMonitoring()
                    } else {
                        viewModel.pauseMonitoring()
                    }
                } label: {
                    Text(viewModel.isPaused ? "Resume" : "Pause")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(islandSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(islandChrome)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.isPaused ? "Resume monitoring" : "Pause monitoring")
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showSurfaceNudge)
    }

    // MARK: - Widget Card

    private func widgetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(islandChrome)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Surface Badge

    private func cycleSurface() {
        let surfaces: [Surface] = [.desk, .lap, .couch]
        let currentIndex = surfaces.firstIndex(of: viewModel.selectedSurface) ?? 0
        let nextSurface = surfaces[(currentIndex + 1) % surfaces.count]
        viewModel.changeSurface(to: nextSurface)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            surfaceBadgeScale = 1.15
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6).delay(0.12)) {
            surfaceBadgeScale = 1.0
        }
    }

    private func surfaceBadge(fontSize: CGFloat = 11, hPad: CGFloat = 8, vPad: CGFloat = 3) -> some View {
        Button {
            cycleSurface()
        } label: {
            Text(viewModel.selectedSurface.label.lowercased())
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(islandSecondaryText)
                .padding(.horizontal, hPad)
                .padding(.vertical, vPad)
                .background(islandChrome)
                .clipShape(Capsule())
                .contentTransition(.interpolate)
        }
        .buttonStyle(.plain)
        .scaleEffect(surfaceBadgeScale)
        .accessibilityLabel("Surface: \(viewModel.selectedSurface.label). Tap to switch.")
    }

    // MARK: - Surface Nudge Banner

    private var surfaceNudgeBanner: some View {
        VStack(spacing: 6) {
            Text("Moved to a different surface?")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(islandPrimaryText)

            HStack(spacing: 6) {
                ForEach([Surface.desk, .lap, .couch], id: \.rawValue) { surface in
                    Button {
                        viewModel.acceptSurfaceNudge(to: surface)
                    } label: {
                        Text(surface.label)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(
                                surface == viewModel.selectedSurface
                                    ? islandPrimaryText
                                    : islandSecondaryText
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                surface == viewModel.selectedSurface
                                    ? Color.white.opacity(0.15)
                                    : islandChrome
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Switch to \(surface.label)")
                }
            }

            Button {
                viewModel.dismissSurfaceNudge()
            } label: {
                Text("Dismiss")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(islandSecondaryText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss surface suggestion")
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Floating Layout (non-notch)

    private var floatingLayout: some View {
        let width: CGFloat = isExpanded ? 240 : 120
        let nudgeExtra: CGFloat = viewModel.showSurfaceNudge ? 100 : 0
        let height: CGFloat = isExpanded ? 180 + nudgeExtra : 32
        let radius: CGFloat = isExpanded ? 20 : height / 2

        return VStack(spacing: 0) {
            if isExpanded {
                VStack(spacing: 8) {
                    HStack {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(islandPrimaryText)
                        Spacer()
                        surfaceBadge(fontSize: 10, hPad: 6, vPad: 2)
                    }

                    if viewModel.showSurfaceNudge {
                        surfaceNudgeBanner
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    HStack(spacing: 8) {
                        widgetCard {
                            Text(expandedCard1Label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(islandSecondaryText)
                                .textCase(.uppercase)
                            Text(expandedCard1Value)
                                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(islandPrimaryText)
                        }
                        widgetCard {
                            Text(expandedCard2Label)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(islandSecondaryText)
                                .textCase(.uppercase)
                            Text(expandedCard2Value)
                                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(islandPrimaryText)
                        }
                    }

                    HStack(spacing: 8) {
                        if viewModel.breakTracker.isBreakOverdue {
                            Button {
                                viewModel.recordBreak()
                            } label: {
                                Text("Took a Break")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(islandSecondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(islandChrome)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Took a Break")
                        } else {
                            Button {
                                if viewModel.sensorClient.connectionError == nil {
                                    viewModel.calibrate()
                                } else {
                                    viewModel.start()
                                }
                            } label: {
                                Text(sensorActionTitle)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(islandSecondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(8)
                                    .background(islandChrome)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sensorActionTitle)
                            .accessibilityHint(sensorActionHint)
                        }

                        Button {
                            if viewModel.isPaused {
                                viewModel.resumeMonitoring()
                            } else {
                                viewModel.pauseMonitoring()
                            }
                        } label: {
                            Text(viewModel.isPaused ? "Resume" : "Pause")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(islandSecondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(8)
                                .background(islandChrome)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.isPaused ? "Resume monitoring" : "Pause monitoring")
                    }
                }
                .padding(14)
                .opacity(contentVisible ? 1 : 0)
                .scaleEffect(contentVisible ? 1 : 0.92, anchor: .top)
                .animation(.spring(response: 0.3, dampingFraction: 0.8).delay(0.06), value: contentVisible)
                .transition(.opacity.animation(.easeOut(duration: 0.12)))
            } else {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor.opacity(0.5), radius: 4)
                    Text(minimalRightValue)
                        .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 12)
                .transition(.opacity.animation(.easeOut(duration: 0.1)))
            }
        }
        .frame(width: width, height: height)
        .background(
            islandBackground.opacity(0.9)
                .background(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(isExpanded ? expandSpring : collapseSpring, value: isExpanded)
        .scaleEffect(hoverScale)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.showSurfaceNudge)
        .padding(.top, 6)
    }

    // MARK: - Hover

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering {
            isHovering = true
            // Phase 1: smooth pill breathe — tactile feedback
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                hoverScale = 1.04
            }
            viewModel.islandManager.updateShadow(radius: 20, opacity: 0.35, offsetY: 4)
            // Phase 2: delayed expand — scale grows further
            hoverTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                guard !Task.isCancelled, isHovering else { return }
                withAnimation(expandSpring) {
                    isExpanded = true
                    hoverScale = 1.06
                }
                viewModel.islandManager.updateShadow(radius: 25, opacity: 0.4, offsetY: 6)
                try? await Task.sleep(for: .milliseconds(80))
                guard !Task.isCancelled else { return }
                contentVisible = true
            }
        } else {
            isHovering = false
            hoverTask = Task { @MainActor in
                if contentVisible {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    contentVisible = false
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                }
                withAnimation(collapseSpring) {
                    contentVisible = false
                    isExpanded = false
                    hoverScale = 1.0
                }
                viewModel.islandManager.updateShadow(radius: 16, opacity: 0.3, offsetY: 3)
            }
        }
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if viewModel.sensorClient.connectionError != nil { return DS.Colors.accentDanger }
        switch viewModel.iconState {
        case .good: return DS.Colors.accentGood
        case .drifting: return DS.Colors.accentWarn
        case .breakNeeded: return DS.Colors.accentDanger
        case .unavailable: return DS.Colors.accentDanger
        case .away: return DS.Colors.textMuted
        }
    }

    private var statusText: String {
        if viewModel.sensorClient.connectionError != nil { return "Sensors Unavailable" }
        if viewModel.isPaused { return "Paused" }
        switch viewModel.iconState {
        case .good: return "Good Posture"
        case .drifting: return "Drifting"
        case .breakNeeded: return "Break Needed"
        case .unavailable: return "Sensors Unavailable"
        case .away: return "Away"
        }
    }

    // MARK: - Variant-Driven Content

    private var variant: IslandVariant { viewModel.islandVariant }

    private var minimalRightValue: String {
        guard viewModel.sensorClient.connectionError == nil else { return "—" }
        switch variant {
        case .lidAngle: return lidAngleLabel
        case .tiltAngle: return tiltAngleLabel
        case .sessionTime: return sessionDuration
        case .typingIntensity: return typingLabel
        }
    }

    private var minimalRightNumeric: Double {
        switch variant {
        case .lidAngle: return viewModel.postureAnalyzer.lidAngleDrift
        case .tiltAngle: return viewModel.postureAnalyzer.pitchDrift
        case .sessionTime: return Double(viewModel.breakTracker.totalActiveSeconds)
        case .typingIntensity: return viewModel.fatigueMonitor.currentIntensityPercent
        }
    }

    private var expandedCard1Label: String {
        switch variant {
        case .lidAngle, .tiltAngle, .typingIntensity: return "Session"
        case .sessionTime: return "Tilt"
        }
    }

    private var expandedCard1Value: String {
        switch variant {
        case .lidAngle, .tiltAngle, .typingIntensity: return sessionDuration
        case .sessionTime: return tiltAngleLabel
        }
    }

    private var expandedCard2Label: String {
        switch variant {
        case .lidAngle, .tiltAngle: return "Break"
        case .sessionTime: return "Screen"
        case .typingIntensity: return "Tilt"
        }
    }

    private var expandedCard2Value: String {
        switch variant {
        case .lidAngle, .tiltAngle: return breakCountdown
        case .sessionTime: return lidAngleLabel
        case .typingIntensity: return tiltAngleLabel
        }
    }

    // MARK: - Formatted Values

    private var lidAngleLabel: String {
        let drift = viewModel.postureAnalyzer.lidAngleDrift
        if abs(drift) < 0.05 { return "0.0\u{00B0}" }
        let sign = drift > 0 ? "+" : ""
        return String(format: "%@%.1f\u{00B0}", sign, drift)
    }

    private var tiltAngleLabel: String {
        let drift = viewModel.postureAnalyzer.pitchDrift
        if abs(drift) < 0.05 { return "0.0\u{00B0}" }
        let sign = drift > 0 ? "+" : ""
        return String(format: "%@%.1f\u{00B0}", sign, drift)
    }

    private var typingLabel: String {
        let intensity = viewModel.fatigueMonitor.currentIntensityPercent
        if intensity < 1 { return "—" }
        return String(format: "%.0f%%", intensity)
    }

    private var sessionDuration: String {
        DisplayFormatter.activeDuration(seconds: viewModel.breakTracker.totalActiveSeconds)
    }

    private var breakCountdown: String {
        DisplayFormatter.shortBreakCountdown(
            elapsedSeconds: viewModel.breakTracker.secondsSinceLastBreak,
            intervalMinutes: viewModel.breakTracker.breakIntervalMinutes
        )
    }

    private var sensorActionTitle: String {
        viewModel.sensorClient.connectionError == nil ? "Recalibrate" : "Retry Sensors"
    }

    private var sensorActionHint: String {
        viewModel.sensorClient.connectionError == nil
            ? "Sets the current posture as your new baseline."
            : "Attempts to reconnect the built-in sensors."
    }

    private var islandPrimaryText: Color {
        .white
    }

    private var islandSecondaryText: Color {
        Color.white.opacity(0.72)
    }

    private var islandChrome: Color {
        Color.white.opacity(0.08)
    }

    private var islandBackground: Color {
        .black
    }
}

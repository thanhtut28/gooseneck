import SwiftUI

struct MenuBarPopover: View {
    @Environment(PostureViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(LicenseManager.self) private var licenseManager

    var body: some View {
        if case .trialExpired = licenseManager.licenseState {
            trialExpiredLockCard
        } else {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Posture")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(statusColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Session")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(sessionDuration)
                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
            .padding(12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current posture")
            .accessibilityValue("\(statusText), session \(sessionDuration)")

            if case .trialActive(let until) = licenseManager.licenseState {
                trialBanner(until: until)
                Divider()
            }

            if let sensorError {
                Divider()

                Text(sensorError)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.accentDanger)
                    .padding(12)
            }

            Divider()

            // Metrics
            VStack(spacing: 8) {
                metricRow("Lid Angle Drift", value: driftValue(for: \.lidAngle), color: driftColor)
                metricRow("Device Tilt", value: tiltValue, color: driftColor)
                metricRow("Typing Intensity", value: typingValue, color: typingColor)
                surfacePicker
            }
            .padding(12)

            Divider()

            // Break timer
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Next Break")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(breakCountdown)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Button("Took a Break") {
                    viewModel.recordBreak()
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Took a break")
                .accessibilityHint("Marks the break as taken and resets the countdown.")
            }
            .padding(12)

            Divider()

            // Quick actions
            HStack(spacing: 8) {
                Button(sensorError == nil ? "Recalibrate" : "Retry Sensors") {
                    if sensorError == nil {
                        viewModel.calibrate()
                    } else {
                        viewModel.start()
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(sensorError == nil ? "Recalibrate posture" : "Retry sensor connection")

                Button(viewModel.isPaused ? "Resume" : "Pause") {
                    if viewModel.isPaused {
                        viewModel.resumeMonitoring()
                    } else {
                        viewModel.pauseMonitoring()
                    }
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(viewModel.isPaused ? "Resume monitoring" : "Pause monitoring")
                .accessibilityHint(viewModel.isPaused ? "Resumes posture monitoring." : "Pauses posture monitoring until you resume it.")

                Spacer()

                Button {
                    openWindow(id: "dashboard")
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "rectangle.3.group")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Dashboard")
                .accessibilityLabel("Open Dashboard")

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityHint("Closes GooseNeck.")
            }
            .padding(12)
        }
        .frame(width: 280)
        } // end else
    }

    // MARK: - Computed Properties

    private var statusText: String {
        if sensorError != nil { return "Unavailable" }
        switch viewModel.iconState {
        case .good: return "Good"
        case .drifting: return "Drifting"
        case .breakNeeded: return "Break Needed"
        case .unavailable: return "Unavailable"
        case .away: return "Away"
        }
    }

    private var statusColor: Color {
        if sensorError != nil { return DS.Colors.accentDanger }
        switch viewModel.iconState {
        case .good: return DS.Colors.accentGood
        case .drifting: return DS.Colors.accentWarn
        case .breakNeeded: return DS.Colors.accentDanger
        case .unavailable: return DS.Colors.accentDanger
        case .away: return DS.Colors.textSecondary
        }
    }

    private var sessionDuration: String {
        DisplayFormatter.activeDuration(seconds: viewModel.breakTracker.totalActiveSeconds)
    }

    private func driftValue(for keyPath: KeyPath<SensorSnapshot, Double>) -> String {
        guard let snapshot = viewModel.sensorClient.latestSnapshot else { return "—" }
        let value = snapshot[keyPath: keyPath]
        if value < 0 { return "N/A" }
        let delta = value - viewModel.postureAnalyzer.baselineLidAngle
        let sign = delta >= 0 ? "+" : ""
        return String(format: "%@%.1f°", sign, delta)
    }

    private var tiltValue: String {
        guard let snapshot = viewModel.sensorClient.latestSnapshot else { return "—" }
        let delta = snapshot.pitch - viewModel.postureAnalyzer.baselinePitch
        let sign = delta >= 0 ? "+" : ""
        return String(format: "%@%.1f°", sign, delta)
    }

    private var driftColor: Color {
        viewModel.postureAnalyzer.isDrifting ? DS.Colors.accentWarn : DS.Colors.accentGood
    }

    private var typingValue: String {
        guard viewModel.fatigueMonitor.calibrationState == .ready else {
            return "Calibrating"
        }
        guard viewModel.fatigueMonitor.isCurrentlyTyping else {
            return "Idle"
        }
        let pct = viewModel.fatigueMonitor.currentIntensityPercent
        if pct > 0 {
            return String(format: "↑ %.0f%% from baseline", pct)
        }
        return "Normal"
    }

    private var typingColor: Color {
        guard viewModel.fatigueMonitor.calibrationState == .ready else {
            return .secondary
        }
        guard viewModel.fatigueMonitor.isCurrentlyTyping else {
            return DS.Colors.textSecondary
        }
        return viewModel.fatigueMonitor.isFatigued ? DS.Colors.accentWarn : DS.Colors.accentGood
    }

    private var breakCountdown: String {
        DisplayFormatter.breakCountdown(
            elapsedSeconds: viewModel.breakTracker.secondsSinceLastBreak,
            intervalMinutes: viewModel.breakTracker.breakIntervalMinutes
        )
    }

    private var surfacePicker: some View {
        let surfaceBinding = Binding<Surface>(
            get: { viewModel.selectedSurface },
            set: { viewModel.changeSurface(to: $0) }
        )
        return HStack {
            Text("Surface")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Picker("", selection: surfaceBinding) {
                Text("Desk").tag(Surface.desk)
                Text("Lap").tag(Surface.lap)
                Text("Couch").tag(Surface.couch)
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel("Surface")
        }
    }

    // MARK: - Helpers

    private func metricRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var sensorError: String? {
        viewModel.sensorClient.connectionError
    }

    private func trialBanner(until: Date) -> some View {
        let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: until).day ?? 0)
        let urgent = daysLeft <= 1
        return HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(urgent ? DS.Colors.accentWarn : DS.Colors.accentInfo)
            Text(daysLeft <= 0 ? "Trial · last day" : "Trial · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
            Button("Subscribe") {
                licenseManager.openCheckout()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(DS.Colors.accentInfo)
            .accessibilityHint("Opens the GooseNeck purchase page in your browser.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((urgent ? DS.Colors.accentWarn : DS.Colors.accentInfo).opacity(0.08))
    }

    private var trialExpiredLockCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(DS.Colors.accentWarn)

            Text("Your free trial has ended")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)

            Text("Subscribe to keep monitoring your posture.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                licenseManager.openCheckout()
            } label: {
                Text("Subscribe — $14.99")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(DS.Colors.accentInfo, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the GooseNeck purchase page in your browser.")
        }
        .padding(16)
        .frame(width: 260)
    }
}

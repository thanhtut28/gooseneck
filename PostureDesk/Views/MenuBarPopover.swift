import SwiftUI

struct MenuBarPopover: View {
    @Environment(PostureViewModel.self) private var viewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Posture")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(statusText)
                        .font(.title3.bold())
                        .foregroundStyle(statusColor)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Session")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(sessionDuration)
                        .font(.body.monospacedDigit())
                }
            }
            .padding(12)

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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(breakCountdown)
                        .font(.body)
                }
                Spacer()
                Button("Skip") {
                    viewModel.breakTracker.recordBreak()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)

            Divider()

            // Quick actions
            HStack(spacing: 8) {
                Button("Recalibrate") {
                    viewModel.calibrate()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(viewModel.isPaused ? "Resume" : "Pause 1hr") {
                    viewModel.isPaused.toggle()
                    if viewModel.isPaused {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3600) {
                            viewModel.isPaused = false
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    openWindow(id: "dashboard")
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate()
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Dashboard")

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
        }
        .frame(width: 280)
        .onAppear {
            viewModel.start()
        }
    }

    // MARK: - Computed Properties

    private var statusText: String {
        switch viewModel.iconState {
        case .good: return "Good"
        case .drifting: return "Drifting"
        case .breakNeeded: return "Break Needed"
        case .away: return "Away"
        }
    }

    private var statusColor: Color {
        switch viewModel.iconState {
        case .good: return .green
        case .drifting: return .yellow
        case .breakNeeded: return .red
        case .away: return .secondary
        }
    }

    private var sessionDuration: String {
        let seconds = viewModel.breakTracker.totalActiveSeconds
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func driftValue(for keyPath: KeyPath<SensorSnapshot, Double>) -> String {
        guard let snapshot = viewModel.sensorClient.latestSnapshot else { return "—" }
        let value = snapshot[keyPath: keyPath]
        if value < 0 { return "N/A" }
        let delta = abs(value - viewModel.postureAnalyzer.baselineLidAngle)
        return String(format: "+%.1f°", delta)
    }

    private var tiltValue: String {
        guard let snapshot = viewModel.sensorClient.latestSnapshot else { return "—" }
        let delta = abs(snapshot.pitch - viewModel.postureAnalyzer.baselinePitch)
        return String(format: "+%.1f°", delta)
    }

    private var driftColor: Color {
        viewModel.postureAnalyzer.isDrifting ? .yellow : .green
    }

    private var typingValue: String {
        let pct = viewModel.fatigueMonitor.currentIntensityPercent
        if pct > 0 {
            return String(format: "↑ %.0f%% from baseline", pct)
        }
        return "Normal"
    }

    private var typingColor: Color {
        viewModel.fatigueMonitor.isFatigued ? .orange : .green
    }

    private var breakCountdown: String {
        let elapsed = viewModel.breakTracker.secondsSinceLastBreak
        let target = viewModel.breakTracker.breakIntervalMinutes * 60
        let remaining = max(0, target - elapsed)
        return "in \(remaining / 60) min"
    }

    private var surfacePicker: some View {
        @Bindable var vm = viewModel
        return HStack {
            Text("Surface")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: $vm.selectedSurface) {
                Text("Desk").tag(Surface.desk)
                Text("Lap").tag(Surface.lap)
                Text("Couch").tag(Surface.couch)
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    // MARK: - Helpers

    private func metricRow(_ label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
    }
}

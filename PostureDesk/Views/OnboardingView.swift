import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case sensorCheck
    case activate
    case calibrate
    case ready
}

struct OnboardingView: View {
    @Binding var isComplete: Bool
    var licenseManager: LicenseManager
    var initialStep: OnboardingStep = .welcome
    @State private var step: OnboardingStep = .welcome
    @State private var sensorClient = DirectSensorClient()
    @State private var calibrationDone = false
    @State private var licenseKey = ""

    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Circle()
                        .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)

            switch step {
            case .welcome:
                welcomeStep
            case .sensorCheck:
                sensorCheckStep
            case .activate:
                activateStep
            case .calibrate:
                calibrateStep
            case .ready:
                readyStep
            }
        }
        .padding(24)
        .frame(width: 420, height: 380)
        .onAppear { step = initialStep }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.stand")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to PostureDesk")
                .font(.title2.bold())
            Text("PostureDesk uses your MacBook's built-in sensors to monitor posture, track breaks, and detect typing fatigue — all without a camera.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Get Started") {
                sensorClient.connect()
                step = .sensorCheck
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var sensorCheckStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "sensor")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Sensor Check")
                .font(.title2.bold())

            if let avail = sensorClient.sensorAvailability {
                VStack(alignment: .leading, spacing: 8) {
                    sensorRow("Accelerometer", available: avail.hasAccelerometer)
                    sensorRow("Gyroscope", available: avail.hasGyroscope)
                    sensorRow("Lid Angle", available: avail.hasLidAngle)
                }
                .padding()
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if !avail.hasAccelerometer {
                    Text("Accelerometer is required. Make sure you're on an Apple Silicon Mac.")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Spacer()
                    Button("Next") {
                        step = .activate
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Detecting sensors...")
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            sensorClient.fetchSensorStatus()
                        }
                    }
            }
        }
    }

    private var activateStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Activate License")
                .font(.title2.bold())
            Text("PostureDesk requires a license key to use.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button {
                licenseManager.openCheckout()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cart")
                    Text("Buy a License")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack {
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1)
                Text("already have a key?")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .layoutPriority(1)
                Rectangle()
                    .fill(.separator)
                    .frame(height: 1)
            }

            HStack(spacing: 8) {
                TextField("Paste license key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)

                if licenseManager.isValidating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 70)
                } else {
                    Button("Activate") {
                        Task {
                            await licenseManager.activate(key: licenseKey)
                            if licenseManager.isLicensed {
                                step = .calibrate
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let error = licenseManager.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var calibrateStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.and.person.rectangle.portrait")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Calibrate Your Posture")
                .font(.title2.bold())
            Text("Sit in your ideal posture with your screen at a comfortable angle. When ready, press Calibrate to set your baseline.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            if calibrationDone {
                Label("Baseline recorded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button("Finish Setup") {
                    step = .ready
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Calibrate") {
                    sensorClient.calibrate { success in
                        calibrationDone = success
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("You're All Set!")
                .font(.title2.bold())
            Text("PostureDesk is now monitoring from your menu bar. You'll get gentle nudges when your posture drifts or it's time for a break.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Done") {
                isComplete = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func sensorRow(_ name: String, available: Bool) -> some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(available ? .green : .secondary)
            Text(name)
                .font(.body)
            Spacer()
            Text(available ? "Available" : "Not found")
                .font(.caption)
                .foregroundStyle(available ? .green : .secondary)
        }
    }
}

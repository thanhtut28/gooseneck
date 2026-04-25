import SwiftUI

enum OnboardingStep: Int, CaseIterable {
    case welcome
    case privacyTerms
    case accelerometer
    case lidAngle
    case typingIntensity
    case surface
    case calibrate
    case island
    case activate
    case complete
}

struct OnboardingView: View {
    @Environment(LicenseManager.self) private var licenseManager
    @Environment(PostureViewModel.self) private var viewModel

    @Binding var isComplete: Bool
    var initialStep: OnboardingStep = .welcome
    @State private var step: OnboardingStep = .welcome
    @State private var calibrationDone = false
    @State private var licenseKey = ""
    @State private var direction: Edge = .trailing
    @State private var lidDetectionReady = false
    @State private var typingDetected = false
    @State private var typingCheckReady = false
    @State private var consecutiveTypingSamples = 0
    @State private var showPrivacySheet = false
    @State private var showTermsSheet = false
    @State private var isActivating = false

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            ZStack {
                switch step {
                case .welcome:
                    welcomeStep
                        .transition(slideTransition)
                case .privacyTerms:
                    privacyTermsStep
                        .transition(slideTransition)
                case .accelerometer:
                    accelerometerStep
                        .transition(slideTransition)
                case .lidAngle:
                    lidAngleStep
                        .transition(slideTransition)
                case .typingIntensity:
                    typingIntensityStep
                        .transition(slideTransition)
                case .surface:
                    surfaceStep
                        .transition(slideTransition)
                case .calibrate:
                    calibrateStep
                        .transition(slideTransition)
                case .island:
                    islandStep
                        .transition(slideTransition)
                case .activate:
                    activateStep
                        .transition(slideTransition)
                case .complete:
                    completeStep
                        .transition(slideTransition)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: step)
        }
        .padding(24)
        .frame(width: 530, height: 480)
        .background(DS.Colors.bg)
        .onAppear { step = initialStep }
    }

    // MARK: - Navigation

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: direction).combined(with: .opacity),
            removal: .move(edge: direction == .trailing ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        direction = .trailing
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            step = next
        }
    }

    private func goBack() {
        guard let prev = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        direction = .leading
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            step = prev
        }
    }

    // MARK: - Progress Bar

    // MARK: - Back Button

    private var backButton: some View {
        Button {
            goBack()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                Text("Back")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
            .foregroundStyle(DS.Colors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Primary Button

    private func primaryButton(
        _ title: String,
        enabled: Bool = true,
        hint: String = "",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(enabled ? .white : DS.Colors.textMuted)
                .frame(maxWidth: 240)
                .padding(.vertical, 12)
                .background(enabled ? DS.Colors.accentInfo : DS.Colors.textMuted.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)

            VStack(spacing: 10) {
                Text("GooseNeck")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("Real-time posture monitoring using\nyour MacBook's built-in sensors")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            primaryButton("Get Started", hint: "Review privacy and terms before setup.") {
                advance()
            }
        }
    }

    // MARK: - Step 1: Privacy & Terms

    private var privacyTermsStep: some View {
        VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 36))
                .foregroundStyle(DS.Colors.accentInfo)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                Text("Privacy & Terms")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("Your data stays on your Mac.\nReview our policies below.")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 20)

            // Two highlight cards side by side
            HStack(alignment: .top, spacing: 12) {
                legalHighlightCard(
                    title: "Privacy",
                    icon: "lock.shield",
                    highlights: LegalContent.privacyHighlights,
                    action: { showPrivacySheet = true }
                )
                legalHighlightCard(
                    title: "Terms",
                    icon: "doc.text",
                    highlights: LegalContent.termsHighlights,
                    action: { showTermsSheet = true }
                )
            }

            Spacer()

            primaryButton("I Agree & Continue", hint: "Accept privacy policy and terms of service to continue setup.") {
                UserDefaults.standard.set(true, forKey: "termsAccepted")
                UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: "termsAcceptedAt")
                viewModel.sensorClient.connect()
                advance()
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            LegalDocumentSheet(title: "Privacy Policy", content: LegalContent.privacyFullText, isPresented: $showPrivacySheet)
        }
        .sheet(isPresented: $showTermsSheet) {
            LegalDocumentSheet(title: "Terms of Service", content: LegalContent.termsFullText, isPresented: $showTermsSheet)
        }
    }

    private func legalHighlightCard(
        title: String,
        icon: String,
        highlights: [(icon: String, text: String)],
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Colors.accentInfo)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
            }

            // Bullet items
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(highlights.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(DS.Colors.textMuted)
                            .frame(width: 14, height: 14)
                        Text(item.text)
                            .font(.system(size: 10.5, weight: .regular, design: .rounded))
                            .foregroundStyle(DS.Colors.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)

            // Read full link
            Button(action: action) {
                HStack(spacing: 4) {
                    Text("Read full \(title.lowercased())")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(DS.Colors.accentInfo)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.cardBg, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(DS.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Step 2: Accelerometer

    private var accelerometerStep: some View {
        let avail = viewModel.sensorClient.sensorAvailability
        let hasAccel = avail?.hasAccelerometer == true
        let snapshot = viewModel.sensorClient.latestSnapshot

        return VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            // Coach mark
            MacBookFrontView(
                isDetected: hasAccel,
                liveValue: snapshot?.pitch
            )

            Spacer().frame(height: 24)

            // Text
            VStack(spacing: 8) {
                Text("Motion Sensor")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("Your MacBook has a built-in accelerometer\nthat detects tilt and movement")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 20)

            // Status
            statusBadge(
                detected: hasAccel,
                detecting: avail == nil,
                detectedText: "Motion sensor detected",
                notFoundText: viewModel.sensorClient.connectionError ?? "Accelerometer unavailable. Apple Silicon Mac required.",
                onRetry: { viewModel.sensorClient.connect() }
            )

            Spacer()

            primaryButton(
                "Continue",
                enabled: hasAccel,
                hint: hasAccel
                    ? "Continues to the screen angle sensor step."
                    : "Continue becomes available after the motion sensor is detected."
            ) {
                advance()
            }
        }
    }

    // MARK: - Step 2: Lid Angle

    private var lidAngleStep: some View {
        let avail = viewModel.sensorClient.sensorAvailability
        let hasLid = avail?.hasLidAngle == true
        let snapshot = viewModel.sensorClient.latestSnapshot
        let lidAngle = snapshot?.lidAngle ?? -1
        let displayAngle = lidAngle >= 0 ? lidAngle : 110
        let showResult = lidDetectionReady && avail != nil

        return VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            // Coach mark
            MacBookSideView(
                isDetected: showResult && hasLid,
                angle: displayAngle,
                liveValue: showResult && hasLid && lidAngle >= 0 ? lidAngle : nil
            )

            Spacer().frame(height: 24)

            // Text
            VStack(spacing: 8) {
                Text("Screen Angle Sensor")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("Tracks how open your screen is\nfor complete posture analysis")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 20)

            // Status — non-blocking, with brief detection animation
            if !showResult {
                statusBadge(
                    detected: false,
                    detecting: true,
                    detectedText: "",
                    notFoundText: "",
                    onRetry: {}
                )
            } else if hasLid {
                statusBadge(
                    detected: true,
                    detecting: false,
                    detectedText: "Screen angle sensor detected",
                    notFoundText: "",
                    onRetry: {}
                )
            } else {
                // Not available — friendly message
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Colors.textSecondary)
                    Text("Not available on your model — GooseNeck\nworks great with just the motion sensor")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textSecondary)
                        .lineSpacing(2)
                }
                .padding(12)
                .background(DS.Colors.textMuted.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            primaryButton("Continue", enabled: showResult, hint: "Continues to posture calibration.") {
                advance()
            }
        }
        .onAppear {
            lidDetectionReady = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    lidDetectionReady = true
                }
            }
        }
    }

    // MARK: - Step 3: Typing Intensity

    private var typingIntensityStep: some View {
        let snapshot = viewModel.sensorClient.latestSnapshot
        let typingRMS = snapshot?.typingRMS ?? 0
        let showResult = typingCheckReady

        return VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            // Visual
            TypingTestVisual(
                typingRMS: typingRMS,
                isDetected: showResult && typingDetected
            )
            .frame(maxWidth: 320)

            Spacer().frame(height: 24)

            // Text
            VStack(spacing: 8) {
                Text("Typing Detection")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("Detects keyboard activity through vibration\nto track typing fatigue over time")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 20)

            // Status
            if !showResult {
                statusBadge(
                    detected: false,
                    detecting: true,
                    detectedText: "",
                    notFoundText: "",
                    onRetry: {}
                )
            } else if typingDetected {
                statusBadge(
                    detected: true,
                    detecting: false,
                    detectedText: "Typing vibration detected",
                    notFoundText: "",
                    onRetry: {}
                )
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Colors.textSecondary)
                    Text("Available — will calibrate during use")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .padding(12)
                .background(DS.Colors.textMuted.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }

            Spacer()

            primaryButton("Continue", enabled: showResult, hint: "Continues to surface selection.") {
                advance()
            }
        }
        .onAppear {
            typingDetected = false
            typingCheckReady = false
            consecutiveTypingSamples = 0
        }
        .onChange(of: viewModel.sensorClient.latestSnapshot?.typingRMS) { _, rms in
            guard !typingCheckReady else { return }
            if let rms, rms > 0.0001 {
                consecutiveTypingSamples += 1
                if consecutiveTypingSamples >= 3 && !typingDetected {
                    typingDetected = true
                    // Premium delay before revealing result
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            typingCheckReady = true
                        }
                    }
                }
            } else {
                consecutiveTypingSamples = 0
            }
        }
        .task {
            // Timeout: if no typing after 10s, show fallback
            try? await Task.sleep(for: .seconds(10))
            guard !typingCheckReady else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    typingCheckReady = true
                }
            }
        }
    }

    // MARK: - Step 4: Surface

    private var surfaceStep: some View {
        VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            VStack(spacing: 8) {
                Text("Where's Your MacBook?")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("This helps set appropriate posture\nthresholds for your setup")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 28)

            HStack(spacing: 12) {
                surfaceOption(.desk, icon: "desktopcomputer", description: "On a table or desk")
                surfaceOption(.lap, icon: "laptopcomputer", description: "On your lap")
                surfaceOption(.couch, icon: "sofa.fill", description: "On a soft surface")
            }
            .padding(.horizontal, 24)

            Spacer()

            primaryButton("Continue", hint: "Continues to posture calibration.") {
                advance()
            }
        }
    }

    private func surfaceOption(_ surface: Surface, icon: String, description: String) -> some View {
        let isSelected = viewModel.selectedSurface == surface

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                viewModel.selectedSurface = surface
            }
        } label: {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? DS.Colors.accentInfo : DS.Colors.textMuted)

                Text(surface.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text(description)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? DS.Colors.accentInfo.opacity(0.08) : DS.Colors.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? DS.Colors.accentInfo : DS.Colors.cardBorder, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(surface.label)
        .accessibilityHint(description)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Step 5: Calibrate

    private var calibrateStep: some View {
        let snapshot = viewModel.sensorClient.latestSnapshot
        let hasSensorData = snapshot != nil
        let pitchDrift = viewModel.postureAnalyzer.pitchDrift
        let lidDrift = viewModel.postureAnalyzer.lidAngleDrift

        return VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            // Live PostureFigure orb
            PostureFigure(
                pitchDrift: calibrationDone ? 0 : pitchDrift,
                lidAngleDrift: calibrationDone ? 0 : lidDrift,
                isDrifting: false
            )

            Spacer().frame(height: 20)

            VStack(spacing: 8) {
                Text("Set Your Baseline")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("Sit in your ideal posture with your screen\nat a comfortable angle, then calibrate")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 20)

            if calibrationDone {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Colors.accentGood)
                    Text("Baseline recorded")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.accentGood)
                }
                .transition(.scale.combined(with: .opacity))
            } else if !hasSensorData {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Waiting for sensor data...")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
            } else {
                primaryButton("Calibrate") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        calibrationDone = viewModel.calibrate()
                    }
                    if calibrationDone {
                        NotificationManager.shared.requestPermission()
                    }
                }
                .accessibilityHint("Sets your current sitting posture as the monitoring baseline.")
            }

            Spacer()

            if calibrationDone {
                if NotificationManager.shared.systemAuthorizationDenied {
                    notificationDenialHint
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                primaryButton("Continue", hint: "Continues to the Posture Island preview.") {
                    advance()
                }
            }
        }
    }

    private var notificationDenialHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Colors.textMuted)
            Text("Notifications are off — you can enable them in System Settings anytime")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(DS.Colors.textMuted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(DS.Colors.cardBg.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Step 6: Island Preview

    private var islandStep: some View {
        @Bindable var vm = viewModel

        return VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            // Island mockup
            IslandPreviewMockup()
                .scaleEffect(0.95)

            Spacer().frame(height: 28)

            VStack(spacing: 8) {
                Text("Posture Island")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("A floating widget near your notch showing\nreal-time posture status at a glance")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer().frame(height: 24)

            // Toggle
            HStack {
                Text("Enable Posture Island")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $vm.dynamicIslandEnabled)
                    .toggleStyle(.switch)
                    .tint(DS.Colors.accentInfo)
                    .labelsHidden()
                    .accessibilityLabel("Enable Posture Island")
                    .accessibilityHint("Shows a floating posture summary near the top of the screen.")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(DS.Colors.cardBg, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 40)

            Spacer()

            primaryButton("Continue", hint: "Continues to license activation.") {
                advance()
            }
        }
    }

    // MARK: - Step 7: Activate

    private var activateStep: some View {
        VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }

            Spacer()

            // Icon
            Image(systemName: "key.fill")
                .font(.system(size: 44))
                .foregroundStyle(DS.Colors.accentInfo)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                Text("Activate GooseNeck")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("Enter your license key to start monitoring")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
            }

            Spacer().frame(height: 28)

            // Buy button
            Button {
                licenseManager.openCheckout()
            } label: {
                VStack(spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "cart")
                            .font(.system(size: 13))
                        Text("Buy a License — $14.99")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    Text("One-time purchase · Unlimited updates")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.7)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 280)
                .padding(.vertical, 12)
                .background(DS.Colors.accentInfo, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the Polar checkout page to buy a GooseNeck license for $14.99.")

            // Divider
            HStack(spacing: 12) {
                Rectangle()
                    .fill(DS.Colors.cardBorder)
                    .frame(height: 1)
                Text("already have a key?")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textMuted)
                    .layoutPriority(1)
                Rectangle()
                    .fill(DS.Colors.cardBorder)
                    .frame(height: 1)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 40)

            // Key entry
            HStack(spacing: 8) {
                TextField("Paste license key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, design: .monospaced))
                    .accessibilityLabel("License key")

                if licenseManager.isValidating || isActivating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 70)
                } else {
                    Button("Activate") {
                        // Debounce: ignore taps while a request is in flight.
                        guard !isActivating else { return }
                        isActivating = true
                        Task {
                            defer { isActivating = false }
                            await licenseManager.activate(key: licenseKey)
                            if licenseManager.isLicensed {
                                await MainActor.run {
                                    viewModel.unlockMonitoring()
                                    viewModel.start()
                                    advance()
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Colors.accentGood)
                    .disabled(
                        isActivating
                            || licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityHint(
                        licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Paste a license key before activating."
                            : "Activates your license and completes setup."
                    )
                }
            }
            .padding(.horizontal, 40)

            if let error = licenseManager.error {
                Text(error)
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.accentDanger)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - Status Badge

    private func statusBadge(
        detected: Bool,
        detecting: Bool,
        detectedText: String,
        notFoundText: String,
        onRetry: @escaping () -> Void
    ) -> some View {
        Group {
            if detecting {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Detecting sensor...")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.textMuted)
                }
                .padding(12)
                .background(DS.Colors.textMuted.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            } else if detected {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Colors.accentGood)
                    Text(detectedText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.accentGood)
                }
                .padding(12)
                .background(DS.Colors.accentGood.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .transition(.scale.combined(with: .opacity))
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DS.Colors.accentDanger)
                        Text(notFoundText)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Colors.accentDanger)
                            .multilineTextAlignment(.leading)
                    }

                    Button("Retry") {
                        onRetry()
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.accentInfo)
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(DS.Colors.accentDanger.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Step 7: Complete

    private var completeStep: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DS.Colors.accentGood)
                .padding(.bottom, 16)

            VStack(spacing: 10) {
                Text("You're all set!")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text("GooseNeck is now monitoring from your menu bar.\nLook for the goose icon at the top of your screen.")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            Spacer()

            primaryButton("Get Started", hint: "Closes setup and starts monitoring.") {
                isComplete = true
            }
        }
    }
}

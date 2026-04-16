import Foundation

// Legal text sourced from posture-desk-website/src/pages/privacy.astro and terms.astro
// Keep in sync when updating website content.

enum LegalContent {
    static let lastUpdated = "April 2026"

    // MARK: - Privacy Highlights

    static let privacyHighlights: [(icon: String, text: String)] = [
        ("eye.slash", "No camera or microphone access — ever"),
        ("internaldrive", "All sensor data stays on your Mac"),
        ("chart.bar.xaxis", "No analytics, telemetry, or tracking"),
        ("key", "License validated via Polar (key + hostname only)"),
        ("arrow.down.circle", "Sparkle checks for updates (sends app/OS version)"),
    ]

    // MARK: - Terms Highlights

    static let termsHighlights: [(icon: String, text: String)] = [
        ("infinity", "Lifetime license — one device at a time"),
        ("desktopcomputer", "Requires Apple Silicon Mac, macOS 14+"),
        ("gearshape.2", "Uses private macOS APIs — may change with updates"),
        ("heart.text.square", "For wellness only — not a medical device"),
        ("arrow.uturn.left", "15-day refund if it doesn't work for you"),
    ]

    // MARK: - Full Privacy Policy

    static let privacyFullText: String = """
    **Privacy Policy**
    Last updated: \(lastUpdated)

    ## Overview

    GooseNeck is built with privacy as a core principle. The app uses your MacBook's built-in accelerometer and lid angle sensor to monitor posture — it never accesses your camera or microphone. All sensor data is processed entirely on your device and is never transmitted to external servers. No accounts or personal information are required to use GooseNeck.

    ## Data We Do Not Collect

    - Camera or microphone data — never accessed
    - Personal information — no accounts, no email collection in the app
    - Usage analytics or telemetry — no tracking of any kind
    - Location data — not requested or used
    - Crash reports or diagnostic data — no crash reporting SDK
    - Browsing or app usage data — GooseNeck does not monitor activity outside the app
    - Biometric data — the sensors measure device orientation, not body metrics

    ## Data Stored Locally

    GooseNeck stores the following data locally on your Mac. None of this data is transmitted off your device.

    - **Sensor session data:** device pitch angle, roll angle, lid angle, typing intensity, vibration variance, timestamps, and detected surface type (desk, lap, or couch)
    - **Calibration baselines:** your baseline posture angles per surface type, used to detect drift
    - **Session history:** posture alerts triggered, breaks taken, active minutes, and typing intensity per session
    - **User preferences:** drift sensitivity, break interval, fatigue threshold, theme, notification settings, launch-at-login, and Dynamic Island display preferences (stored in macOS UserDefaults)
    - **License key:** stored in macOS Keychain, encrypted by the operating system

    Session data is stored using SwiftData (SQLite) in ~/Library/Application Support/GooseNeck/. Data is retained locally until you delete it or uninstall the application. There are no automatic data purge mechanisms.

    ## License Validation

    GooseNeck validates your license key through the Polar API. This occurs at activation and periodically thereafter to confirm the license remains valid. The following data is sent during validation:

    - Your license key
    - Your machine's hostname (used to bind the license to one device)

    No other data is transmitted during validation. If your Mac is offline, GooseNeck continues to function for up to 7 days after the last successful validation. Your license key is stored in macOS Keychain, encrypted by the operating system — it is not stored in plaintext files.

    ## Third-Party Services

    Payment processing and license key generation are handled by Polar (polar.sh). GooseNeck communicates with the Polar API solely for license validation. The only data sent to Polar is your license key and machine hostname. GooseNeck never sees or stores your payment information.

    GooseNeck uses Sparkle, an open-source update framework, to check for new versions. This may send your macOS version and app version to our update server. No other data is sent.

    No other third-party services, SDKs, analytics providers, or ad networks are used.

    ## Children's Privacy

    GooseNeck is not directed at children under 13. We do not knowingly collect personal data from any user, including children. Since GooseNeck does not collect personal information, no special handling is required under COPPA or similar regulations.

    ## Security

    Sensor and session data is stored locally using SwiftData with standard macOS file-system permissions. Your license key is stored in macOS Keychain, which uses hardware-backed encryption on Apple Silicon Macs. No sensor or session data is ever transmitted over the network. GooseNeck contains no third-party SDKs that could introduce external data collection.

    ## Changes to This Policy

    We may update this privacy policy from time to time. Changes will be reflected by updating the "Last updated" date at the top of this page. Continued use of GooseNeck after changes constitutes acceptance of the updated policy.

    ## Contact

    If you have questions about this privacy policy, contact us at support@gooseneck.app.
    """

    // MARK: - Full Terms of Service

    static let termsFullText: String = """
    **Terms of Service**
    Last updated: \(lastUpdated)

    ## License Grant

    Upon purchase and activation, you are granted a non-exclusive, non-transferable, perpetual license to use GooseNeck on one Apple Silicon Mac (M1 or later) running macOS 14 Sonoma or later. This is a lifetime license — there are no recurring fees. "Lifetime" means the lifetime of the application: you receive all updates we release, but specific features may change or become unavailable due to factors outside our control, including changes to macOS. The license is tied to one machine at a time. You may deactivate your license and reactivate it on a different device. The license requires periodic online validation via the Polar API, with a 7-day offline grace period.

    ## Restrictions

    - You may not redistribute, resell, or sublicense the software
    - You may not reverse-engineer, decompile, or disassemble the software
    - You may not share your activation key with others
    - You may not circumvent or attempt to circumvent the license validation mechanism
    - You may not use the software on unsupported hardware or operating system versions

    ## System Requirements

    - Apple Silicon Mac (M1, M2, M3, M4 series or later)
    - macOS 14 Sonoma or later
    - Internet connection required for initial activation and periodic license validation

    GooseNeck accesses your MacBook's accelerometer and lid angle sensor through macOS system interfaces. These interfaces are not part of Apple's public API and may change or become unavailable in any macOS update without prior notice. We test against each major macOS release and make commercially reasonable efforts to maintain compatibility, but we cannot guarantee uninterrupted functionality across all future macOS versions.

    ## Intellectual Property

    GooseNeck and all associated trademarks, logos, and content are the property of the developer. The license grant does not transfer ownership of any intellectual property. Feedback submitted to support may be used to improve the product without obligation.

    ## Disclaimer of Warranties

    GooseNeck is provided "as is" without warranties of any kind. GooseNeck is not a medical device and should not be used as a substitute for professional medical advice. The posture monitoring features are intended for general wellness purposes only. GooseNeck uses private macOS APIs that may change without notice — we do not warrant uninterrupted or error-free operation, particularly across macOS updates.

    ## Limitation of Liability

    In no event shall GooseNeck or its developers be liable for any indirect, incidental, special, or consequential damages arising out of or in connection with the use of the software. In any event, our total aggregate liability shall not exceed the amount you paid for the software license.

    ## Updates

    Your license includes all future updates for Apple Silicon Macs. Updates are distributed directly from our website. GooseNeck may check for available updates but will not auto-install without your consent. Due to the use of private macOS APIs, we cannot guarantee that future macOS versions will remain compatible. We will make commercially reasonable efforts to release compatibility updates.

    ## Termination

    This license is perpetual but may be terminated if you violate these terms. Upon termination, you must cease all use of the software and delete all copies. The following sections survive termination: Intellectual Property, Disclaimer of Warranties, Limitation of Liability, and this Termination section.

    ## Refunds

    If GooseNeck fails to function on your supported device, contact us at support@gooseneck.app within 15 days of purchase and we will work to resolve the issue or provide a refund. Beyond the 15-day window, refunds are provided at our discretion.

    ## Changes to These Terms

    We reserve the right to modify these terms at any time. Changes take effect upon posting to this website with an updated date. Continued use of GooseNeck after changes constitutes acceptance of the updated terms.

    ## Contact

    For questions about these terms, contact us at support@gooseneck.app.
    """
}

# GooseNeck 1.0.0 — first public release 🦢

A privacy-first posture coach that lives in your menu bar and uses your MacBook's built-in hardware sensors to keep you honest about how you're sitting. No webcam. No cloud. No account required.

## What's in the box

- **Real-time posture drift detection.** Calibrate once with a healthy posture and GooseNeck warns you when you've been leaning, slouching, or tilted away from baseline for too long. A 90-second sliding window prevents nags on momentary movement.
- **Adaptive surface awareness.** Pick desk, lap, or couch — drift thresholds and break cadence adjust automatically.
- **Break tracking.** Gentle, dismissible reminders when you've been heads-down past your configured interval.
- **Typing fatigue monitoring.** A bandpass filter on accelerometer data detects sustained intense typing that correlates with hand and wrist strain.
- **Menu bar status + optional overlay.** At-a-glance posture state without opening anything. The floating status pill near the notch is opt-in.
- **Fully local.** No webcam, no cloud sync, no telemetry. The only network calls are auto-update checks (a static appcast file) and a license-server roundtrip at activation.

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer) — the sensors GooseNeck reads aren't exposed on Intel Macs.

## Install

1. Download `GooseNeck.dmg` below.
2. Open the DMG, drag the app to your Applications folder.
3. Launch. The first run walks you through onboarding and calibration.

The DMG is signed with a Developer ID certificate and notarized by Apple — Gatekeeper will accept it without the "unidentified developer" warning.

## Privacy

All sensor processing happens on-device. There is no analytics, no telemetry, and no usage data sent anywhere. The only outbound network requests are the Sparkle update check (a static appcast file) and a license-server roundtrip at activation and during periodic re-validation.

## Auto-updates

Updates are delivered via [Sparkle](https://sparkle-project.org), signed with EdDSA, and verified against a public key embedded in the app — even a compromised update channel can't push a malicious build.

## Known limitations

- **Apple Silicon only.** The accelerometer and lid-angle sensors GooseNeck reads aren't available on Intel Macs.
- **First-time permissions.** macOS may prompt for input-monitoring access on the first launch (used only to detect typing intensity; keystrokes are never logged).

---

Bug reports and feature requests: [open an issue](https://github.com/thanhtut28/gooseneck/issues).

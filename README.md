# GooseNeck

A privacy-first posture coach that lives in your menu bar.

GooseNeck uses your MacBook's built-in hardware sensors — the accelerometer and lid-angle sensor — to detect when you're slouching, stuck in one position too long, or typing intensely enough to need a break. No webcam. No cloud. Everything runs locally on your Mac.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-orange) ![Developer ID](https://img.shields.io/badge/Signed-Developer%20ID-green)

## What it does

- **Real-time posture drift detection** — calibrate once with a healthy posture; the app warns you when you've been leaning, slouching, or tilted away from your baseline for too long.
- **Adaptive surface awareness** — desk, lap, or couch. Drift thresholds adjust automatically.
- **Break tracking** — gentle nudges when you've been heads-down too long.
- **Typing fatigue monitoring** — detects sustained intense typing that correlates with strain.
- **Live menu bar status + optional Dynamic Island-style overlay** — at-a-glance state without opening anything.

## Privacy

Everything stays on your Mac. There is no telemetry, no analytics, no cloud sync, no account required to use the app. The only network requests it makes are:

- Auto-update checks against `https://gooseneck-updates.pages.dev/appcast.xml` (a static appcast file).
- License activation against `api.polar.sh` once at first activation, then periodic re-validation.

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon Mac (M1 or newer) — the app reads sensors that aren't exposed on Intel Macs.

## Install

1. Download the latest `GooseNeck.dmg` from the [Releases](https://github.com/thanhtut28/gooseneck/releases) page.
2. Open the DMG, drag GooseNeck to your Applications folder.
3. Launch. The first run walks you through onboarding, sensor detection, and calibration.

The DMG is signed with a Developer ID certificate and notarized by Apple — Gatekeeper will accept it without warnings.

## Auto-updates

GooseNeck uses [Sparkle](https://sparkle-project.org) to check for updates in the background. New releases are signed with EdDSA and verified against an embedded public key before installing — there's no path for an attacker to push a malicious update even if the update channel were compromised.

## Support

Bug reports and feature requests: please use [Issues](https://github.com/thanhtut28/gooseneck/issues) on this repo.

## License

Proprietary. The compiled binaries available from Releases are licensed for personal use under the terms shown in the app's onboarding flow. Source code is not currently public.

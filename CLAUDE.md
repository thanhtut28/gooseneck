# PostureDesk

Real-time posture and ergonomic coach for Apple Silicon MacBooks. Menu bar app that uses hidden hardware sensors (accelerometer, lid angle) to monitor posture drift, track breaks, and detect typing fatigue — no webcam needed.

## Quick Reference

```bash
make generate      # xcodegen → PostureDesk.xcodeproj
make build         # generate + xcodebuild Debug
make run           # build + open .app
make daemon-test   # build + sudo run daemon standalone
make clean         # remove build artifacts
```

**Requirements:** Xcode 16+, Swift 5.10, Apple Silicon Mac (M1+), macOS 14 Sonoma+

## Architecture

Two-process privilege-separated design:

```
PostureDesk.app (SwiftUI, unprivileged)
    ↕ XPC (PostureSensorProtocol)
PostureSensorDaemon (launchd helper, privileged)
    ↕ IOKit HID callbacks
AppleSPUHIDDevice (BMI286 accelerometer + lid angle sensor)
```

- **Daemon** reads raw IOKit HID at ~100Hz, runs signal pipeline (Kalman → Mahony AHRS → Bandpass → FFT), emits 1Hz `SensorSnapshot` over XPC
- **App** receives snapshots and runs analysis (drift detection, break tracking, fatigue monitoring)
- Currently uses `DirectSensorClient` (in-process) by default; `SensorXPCClient` available as alternative

## Project Structure

```
PostureDesk/          ← Main app target (SwiftUI menu bar app)
  PostureDeskApp.swift    Entry point, MenuBarExtra, onboarding
  ViewModels/             PostureViewModel (central service hub)
  Services/               Sensor clients, analyzers, notifications
  Views/                  MenuBarPopover, Dashboard/, History/, Settings/
  Models/                 SwiftData models (Session, Calibration, Settings)
  Resources/              Assets.xcassets

PostureSensorDaemon/  ← Privileged helper target (CLI tool)
  main.swift              XPC listener setup
  SensorManager.swift     IOKit HID device access
  SignalProcessor.swift   1-second snapshot aggregation
  XPCServer.swift         PostureSensorProtocol implementation
  Filters/                KalmanFilter, MahonyAHRS, BandpassFilter, FFTAnalyzer

Shared/               ← Shared between both targets
  PostureSensorProtocol.swift   XPC @objc protocol (3 methods)
  SensorTypes.swift             SensorSnapshot, SensorAvailability, Surface enum

LaunchDaemons/        ← launchd plist for daemon registration
```

## Build System

- **XcodeGen** (`project.yml`) generates the Xcode project — run `make generate` after changing targets/settings
- Two targets: `PostureDesk` (app) and `PostureSensorDaemon` (tool)
- Post-build script copies daemon binary + plist into app bundle at `Contents/Library/`
- The app target includes daemon sources (excluding `main.swift`, `XPCServer.swift`) for `DirectSensorClient`
- Frameworks: IOKit, Accelerate (vDSP for FFT)
- No third-party dependencies

## Key Conventions

- **State management:** `@Observable` macro (Swift 5.10 macOS 14+), `@Binding` for two-way UI, `@Environment` for DI
- **XPC transport:** `NSSecureCoding` for custom types (`SensorSnapshot`, `SensorAvailability`)
- **Thread safety:** `NSLock` in `SignalProcessor` for sample buffer access
- **IOKit callbacks:** `Unmanaged.passUnretained` + `toOpaque()` for C function pointer context
- **Persistence:** SwiftData (`SessionRecord`, `CalibrationProfile`, `UserSettings`) — all local, no cloud sync
- **UI:** Dark mode only, design tokens in `DesignSystem.swift` (colors, fonts, spacing, card modifier)
- **Notifications:** Per-category throttling via `NotificationManager` singleton (posture 15min, break 5min, fatigue 30min)

## Key Algorithms

- **Drift detection** (`PostureAnalyzer`): 90-sec sliding window, fires if drift > threshold AND >70% of samples above 80% threshold AND monotonically increasing (second-half > first-half avg)
- **Orientation** (`MahonyAHRS`): Quaternion complementary filter, accelerometer-only (kp=4.0), outputs pitch/roll
- **Typing detection** (`BandpassFilter`): Cascaded Butterworth 5-45Hz, RMS of bandpass output = typing intensity
- **Presence** (`BreakTracker`): `CGEventSource.secondsSinceLastEventType` for system idle, 30-sec away threshold
- **Surface thresholds:** desk=10deg, lap=15deg, couch=20deg drift sensitivity

## Important Notes

- **Private APIs:** IOKit HID access to `AppleSPUHIDDevice` is undocumented — may break with macOS updates. Not App Store eligible.
- **Sensor variance:** Not all MacBook models expose lid angle sensor. Accelerometer report format may differ across models.
- **Sandbox disabled** in both targets (required for IOKit HID access)
- **No tests yet** — test infrastructure not set up
- Design spec lives at `docs/superpowers/specs/2026-03-27-posture-desk-design.md`

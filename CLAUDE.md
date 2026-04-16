# GooseNeck

Real-time posture and ergonomic coach for Apple Silicon MacBooks. Menu bar app that uses hidden hardware sensors (accelerometer, lid angle) to monitor posture drift, track breaks, and detect typing fatigue — no webcam needed.

## Quick Reference

```bash
make generate      # xcodegen → GooseNeck.xcodeproj
make build         # generate + xcodebuild Debug
make run           # build + open .app
make clean         # remove build artifacts
```

**Requirements:** Xcode 16+, Swift 5.10, Apple Silicon Mac (M1+), macOS 14 Sonoma+

## Architecture

Single-process direct sensor runtime:

```
GooseNeck.app (SwiftUI menu bar app)
    ↕ in-process IOKit HID callbacks
AppleSPUHIDDevice (BMI286 accelerometer + lid angle sensor)
```

- **DirectSensorClient** owns sensor access and snapshot generation in-process
- Shared sensor pipeline reads raw IOKit HID at ~100Hz, runs Kalman → Mahony AHRS → Bandpass → FFT, and produces a 1Hz `SensorSnapshot`
- The app runs analysis (drift detection, break tracking, fatigue monitoring), notifications, and persistence locally

## Project Structure

```
GooseNeck/          ← Main app target (SwiftUI menu bar app)
  GooseNeckApp.swift    Entry point, MenuBarExtra, onboarding
  ViewModels/             PostureViewModel (central service hub)
  Services/               Direct sensor client, analyzers, notifications
  Views/                  MenuBarPopover, Dashboard/, History/, Settings/
  Models/                 SwiftData models (Session, Calibration, Settings)
  Resources/              Assets.xcassets

PostureSensorDaemon/  ← Shared sensor pipeline sources (compiled into app)
  SensorManager.swift     IOKit HID device access
  SignalProcessor.swift   1-second snapshot aggregation
  Filters/                KalmanFilter, MahonyAHRS, BandpassFilter, FFTAnalyzer

Shared/               ← Shared app types
  SensorTypes.swift             SensorSnapshot, SensorAvailability, Surface enum
```

## Build System

- **XcodeGen** (`project.yml`) generates the Xcode project — run `make generate` after changing targets/settings
- One target: `GooseNeck` (app), plus `GooseNeckTests`
- The app target compiles the shared sensor pipeline from `PostureSensorDaemon/`
- Frameworks: IOKit, Accelerate (vDSP for FFT)
- No third-party dependencies

## Key Conventions

- **State management:** `@Observable` macro (Swift 5.10 macOS 14+), `@Binding` for two-way UI, `@Environment` for DI
- **Sensor types:** `NSSecureCoding` models for shared sensor value transport and persistence-friendly bridging
- **Thread safety:** `NSLock` in `SignalProcessor` for sample buffer access
- **IOKit callbacks:** `Unmanaged.passUnretained` + `toOpaque()` for C function pointer context
- **Persistence:** SwiftData (`SessionRecord`, `CalibrationProfile`, `UserSettings`) — all local, no cloud sync
- **UI:** Dark mode only, design tokens in `DesignSystem.swift` (colors, fonts, spacing, card modifier)
- **Notifications:** Per-category throttling via `NotificationManager` singleton (posture 15min, break 30s guard, fatigue 30min); break repeat cadence managed by `BreakTracker`

## Key Algorithms

- **Drift detection** (`PostureAnalyzer`): 90-sec sliding window, fires if drift > threshold AND >70% of samples above 80% threshold
- **Orientation** (`MahonyAHRS`): Quaternion complementary filter, accelerometer-only (kp=4.0), outputs pitch/roll
- **Typing detection** (`BandpassFilter`): Cascaded Butterworth 5-45Hz, RMS of bandpass output = typing intensity
- **Presence** (`BreakTracker`): `CGEventSource.secondsSinceLastEventType` for system idle, 30-sec away threshold
- **Surface thresholds:** desk=10deg, lap=15deg, couch=20deg drift sensitivity

## Important Notes

- **Private APIs:** IOKit HID access to `AppleSPUHIDDevice` is undocumented — may break with macOS updates. Not App Store eligible.
- **Sensor variance:** Not all MacBook models expose lid angle sensor. Accelerometer report format may differ across models.
- **Sandbox disabled** in the app target (required for IOKit HID access)
- **Tests available** via `xcodebuild test` and the `GooseNeckTests` target
- Design spec lives at `docs/superpowers/specs/2026-03-27-posture-desk-design.md`

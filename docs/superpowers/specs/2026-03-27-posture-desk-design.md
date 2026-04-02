# PostureDesk — Design Specification

A real-time posture and ergonomic coach for Apple Silicon MacBooks that uses hidden hardware sensors (accelerometer, lid angle sensor) to monitor posture drift, detect breaks, track typing fatigue, and classify working surfaces. Runs as a lightweight menu bar app.

## Context

Remote workers and developers spend money on ergonomic hardware (standing desks, chairs, monitor arms) but have no passive software solution that monitors posture without a webcam. Apple Silicon MacBooks contain a Bosch BMI286 6-axis IMU and a lid angle sensor — both undocumented but accessible via IOKit HID. SlapMyMac proved there's a market for sensor-based Mac apps. PostureDesk takes the same sensor access and applies it to a genuine productivity/health use case.

## Product Decisions

- **Price**: $3 one-time purchase (adjustable later)
- **Distribution**: Direct download from website (not App Store — private API usage violates Guideline 2.5.1)
- **Signing**: Developer ID + Apple notarization
- **Platform**: macOS on Apple Silicon only (M1+)
- **UI**: Menu bar app with popover. No full dashboard window in v1.
- **Data**: All local (SwiftData/SQLite). No accounts, no cloud sync.

## Tech Stack

- **Language**: Swift
- **UI**: SwiftUI (menu bar + popover)
- **Sensor access**: IOKit HID (C API via bridging header)
- **Signal processing**: Accelerate framework (vDSP for FFT, bandpass filters)
- **Runtime architecture**: Direct in-process sensor access via IOKit HID
- **Persistence**: SwiftData
- **Notifications**: UserNotifications framework
- **Min deployment**: macOS 14 Sonoma (SwiftData requires this)

## Architecture

Single-process menu bar app with direct sensor access:

```
PostureDesk.app (SwiftUI)
    ↕ in-process IOKit HID callbacks
AppleSPUHIDDevice (BMI286 accelerometer + lid angle sensor)
```

**Direct sensor pipeline**:
- Reads raw IOKit HID data at ~100Hz (22-byte reports, x/y/z as int32 LE, divide by 65536 for g-force)
- Reads lid angle via HID Feature Report ID 1 (16-bit LE centidegrees)
- Runs signal processing: gravity removal (Kalman filter), orientation (Mahony AHRS), bandpass filtering, FFT
- Emits a `SensorSnapshot` every 1 second to the app runtime

**PostureDesk.app**:
- Owns the sensor pipeline directly via `DirectSensorClient`
- Runs analysis logic (drift detection, break tracking, fatigue monitoring, surface classification)
- Manages notifications, UI state, data persistence

### IOKit HID Access Details

- **Device**: AppleSPUHIDDevice
- **Vendor ID**: 0x05AC (Apple)
- **Product ID**: 0x8104 (Sensor Hub)
- **Accelerometer**: Usage Page 0xFF00, Usage ID 0x03
- **Gyroscope**: Usage Page 0xFF00, Usage ID 0x09
- **Lid Angle**: Usage Page 0x0020, Usage ID 0x008A
- **Report format**: 22-byte HID reports; X at bytes 6-9, Y at bytes 10-13, Z at bytes 14-17 (int32 LE / 65536 = g-force)
- **Lid angle format**: Feature Report ID 1, 16-bit LE centidegrees

## Features

### Feature 1: Posture Drift Detection

**Inputs**: Lid angle (10Hz) + device pitch/roll (1Hz averaged from Mahony AHRS) + calibrated baseline

**Algorithm**:
1. Compute combined drift: `|lid_angle - baseline_lid| + |pitch - baseline_pitch|`
2. Track drift over 90-second sliding window
3. Alert if drift exceeds threshold AND trend is increasing over the window (net drift positive, allowing minor fluctuations — no sustained user self-correction detected)
4. Surface-aware thresholds: desk = 10°, lap = 15°, couch = 20°

**Notification**: "You've shifted X° from your baseline in the last Y minutes." Actions: [Recalibrate] [Dismiss]. Max 1 per 15 minutes.

### Feature 2: Break / Presence Detection

**Inputs**: Typing impulse detection (STA/LTA on accelerometer) + vibration RMS baseline

**Algorithm**:
1. Active = any keystroke impulse detected in last 30 seconds
2. Away = no impulses for 30s AND vibration RMS below idle threshold
3. Session timer runs while Active, pauses while Away
4. Break reminder at configurable interval (default 45 min active time)
5. Auto-reset session after 5+ minutes away

**Notification**: "You've been working for Xh Ym straight. Stand up, stretch, look at something far away." Actions: [Snooze 15m] [Done]. Fires at configurable interval.

### Feature 3: Typing Fatigue

**Inputs**: Typing RMS energy (bandpass 5-100Hz, 1-second windows) + session baseline (first 15 min average)

**Algorithm**:
1. Compute rolling 5-minute average of typing RMS during active typing windows
2. Compare against session baseline
3. Alert if current > baseline * 1.3 for 5+ minutes
4. Reset baseline on new session (after 5+ min away)

**Notification**: "Your typing intensity is up X% from your session start. Your hands might need a rest." Actions: [Got it]. Max 1 per 30 minutes.

### Feature 4: Surface Detection

**Inputs**: Gravity vector variance (1s windows) + vibration frequency profile (FFT bins) + RMS amplitude

**Algorithm (threshold-based v1)**:
1. Desk: low gravity jitter + high-frequency vibration content
2. Lap: medium gravity jitter + body micro-movement patterns
3. Couch: high gravity jitter + heavily damped vibrations
4. Require 3 consecutive same-class predictions (3 seconds) before switching classification
5. On surface change: adjust posture drift thresholds + notify user

**Notification**: "Looks like you moved to [surface]. Posture thresholds adjusted." Informational only.

## Data Model (SwiftData)

```swift
@Model class Session {
    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var surface: Surface           // .desk | .lap | .couch
    var totalActiveMinutes: Int
    var postureAlertCount: Int
    var breaksTaken: Int
    var avgTypingIntensity: Double
    var peakTypingIntensity: Double
}

@Model class CalibrationProfile {
    var id: UUID
    var createdAt: Date
    var lidAngleBaseline: Double   // degrees
    var pitchBaseline: Double      // degrees
    var rollBaseline: Double       // degrees
    var isActive: Bool
}

@Model class UserSettings {
    var breakIntervalMinutes: Int          // default 45
    var postureDriftThreshold: Double      // default 10°
    var fatigueThresholdPercent: Double    // default 30%
    var notificationsEnabled: Bool
    var launchAtLogin: Bool
}
```

## UI

### Menu Bar Icon States

| State | Icon | Condition |
|-------|------|-----------|
| Good | 🧘 | Within baseline thresholds |
| Drifting | ⚠️ | Posture drift alert triggered |
| Break Needed | 🔴 | Active session exceeds break interval |
| Away | 💤 | No activity detected, timers paused |

### Menu Bar Popover (280px wide)

- **Status header**: Current posture state + session duration
- **Metrics**: Lid angle drift, device tilt, typing intensity (% from baseline), detected surface
- **Break timer**: Countdown to next break + Skip button
- **Quick actions**: Recalibrate / Pause 1hr / Settings

### First Launch Flow

1. Welcome screen (what PostureDesk does)
2. Sensor check (verify which sensors are available, graceful degradation if lid angle missing)
3. Calibrate ("Sit in your ideal posture. Press Calibrate." Records the real baseline)
4. Ready (menu bar icon appears, monitoring starts)

## Project Structure

```
PostureDesk/
├── PostureDesk/                    ← Main app target
│   ├── PostureDeskApp.swift        ← Entry point, menu bar setup
│   ├── Views/
│   │   ├── MenuBarPopover.swift
│   │   ├── OnboardingView.swift
│   │   └── SettingsView.swift
│   ├── Services/
│   │   ├── DirectSensorClient.swift ← In-process sensor runtime
│   │   ├── PostureAnalyzer.swift   ← Drift detection logic
│   │   ├── BreakTracker.swift      ← Session & presence tracking
│   │   ├── FatigueMonitor.swift    ← Typing intensity analysis
│   │   ├── SurfaceClassifier.swift ← Desk/lap/couch detection
│   │   └── NotificationManager.swift
│   ├── Models/
│   │   ├── Session.swift
│   │   ├── CalibrationProfile.swift
│   │   ├── UserSettings.swift
│   │   └── SensorSnapshot.swift
│   └── Resources/
│       └── Assets.xcassets
├── PostureSensorDaemon/            ← Shared sensor pipeline sources compiled into app
│   ├── SensorManager.swift         ← IOKit HID setup & callbacks
│   ├── SignalProcessor.swift       ← Kalman, Mahony, FFT, filters
│   └── Filters/
├── Shared/                         ← Shared app enums & structs
│   └── SensorTypes.swift
└── PostureDesk.xcodeproj
```

## Verification Plan

1. **Sensor access**: Launch the app, verify accelerometer data streams at expected rate and lid angle reads correctly
2. **Startup**: Confirm monitoring starts without any helper installation step
3. **Posture drift**: Manually tilt laptop by 10°+, confirm alert fires after 90s
4. **Break detection**: Type, stop for 30s, confirm Away state. Type for 45+ min, confirm break reminder
5. **Typing fatigue**: Type normally for 15 min (baseline), then type harder — confirm intensity % increases in popover
6. **Surface detection**: Test on desk, lap, couch — confirm classification changes after 3s
7. **Notifications**: Verify all 4 notification types render with correct actions, respect throttle limits
8. **Onboarding**: Fresh install → full onboarding flow → monitoring active
9. **Graceful degradation**: Test on a Mac model missing lid angle sensor — app should still work with accelerometer-only features

## Known Risks

- **Private API**: IOKit HID access to AppleSPUHIDDevice is undocumented. May break with macOS updates. Requires testing each major release.
- **Model variance**: Some M1/M2 MacBook Air models may not expose the lid angle sensor. Runtime detection + graceful degradation required.
- **Signal noise**: Fan vibration, desk bumps, and environmental noise affect accelerometer readings. Signal processing pipeline must handle this.
- **False positives**: Intentional screen adjustments look like posture drift. 90-second sustained drift + monotonic-increase filter mitigates this.

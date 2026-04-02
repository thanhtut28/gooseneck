# Typing Intensity Baseline Redesign

## Context

The current typing intensity system calibrates from only the first 120 seconds of each session, uses a rigid 80/20 cross-session blend with no staleness decay, stores a point-in-time snapshot as "session average," and leaks stale data into the rolling window after breaks. For normal desk usage (open app, work, break, resume), the numbers shown in the first few minutes of any transition are unreliable — and the user has no way to know.

This redesign fixes the baseline to use full-session data, adds time-decay to cross-session persistence, cleans up break transitions, and makes the history metric honest.

## Goals

- Typing intensity is primarily a **real-time awareness tool** (how am I typing right now vs my normal), with fatigue alerts as a secondary benefit
- Correct for normal usage: sit at desk, open app, work, break, continue or start new session
- Cross-session baseline that adapts over time without staleness
- User can understand what the system is doing at every point

## Design

### 1. Baseline Calculation

**Session baseline** = incremental running mean of ALL typing RMS samples in the current session (not capped).

```
sessionSampleCount += 1
sessionBaselineMean += (typingRMS - sessionBaselineMean) / sessionSampleCount
```

O(1) memory, no array needed. Naturally stabilizes the longer you work.

**Blended baseline** (what intensity is measured against):

```
weight = max(0.3, 1.0 - (sessionSampleCount / 600.0) * 0.7)
baseline = persistedBaseline * weight + sessionBaselineMean * (1 - weight)
```

| Session time | Persisted weight | Session weight |
|---|---|---|
| 0 samples (start) | 100% | 0% |
| 300 samples (5 min) | 65% | 35% |
| 600 samples (10 min) | 30% | 70% |
| 600+ samples | 30% | 70% |

First-ever session (no persisted baseline): uses session mean alone once bootstrapped (60 samples).

### 2. Cross-Session Persistence

**Persisted at session end** (in UserDefaults):
- `baselineRMS` — final blended baseline
- `totalLifetimeSamples` — cumulative sample count
- `lastUpdatedAt` — timestamp

**Restored at session start** with time-decay:

```
daysSince = (now - lastUpdatedAt) / 86400
decayedWeight = max(0.3, 0.8 - 0.1 * daysSince)
```

| Days since last session | Initial persisted weight |
|---|---|
| 0 (same day) | 0.8 |
| 1 day | 0.7 |
| 3 days | 0.5 |
| 5+ days | 0.3 |

This `decayedWeight` replaces the starting weight of 1.0 in the blended baseline formula from Section 1. The combined formula becomes:

```
startWeight = decayedWeight   // (or 1.0 if no persisted baseline / first-ever session)
weight = max(0.3, startWeight - (sessionSampleCount / 600.0) * (startWeight - 0.3))
baseline = persistedBaseline * weight + sessionBaselineMean * (1 - weight)
```

So if you return after 5 days (`decayedWeight = 0.3`), the system starts at 30% persisted and stays there — fresh session data dominates immediately. If you return same-day (`decayedWeight = 0.8`), it starts at 80% persisted and gradually shifts to 30/70 over 10 minutes.

### 3. Intensity Calculation

```
intensity = (recentAvg - baseline) / baseline * 100
```

**Recent window**: 2-minute rolling window (120 samples at 1 Hz). Shorter than current 5-minute — more responsive for real-time awareness.

**Intensity history** (for sparkline): stores last 5 minutes of intensity values (300 entries), same as current.

**Peak tracking**: `peakIntensityPercent = max(peak, currentIntensity)` per session, same as current.

### 4. Break Handling

**Short break (within same session)**:
- While idle (`isActive == false`): `update()` early-returns, sets `currentIntensityPercent = 0`. No samples added to anything.
- On return: **clear the 2-min recent window** (`recentSamples`). Baseline and session mean are preserved. Intensity numbers are clean from the first typing sample after return.

**New session (long break / app restart)**:
- `resetSession()` clears all session state
- Persisted baseline restored with time-decay
- If persisted baseline exists: `calibrationState = .ready` immediately
- If no persisted baseline: `calibrationState = .bootstrapping`, 60-sample wait

**Break detection for clearing recent window**: track `wasActive` state. When `isActive` transitions from `false` to `true`, clear `recentSamples`.

### 5. Session History Fix

Replace the current point-in-time snapshot with a true session average:

```swift
// New fields in FatigueMonitor
private var sessionIntensitySum: Double = 0
private var sessionIntensitySampleCount: Int = 0

// Updated in update() after intensity calculation:
sessionIntensitySum += max(0, currentIntensityPercent)
sessionIntensitySampleCount += 1

// New computed property:
var sessionAverageIntensity: Double {
    guard sessionIntensitySampleCount > 0 else { return 0 }
    return sessionIntensitySum / Double(sessionIntensitySampleCount)
}
```

`SessionRecord.avgTypingIntensity` saves `sessionAverageIntensity` instead of `currentIntensityPercent`.

### 6. Cold Start UX

| State | Condition | UI |
|---|---|---|
| `unavailable` | No sensor data | Card hidden or "Sensor unavailable" |
| `bootstrapping` | First-ever session, < 60 samples | "Learning your rhythm..." + circular progress (sampleCount / 60) |
| `ready` | Baseline exists (persisted or bootstrapped) | Normal intensity display |

Returning users (persisted baseline exists) skip bootstrapping entirely — `ready` from the first second.

### 7. Fatigue Detection

No logic changes. Same sustained-threshold approach:
- Threshold: user-configurable, default 30%
- Must sustain above threshold for 5 continuous minutes
- One notification per episode
- Resets when intensity drops below threshold

The improvement is purely that the baseline is now more accurate, reducing false positives.

## Files to Modify

- `PostureDesk/Services/FatigueMonitor.swift` — all baseline, intensity, and persistence logic
- `PostureDesk/ViewModels/PostureViewModel.swift` — use `sessionAverageIntensity` for session recording
- `PostureDesk/Views/Dashboard/TypingIntensityCard.swift` — bootstrapping progress UI

## What Does NOT Change

- `SignalProcessor.swift` / `BandpassFilter.swift` / `FFTAnalyzer.swift` — signal pipeline untouched
- `SensorSnapshot` / `SensorTypes.swift` — data model untouched
- `BreakTracker` — session boundary detection untouched
- `NotificationManager` — notification delivery untouched
- `SessionRecord` model fields — same fields, just more accurate values
- Fatigue threshold logic — same rules, better baseline

## Verification

1. **First launch**: Open app with no prior data. Card shows "Learning your rhythm..." for ~60s, then switches to percentage display.
2. **Normal session**: Work for 10+ minutes. Intensity should hover near 0% during steady typing and spike when typing harder. Baseline should be stable.
3. **Short break**: Stop typing for 1-2 minutes (within same session). Resume. Intensity should show clean numbers immediately — no stale pre-break data.
4. **New session**: Quit and reopen app. Should be `ready` immediately with persisted baseline. Numbers should be reasonable from second 1.
5. **Staleness**: After 5+ days away, baseline should heavily weight fresh session data (only 30% persisted).
6. **History**: Session records should show a true average, not a point-in-time snapshot.

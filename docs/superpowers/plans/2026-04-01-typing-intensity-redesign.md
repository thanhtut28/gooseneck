# Typing Intensity Baseline Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the capped 120-sample baseline with a full-session running mean, add cross-session time-decay, fix break transitions, and make session history honest.

**Architecture:** All changes are in `FatigueMonitor` (baseline/intensity engine), `PostureViewModel` (session recording), and `TypingIntensityCard` (bootstrap UI). Signal pipeline, data models, and break tracking are untouched.

**Tech Stack:** Swift 5.10, SwiftUI, `@Observable`, UserDefaults, XCTest

**Spec:** `docs/superpowers/specs/2026-04-01-typing-intensity-redesign.md`

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `PostureDesk/Services/FatigueMonitor.swift` | Rewrite | Baseline calc, intensity, persistence, break handling |
| `PostureDesk/ViewModels/PostureViewModel.swift` | Modify (lines 395-397) | Use `sessionAverageIntensity` for session recording |
| `PostureDesk/Views/Dashboard/TypingIntensityCard.swift` | Modify (lines 78-86) | Bootstrap progress ring UI |
| `PostureDeskTests/FormattingAndFatigueTests.swift` | Rewrite fatigue tests | Unit tests for new FatigueMonitor |

---

### Task 1: Write FatigueMonitor Tests

**Files:**
- Modify: `PostureDeskTests/FormattingAndFatigueTests.swift`

- [ ] **Step 1: Write test for first-ever session bootstrap (60 samples)**

Add this test to `FormattingAndFatigueTests.swift` after the existing `testFatigueMonitorRejectsInfinitePersistedBaseline`:

```swift
func testBootstrapRequires60Samples() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "typingBaselineRMS")
    defaults.removeObject(forKey: "typingBaselineSampleCount")
    defaults.removeObject(forKey: "typingBaselineUpdatedAt")

    let monitor = FatigueMonitor()

    // Feed 59 samples — should still be bootstrapping
    for _ in 0..<59 {
        monitor.update(typingRMS: 0.001, isActive: true)
    }
    XCTAssertEqual(monitor.calibrationState, .bootstrapping)
    XCTAssertEqual(monitor.baselineRMS, 0)

    // 60th sample tips it to ready
    monitor.update(typingRMS: 0.001, isActive: true)
    XCTAssertEqual(monitor.calibrationState, .ready)
    XCTAssertGreaterThan(monitor.baselineRMS, 0)
}
```

- [ ] **Step 2: Write test for session baseline using ALL samples (not capped at 120)**

```swift
func testSessionBaselineUsesAllSamples() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "typingBaselineRMS")
    defaults.removeObject(forKey: "typingBaselineSampleCount")
    defaults.removeObject(forKey: "typingBaselineUpdatedAt")

    let monitor = FatigueMonitor()

    // Bootstrap with 60 samples at 0.001
    for _ in 0..<60 {
        monitor.update(typingRMS: 0.001, isActive: true)
    }
    let baselineAfter60 = monitor.baselineRMS

    // Feed 200 more samples at 0.002 — baseline should shift
    for _ in 0..<200 {
        monitor.update(typingRMS: 0.002, isActive: true)
    }
    let baselineAfter260 = monitor.baselineRMS

    // Baseline should have moved toward 0.002 (not stuck at 0.001)
    XCTAssertGreaterThan(baselineAfter260, baselineAfter60)
}
```

- [ ] **Step 3: Write test for cross-session persistence with time-decay**

```swift
func testCrossSessionTimeDecay() {
    let defaults = UserDefaults.standard

    // Simulate a persisted baseline from 5 days ago
    defaults.set(0.001, forKey: "typingBaselineRMS")
    defaults.set(300, forKey: "typingBaselineSampleCount")
    defaults.set(Date().timeIntervalSinceReferenceDate - (5 * 86400), forKey: "typingBaselineUpdatedAt")

    let monitor = FatigueMonitor()

    // Should be ready immediately (persisted baseline exists)
    XCTAssertEqual(monitor.calibrationState, .ready)
    XCTAssertGreaterThan(monitor.baselineRMS, 0)

    // Feed 600 samples at 0.003 (very different from persisted 0.001)
    for _ in 0..<600 {
        monitor.update(typingRMS: 0.003, isActive: true)
    }

    // After 5 days decay + 600 session samples, baseline should be close to 0.003
    // (decayedWeight = max(0.3, 0.8 - 0.1*5) = 0.3, session weight at 600 samples = 0.7)
    // effective persisted weight = 0.3 * 0.3 = 0.09
    XCTAssertGreaterThan(monitor.baselineRMS, 0.0025,
        "After 5 days decay + 10 min session, baseline should be dominated by session data")
}
```

- [ ] **Step 4: Write test for break return clears recent window**

```swift
func testBreakReturnClearsRecentWindow() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "typingBaselineRMS")
    defaults.removeObject(forKey: "typingBaselineSampleCount")
    defaults.removeObject(forKey: "typingBaselineUpdatedAt")

    let monitor = FatigueMonitor()

    // Bootstrap
    for _ in 0..<60 {
        monitor.update(typingRMS: 0.001, isActive: true)
    }

    // Type at elevated intensity to build up recent window
    for _ in 0..<120 {
        monitor.update(typingRMS: 0.005, isActive: true)
    }
    let intensityBeforeBreak = monitor.currentIntensityPercent
    XCTAssertGreaterThan(intensityBeforeBreak, 0)

    // Go idle
    monitor.update(typingRMS: 0.0, isActive: false)
    XCTAssertEqual(monitor.currentIntensityPercent, 0)

    // Return — first sample should not carry stale window data
    monitor.update(typingRMS: 0.001, isActive: true)

    // Intensity should be based only on the single new sample vs baseline,
    // not mixed with pre-break elevated data
    XCTAssertLessThan(monitor.currentIntensityPercent, intensityBeforeBreak)
}
```

- [ ] **Step 5: Write test for session average intensity (not point-in-time)**

```swift
func testSessionAverageIntensity() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "typingBaselineRMS")
    defaults.removeObject(forKey: "typingBaselineSampleCount")
    defaults.removeObject(forKey: "typingBaselineUpdatedAt")

    let monitor = FatigueMonitor()

    // Bootstrap with 60 samples
    for _ in 0..<60 {
        monitor.update(typingRMS: 0.001, isActive: true)
    }

    // Type 60 samples at moderate intensity
    for _ in 0..<60 {
        monitor.update(typingRMS: 0.002, isActive: true)
    }

    // sessionAverageIntensity should be a stable average, not a snapshot
    let avg = monitor.sessionAverageIntensity
    XCTAssertGreaterThan(avg, 0)

    // Type 60 more at baseline level
    for _ in 0..<60 {
        monitor.update(typingRMS: 0.001, isActive: true)
    }

    // Average should have decreased (diluted by normal typing)
    XCTAssertLessThan(monitor.sessionAverageIntensity, avg)
}
```

- [ ] **Step 6: Write test for bootstrap progress reporting**

```swift
func testBootstrapProgress() {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: "typingBaselineRMS")
    defaults.removeObject(forKey: "typingBaselineSampleCount")
    defaults.removeObject(forKey: "typingBaselineUpdatedAt")

    let monitor = FatigueMonitor()

    XCTAssertEqual(monitor.bootstrapProgress, 0)

    for i in 1...30 {
        monitor.update(typingRMS: 0.001, isActive: true)
        XCTAssertEqual(monitor.bootstrapProgress, Double(i) / 60.0, accuracy: 0.01)
    }

    // After bootstrap complete, progress should be 1.0
    for _ in 31...60 {
        monitor.update(typingRMS: 0.001, isActive: true)
    }
    XCTAssertEqual(monitor.bootstrapProgress, 1.0)
}
```

- [ ] **Step 7: Run tests to verify they fail**

Run: `xcodebuild test -project PostureDesk.xcodeproj -scheme PostureDesk -destination 'platform=macOS' -only-testing:PostureDeskTests/FormattingAndFatigueTests 2>&1 | tail -30`

Expected: Compilation errors — `sessionAverageIntensity` and `bootstrapProgress` don't exist yet.

- [ ] **Step 8: Commit**

```bash
git add PostureDeskTests/FormattingAndFatigueTests.swift
git commit -m "test: add failing tests for typing intensity baseline redesign"
```

---

### Task 2: Rewrite FatigueMonitor

**Files:**
- Modify: `PostureDesk/Services/FatigueMonitor.swift` (full rewrite of internals)

- [ ] **Step 1: Replace state properties and constants**

Replace the internal state section (lines 29-48) with:

```swift
    // Internal state — baseline
    private var sessionSampleCount: Int = 0
    private var sessionBaselineMean: Double = 0
    private var persistedBaseline: Double = 0
    private var persistedBaselineWeight: Double = 0  // after time-decay

    // Internal state — recent window
    private var recentSamples: [Double] = []
    private let recentWindowSize = 120                        // 2 minutes at 1Hz

    // Internal state — fatigue
    private var fatigueStartTime: Date?
    private let fatigueSustainedDuration: TimeInterval = 5 * 60
    private var hasSentNotificationForCurrentEpisode = false

    // Internal state — session average tracking
    private var sessionIntensitySum: Double = 0
    private var sessionIntensitySampleCount: Int = 0

    // Internal state — break detection
    private var wasActive = false

    // Constants
    private let minimumTypingRMS = 0.0001
    private let bootstrapMinimumSamples = 60
    private let baselineTransitionSamples: Double = 600      // 10 min to full session weight
    private let minimumPersistedWeight: Double = 0.3

    // UserDefaults keys
    private let baselineRMSDefaultsKey = "typingBaselineRMS"
    private let baselineSampleCountDefaultsKey = "typingBaselineSampleCount"
    private let baselineUpdatedAtDefaultsKey = "typingBaselineUpdatedAt"
    private static let fatigueThresholdDefaultsKey = "fatigueThresholdPercent"
```

- [ ] **Step 2: Add new public properties**

Add after the existing `calibrationState` property (line 19), before `hasSessionTypingMetrics`:

```swift
    private(set) var bootstrapProgress: Double = 0  // 0.0–1.0 during bootstrapping
```

Add a new computed property after `hasSessionTypingMetrics`:

```swift
    /// True session average intensity (not a point-in-time snapshot).
    var sessionAverageIntensity: Double {
        guard sessionIntensitySampleCount > 0 else { return 0 }
        return sessionIntensitySum / Double(sessionIntensitySampleCount)
    }
```

- [ ] **Step 3: Rewrite the `update()` method**

Replace the entire `update(typingRMS:isActive:)` method (lines 56-110) with:

```swift
    func update(typingRMS: Double, isActive: Bool) {
        // Break return detection: clear recent window when user comes back
        if isActive && !wasActive {
            recentSamples.removeAll()
        }
        wasActive = isActive

        guard isActive, typingRMS > minimumTypingRMS else {
            currentIntensityPercent = 0
            fatigueStartTime = nil
            isFatigued = false
            hasSentNotificationForCurrentEpisode = false
            return
        }

        // Accumulate into session baseline (incremental mean, never capped)
        sessionSampleCount += 1
        sessionBaselineMean += (typingRMS - sessionBaselineMean) / Double(sessionSampleCount)

        // Update bootstrap progress
        if calibrationState == .bootstrapping {
            bootstrapProgress = min(1.0, Double(sessionSampleCount) / Double(bootstrapMinimumSamples))
        }

        // Bootstrap: need minimum samples before we have a baseline
        if baselineRMS <= 0 {
            calibrationState = .bootstrapping
            guard sessionSampleCount >= bootstrapMinimumSamples else { return }
            baselineRMS = sessionBaselineMean
            calibrationState = .ready
            bootstrapProgress = 1.0
        }

        guard calibrationState == .ready else { return }

        // Compute blended baseline: persisted weight decays as session grows
        let startWeight = persistedBaseline > 0 ? persistedBaselineWeight : 0
        let weight = max(minimumPersistedWeight,
                         startWeight - (Double(sessionSampleCount) / baselineTransitionSamples) * (startWeight - minimumPersistedWeight))
        if persistedBaseline > 0 {
            baselineRMS = persistedBaseline * weight + sessionBaselineMean * (1 - weight)
        } else {
            baselineRMS = sessionBaselineMean
        }

        // Recent window for intensity calculation (2 min)
        recentSamples.append(typingRMS)
        if recentSamples.count > recentWindowSize {
            recentSamples.removeFirst(recentSamples.count - recentWindowSize)
        }

        let recentAvg = recentSamples.reduce(0, +) / Double(recentSamples.count)
        currentIntensityPercent = ((recentAvg - baselineRMS) / baselineRMS) * 100.0
        peakIntensityPercent = max(peakIntensityPercent, currentIntensityPercent)
        hasSessionTypingMetrics = true

        // Track session average
        sessionIntensitySum += max(0, currentIntensityPercent)
        sessionIntensitySampleCount += 1

        // Intensity history for sparkline (5 min)
        intensityHistory.append(max(0, currentIntensityPercent))
        if intensityHistory.count > 300 {
            intensityHistory.removeFirst(intensityHistory.count - 300)
        }

        // Sustained fatigue detection
        checkFatigue()
    }
```

- [ ] **Step 4: Extract fatigue check and rewrite persistence methods**

Replace `collectCalibrationSample` (lines 127-157), `restorePersistedBaseline` (lines 159-174), `persistBaseline` (lines 176-182), and `mean` (lines 184-187) with:

```swift
    private func checkFatigue() {
        let now = Date()
        if currentIntensityPercent > fatigueThresholdPercent {
            if fatigueStartTime == nil {
                fatigueStartTime = now
            }
            if let start = fatigueStartTime,
               now.timeIntervalSince(start) >= fatigueSustainedDuration {
                isFatigued = true
                if !hasSentNotificationForCurrentEpisode {
                    NotificationManager.shared.send(
                        category: NotificationCategory.fatigue.rawValue,
                        title: "PostureDesk",
                        body: String(format: "Your typing intensity is up %.0f%% from your session baseline. Your hands might need a rest.", currentIntensityPercent)
                    )
                    hasSentNotificationForCurrentEpisode = true
                }
            }
        } else {
            fatigueStartTime = nil
            isFatigued = false
            hasSentNotificationForCurrentEpisode = false
        }
    }

    private func restorePersistedBaseline() {
        let defaults = UserDefaults.standard
        let storedBaseline = defaults.double(forKey: baselineRMSDefaultsKey)
        let storedSampleCount = defaults.integer(forKey: baselineSampleCountDefaultsKey)
        let storedUpdatedAt = defaults.double(forKey: baselineUpdatedAtDefaultsKey)

        guard storedBaseline.isFinite, storedBaseline > 0, storedSampleCount > 0 else {
            baselineRMS = 0
            persistedBaseline = 0
            persistedBaselineWeight = 0
            calibrationState = .unavailable
            return
        }

        // Apply time-decay
        let daysSince = (Date.timeIntervalSinceReferenceDate - storedUpdatedAt) / 86400
        let decayedWeight = max(0.3, 0.8 - 0.1 * daysSince)

        persistedBaseline = storedBaseline
        persistedBaselineWeight = decayedWeight
        baselineRMS = storedBaseline
        calibrationState = .ready
    }

    /// Persist current baseline to UserDefaults. Call at session end.
    func persistCurrentBaseline() {
        guard baselineRMS > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(baselineRMS, forKey: baselineRMSDefaultsKey)
        defaults.set(sessionSampleCount, forKey: baselineSampleCountDefaultsKey)
        defaults.set(Date.timeIntervalSinceReferenceDate, forKey: baselineUpdatedAtDefaultsKey)
    }
```

- [ ] **Step 5: Rewrite `resetSession()`**

Replace the existing `resetSession()` method (lines 113-125) with:

```swift
    func resetSession() {
        // Persist baseline before clearing
        persistCurrentBaseline()

        sessionSampleCount = 0
        sessionBaselineMean = 0
        recentSamples.removeAll()
        intensityHistory.removeAll()
        currentIntensityPercent = 0
        peakIntensityPercent = 0
        isFatigued = false
        fatigueStartTime = nil
        hasSentNotificationForCurrentEpisode = false
        hasSessionTypingMetrics = false
        sessionIntensitySum = 0
        sessionIntensitySampleCount = 0
        wasActive = false
        bootstrapProgress = 0

        restorePersistedBaseline()
    }
```

- [ ] **Step 6: Remove the `loadFatigueThresholdPercent` static method — keep it unchanged**

No change needed — the static method at lines 189-192 stays as-is.

- [ ] **Step 7: Run tests**

Run: `xcodebuild test -project PostureDesk.xcodeproj -scheme PostureDesk -destination 'platform=macOS' -only-testing:PostureDeskTests/FormattingAndFatigueTests 2>&1 | tail -30`

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add PostureDesk/Services/FatigueMonitor.swift
git commit -m "feat: rewrite FatigueMonitor with full-session baseline and time-decay"
```

---

### Task 3: Update PostureViewModel Session Recording

**Files:**
- Modify: `PostureDesk/ViewModels/PostureViewModel.swift` (lines 389-399, 401-432, 434-436)

- [ ] **Step 1: Update `updateCurrentSession()` to use `sessionAverageIntensity`**

In `PostureViewModel.swift`, replace lines 396-397:

```swift
        session.avgTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? persistedCurrentTypingIntensity : 0
        session.peakTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? fatigueMonitor.peakIntensityPercent : 0
```

with:

```swift
        session.avgTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.sessionAverageIntensity) : 0
        session.peakTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.peakIntensityPercent) : 0
```

- [ ] **Step 2: Update `finalizeCurrentSession()` the same way**

Replace lines 423-425:

```swift
        session.typingIntensityAvailable = fatigueMonitor.hasSessionTypingMetrics
        session.avgTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? persistedCurrentTypingIntensity : 0
        session.peakTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? fatigueMonitor.peakIntensityPercent : 0
```

with:

```swift
        session.typingIntensityAvailable = fatigueMonitor.hasSessionTypingMetrics
        session.avgTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.sessionAverageIntensity) : 0
        session.peakTypingIntensity = fatigueMonitor.hasSessionTypingMetrics ? max(0, fatigueMonitor.peakIntensityPercent) : 0
```

- [ ] **Step 3: Add `persistCurrentBaseline()` call to `finalizeCurrentSession()`**

Add this line right before `currentSession = nil` at the end of `finalizeCurrentSession()`:

```swift
        fatigueMonitor.persistCurrentBaseline()
```

- [ ] **Step 4: Remove the `persistedCurrentTypingIntensity` computed property**

Delete lines 434-436:

```swift
    private var persistedCurrentTypingIntensity: Double {
        max(0, fatigueMonitor.currentIntensityPercent)
    }
```

- [ ] **Step 5: Build to verify compilation**

Run: `xcodebuild build -project PostureDesk.xcodeproj -scheme PostureDesk -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

- [ ] **Step 6: Run all tests**

Run: `xcodebuild test -project PostureDesk.xcodeproj -scheme PostureDesk -destination 'platform=macOS' 2>&1 | tail -30`

Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add PostureDesk/ViewModels/PostureViewModel.swift
git commit -m "feat: use session average intensity for history and persist baseline at session end"
```

---

### Task 4: Update TypingIntensityCard Bootstrap UI

**Files:**
- Modify: `PostureDesk/Views/Dashboard/TypingIntensityCard.swift` (lines 78-86)

- [ ] **Step 1: Add `bootstrapProgress` accessor**

Add after line 10 (`private var history: [Double] { ... }`):

```swift
    private var bootstrapProgress: Double { viewModel.fatigueMonitor.bootstrapProgress }
```

- [ ] **Step 2: Replace the bootstrapping UI block**

Replace lines 78-86 (the `else` branch for `!hasBaseline`):

```swift
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(qualitativeLabel)
                                .font(DS.Font.metric(24))
                                .foregroundStyle(qualitativeColor)
                            Text("building typing baseline...")
                                .font(DS.Font.caption())
                                .foregroundStyle(DS.Colors.textMuted.opacity(0.7))
                        }
                    }
```

with:

```swift
                    } else {
                        HStack(spacing: 12) {
                            // Circular progress ring
                            ZStack {
                                Circle()
                                    .stroke(DS.Colors.bg, lineWidth: 3)
                                    .frame(width: 32, height: 32)
                                Circle()
                                    .trim(from: 0, to: bootstrapProgress)
                                    .stroke(DS.Colors.accentGood, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .frame(width: 32, height: 32)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.easeInOut(duration: 0.3), value: bootstrapProgress)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Learning your rhythm...")
                                    .font(DS.Font.metric(18))
                                    .foregroundStyle(DS.Colors.textSecondary)
                                Text("\(Int(bootstrapProgress * 60))s / 60s")
                                    .font(DS.Font.caption())
                                    .foregroundStyle(DS.Colors.textMuted.opacity(0.7))
                            }
                        }
                    }
```

- [ ] **Step 3: Update the `qualitativeLabel` for bootstrapping state**

Replace line 19:

```swift
        if !hasBaseline { return "calibrating" }
```

with:

```swift
        if !hasBaseline { return "learning" }
```

- [ ] **Step 4: Build to verify compilation**

Run: `xcodebuild build -project PostureDesk.xcodeproj -scheme PostureDesk -destination 'platform=macOS' 2>&1 | tail -10`

Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add PostureDesk/Views/Dashboard/TypingIntensityCard.swift
git commit -m "feat: show 'Learning your rhythm...' with progress ring during bootstrap"
```

---

### Task 5: Run Full Test Suite and Manual Verification

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild test -project PostureDesk.xcodeproj -scheme PostureDesk -destination 'platform=macOS' 2>&1 | tail -40`

Expected: All tests pass.

- [ ] **Step 2: Build and launch app**

Run: `make run`

Expected: App launches, menu bar icon appears.

- [ ] **Step 3: Verify bootstrap UX**

Clear persisted baseline and relaunch:
```bash
defaults delete com.posturedesk.app typingBaselineRMS 2>/dev/null
defaults delete com.posturedesk.app typingBaselineSampleCount 2>/dev/null
defaults delete com.posturedesk.app typingBaselineUpdatedAt 2>/dev/null
```

Open dashboard. Typing intensity card should show "Learning your rhythm..." with a progress ring filling over ~60 seconds. After 60s, switches to percentage display.

- [ ] **Step 4: Verify normal session**

Type normally for 2+ minutes. Intensity should hover near 0%. Type harder — intensity should spike. Check that the sparkline appears after data accumulates.

- [ ] **Step 5: Verify break return**

Stop typing for ~30 seconds. Resume. Intensity numbers should be clean — no stale pre-break data mixing in.

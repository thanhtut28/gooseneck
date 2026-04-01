import XCTest
@testable import PostureDesk

final class FormattingAndFatigueTests: XCTestCase {
    private let baselineKey = "typingBaselineRMS"
    private let sampleCountKey = "typingBaselineSampleCount"

    override func tearDown() {
        super.tearDown()
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: baselineKey)
        defaults.removeObject(forKey: sampleCountKey)
        defaults.removeObject(forKey: "typingBaselineUpdatedAt")
    }

    func testActiveDurationShowsLessThanOneMinute() {
        XCTAssertEqual(DisplayFormatter.activeDuration(seconds: 30), "< 1m")
        XCTAssertEqual(DisplayFormatter.activeDuration(seconds: 0), "0m")
        XCTAssertEqual(DisplayFormatter.activeDuration(seconds: 3720), "1h 2m")
    }

    func testBreakCountdownShowsLessThanOneMinuteAndBreakTime() {
        XCTAssertEqual(DisplayFormatter.breakCountdown(elapsedSeconds: 50, intervalMinutes: 1), "< 1 min")
        XCTAssertEqual(DisplayFormatter.breakCountdown(elapsedSeconds: 60, intervalMinutes: 1), "break time")
        XCTAssertEqual(DisplayFormatter.shortBreakCountdown(elapsedSeconds: 50, intervalMinutes: 1), "< 1 min")
    }

    func testFatigueMonitorRejectsInfinitePersistedBaseline() {
        let defaults = UserDefaults.standard
        defaults.set(Double.infinity, forKey: baselineKey)
        defaults.set(120, forKey: sampleCountKey)

        let monitor = FatigueMonitor()

        XCTAssertEqual(monitor.baselineRMS, 0)
        XCTAssertEqual(monitor.calibrationState, .unavailable)
    }

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
        // decayedWeight = max(0.3, 0.8 - 0.5) = 0.3
        // weight = max(0.3, 0.3 - 1.0 * (0.3 - 0.3)) = 0.3
        // baseline = 0.001 * 0.3 + ~0.003 * 0.7 ≈ 0.0024
        XCTAssertGreaterThan(monitor.baselineRMS, 0.002,
            "After 5 days decay + 10 min session, baseline should be dominated by session data")
    }

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
}

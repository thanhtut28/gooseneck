import XCTest
@testable import PostureDesk

final class PostureAnalyzerAndSettingsTests: XCTestCase {
    private let breakIntervalKey = "breakIntervalMinutes"
    private let breakReminderCadenceKey = "breakReminderCadence"
    private let fatigueThresholdKey = "fatigueThresholdPercent"

    override func tearDown() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: breakIntervalKey)
        defaults.removeObject(forKey: breakReminderCadenceKey)
        defaults.removeObject(forKey: fatigueThresholdKey)
        super.tearDown()
    }

    func testPostureAnalyzerSendsOneNotificationPerDriftEpisode() {
        var notificationCount = 0
        let analyzer = PostureAnalyzer { _ in
            notificationCount += 1
        }
        analyzer.driftThreshold = 10
        analyzer.calibrate(pitch: 0, lidAngle: 0)

        for drift in 12...21 {
            analyzer.update(pitch: Double(drift), lidAngle: 0)
        }

        XCTAssertTrue(analyzer.isDrifting)
        XCTAssertEqual(notificationCount, 1)

        for _ in 0..<5 {
            analyzer.update(pitch: 22, lidAngle: 0)
        }

        XCTAssertEqual(notificationCount, 1)

        analyzer.update(pitch: 0, lidAngle: 0)
        XCTAssertFalse(analyzer.isDrifting)

        for drift in 25...36 {
            analyzer.update(pitch: Double(drift), lidAngle: 0)
        }

        XCTAssertTrue(analyzer.isDrifting)
        XCTAssertEqual(notificationCount, 2)
    }

    func testBreakTrackerPersistsIntervalAndCadence() {
        let tracker = BreakTracker()
        tracker.breakIntervalMinutes = 15
        tracker.breakReminderCadence = .every10Minutes

        let reloadedTracker = BreakTracker()

        XCTAssertEqual(reloadedTracker.breakIntervalMinutes, 15)
        XCTAssertEqual(reloadedTracker.breakReminderCadence, .every10Minutes)
    }

    func testBreakTrackerStopResetsRuntimeState() {
        let tracker = BreakTracker()
        _ = tracker.update(isActive: true, at: Date())
        tracker.recordBreak()

        tracker.stop()

        XCTAssertEqual(tracker.state, .away)
        XCTAssertNil(tracker.sessionStartTime)
        XCTAssertEqual(tracker.totalActiveSeconds, 0)
        XCTAssertEqual(tracker.secondsSinceLastBreak, 0)
        XCTAssertEqual(tracker.breaksTaken, 0)
        XCTAssertFalse(tracker.isBreakOverdue)
    }

    func testFatigueMonitorPersistsThreshold() {
        let monitor = FatigueMonitor()
        monitor.fatigueThresholdPercent = 45

        let reloadedMonitor = FatigueMonitor()

        XCTAssertEqual(reloadedMonitor.fatigueThresholdPercent, 45)
    }
}

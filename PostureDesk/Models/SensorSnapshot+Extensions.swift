import Foundation
import SwiftData

// MARK: - SwiftData Models

@Model
final class SessionRecord {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var surfaceRawValue: Int = Surface.unknown.rawValue
    var totalActiveMinutes: Int = 0
    var postureAlertCount: Int = 0
    var breaksTaken: Int = 0
    var avgTypingIntensity: Double = 0
    var peakTypingIntensity: Double = 0

    var surface: Surface {
        get { Surface(rawValue: surfaceRawValue) ?? .unknown }
        set { surfaceRawValue = newValue.rawValue }
    }

    init() {}
}

@Model
final class CalibrationProfile {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var lidAngleBaseline: Double = 0
    var pitchBaseline: Double = 0
    var rollBaseline: Double = 0
    var isActive: Bool = true

    init(lidAngle: Double, pitch: Double, roll: Double) {
        self.lidAngleBaseline = lidAngle
        self.pitchBaseline = pitch
        self.rollBaseline = roll
    }
}

@Model
final class UserSettings {
    var breakIntervalMinutes: Int = 45
    var postureDriftThreshold: Double = 10.0
    var fatigueThresholdPercent: Double = 30.0
    var notificationsEnabled: Bool = true
    var launchAtLogin: Bool = false

    init() {}
}

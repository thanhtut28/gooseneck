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
    var typingIntensityAvailable: Bool = false
    var avgTypingIntensity: Double = 0
    var peakTypingIntensity: Double = 0

    var surface: Surface {
        get { Surface(rawValue: surfaceRawValue) ?? .unknown }
        set { surfaceRawValue = newValue.rawValue }
    }

    init() {}
}

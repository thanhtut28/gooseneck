import Foundation
import SwiftData

// MARK: - Surface Change Event

struct SurfaceChangeEvent: Codable {
    let timestamp: Date
    let surfaceRawValue: Int

    var surface: Surface { Surface(rawValue: surfaceRawValue) ?? .unknown }
}

// MARK: - SwiftData Models

@Model
final class SessionRecord {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    var surfaceRawValue: Int = Surface.unknown.rawValue
    var surfaceChangesData: Data = Data()
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

extension SessionRecord {
    var surfaceChanges: [SurfaceChangeEvent] {
        get {
            guard !surfaceChangesData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([SurfaceChangeEvent].self, from: surfaceChangesData)) ?? []
        }
        set {
            surfaceChangesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    func recordSurfaceChange(to surface: Surface, at time: Date = Date()) {
        var changes = surfaceChanges
        changes.append(SurfaceChangeEvent(timestamp: time, surfaceRawValue: surface.rawValue))
        surfaceChanges = changes
    }

    /// e.g. "Desk" or "Desk → Lap"
    var surfaceLabel: String {
        let changes = surfaceChanges
        guard !changes.isEmpty else { return surface.label }

        var sequence: [Surface] = [surface]
        for change in changes {
            if change.surface != sequence.last {
                sequence.append(change.surface)
            }
        }
        return sequence.map(\.label).joined(separator: " → ")
    }
}

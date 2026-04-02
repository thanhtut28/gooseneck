import Foundation

enum IslandVariant: Int, CaseIterable, Identifiable {
    case lidAngle = 0
    case tiltAngle = 1
    case sessionTime = 2
    case typingIntensity = 3

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .lidAngle: "Screen Angle"
        case .tiltAngle: "Tilt Angle"
        case .sessionTime: "Session Timer"
        case .typingIntensity: "Typing Pulse"
        }
    }

    /// Short label shown in the minimal bar preview.
    var previewMinimalValue: String {
        switch self {
        case .lidAngle: "+2.1\u{00B0}"
        case .tiltAngle: "-1.3\u{00B0}"
        case .sessionTime: "24m"
        case .typingIntensity: "38%"
        }
    }

    /// Labels for the two expanded widget cards.
    var expandedCard1: (label: String, value: String) {
        switch self {
        case .lidAngle: ("Session", "24m")
        case .tiltAngle: ("Session", "24m")
        case .sessionTime: ("Tilt", "-1.3\u{00B0}")
        case .typingIntensity: ("Session", "24m")
        }
    }

    var expandedCard2: (label: String, value: String) {
        switch self {
        case .lidAngle: ("Break", "in 21m")
        case .tiltAngle: ("Break", "in 21m")
        case .sessionTime: ("Screen", "+2.1\u{00B0}")
        case .typingIntensity: ("Tilt", "-1.3\u{00B0}")
        }
    }
}

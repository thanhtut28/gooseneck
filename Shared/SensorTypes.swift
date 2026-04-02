import Foundation

// MARK: - Surface Type

@objc public enum Surface: Int, Codable {
    case desk = 0
    case lap = 1
    case couch = 2
    case unknown = 3

    public var label: String {
        switch self {
        case .desk: return "Desk"
        case .lap: return "Lap"
        case .couch: return "Couch"
        case .unknown: return "Unknown"
        }
    }

    /// Posture drift threshold in degrees for this surface type
    public var driftThreshold: Double {
        switch self {
        case .desk: return 10.0
        case .lap: return 15.0
        case .couch: return 20.0
        case .unknown: return 10.0
        }
    }
}

// MARK: - Sensor Snapshot

@objc public class SensorSnapshot: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public var pitch: Double       // Device pitch in degrees
    @objc public var roll: Double        // Device roll in degrees
    @objc public var lidAngle: Double    // Lid angle in degrees (-1 if unavailable)
    @objc public var typingRMS: Double   // Typing intensity (RMS of bandpass-filtered accel)
    @objc public var vibrationVariance: Double  // Gravity vector variance (for surface classification)
    @objc public var isActive: Bool      // Whether user activity is detected
    @objc public var timestamp: Double   // TimeInterval since reference date

    // FFT bin energies for surface classification
    @objc public var fftLowBin: Double   // 0-10Hz energy ratio
    @objc public var fftMidBin: Double   // 10-50Hz energy ratio
    @objc public var fftHighBin: Double  // 50+Hz energy ratio

    public init(
        pitch: Double = 0,
        roll: Double = 0,
        lidAngle: Double = -1,
        typingRMS: Double = 0,
        vibrationVariance: Double = 0,
        isActive: Bool = false,
        timestamp: Double = Date.timeIntervalSinceReferenceDate,
        fftLowBin: Double = 0,
        fftMidBin: Double = 0,
        fftHighBin: Double = 0
    ) {
        self.pitch = pitch
        self.roll = roll
        self.lidAngle = lidAngle
        self.typingRMS = typingRMS
        self.vibrationVariance = vibrationVariance
        self.isActive = isActive
        self.timestamp = timestamp
        self.fftLowBin = fftLowBin
        self.fftMidBin = fftMidBin
        self.fftHighBin = fftHighBin
        super.init()
    }

    public required init?(coder: NSCoder) {
        self.pitch = coder.decodeDouble(forKey: "pitch")
        self.roll = coder.decodeDouble(forKey: "roll")
        self.lidAngle = coder.decodeDouble(forKey: "lidAngle")
        self.typingRMS = coder.decodeDouble(forKey: "typingRMS")
        self.vibrationVariance = coder.decodeDouble(forKey: "vibrationVariance")
        self.isActive = coder.decodeBool(forKey: "isActive")
        self.timestamp = coder.decodeDouble(forKey: "timestamp")
        self.fftLowBin = coder.decodeDouble(forKey: "fftLowBin")
        self.fftMidBin = coder.decodeDouble(forKey: "fftMidBin")
        self.fftHighBin = coder.decodeDouble(forKey: "fftHighBin")
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(pitch, forKey: "pitch")
        coder.encode(roll, forKey: "roll")
        coder.encode(lidAngle, forKey: "lidAngle")
        coder.encode(typingRMS, forKey: "typingRMS")
        coder.encode(vibrationVariance, forKey: "vibrationVariance")
        coder.encode(isActive, forKey: "isActive")
        coder.encode(timestamp, forKey: "timestamp")
        coder.encode(fftLowBin, forKey: "fftLowBin")
        coder.encode(fftMidBin, forKey: "fftMidBin")
        coder.encode(fftHighBin, forKey: "fftHighBin")
    }
}

// MARK: - Sensor Availability

@objc public class SensorAvailability: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    @objc public var hasAccelerometer: Bool
    @objc public var hasGyroscope: Bool
    @objc public var hasLidAngle: Bool

    public init(hasAccelerometer: Bool = false, hasGyroscope: Bool = false, hasLidAngle: Bool = false) {
        self.hasAccelerometer = hasAccelerometer
        self.hasGyroscope = hasGyroscope
        self.hasLidAngle = hasLidAngle
        super.init()
    }

    public required init?(coder: NSCoder) {
        self.hasAccelerometer = coder.decodeBool(forKey: "hasAccelerometer")
        self.hasGyroscope = coder.decodeBool(forKey: "hasGyroscope")
        self.hasLidAngle = coder.decodeBool(forKey: "hasLidAngle")
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(hasAccelerometer, forKey: "hasAccelerometer")
        coder.encode(hasGyroscope, forKey: "hasGyroscope")
        coder.encode(hasLidAngle, forKey: "hasLidAngle")
    }
}

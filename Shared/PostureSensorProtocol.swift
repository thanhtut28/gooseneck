import Foundation

/// XPC protocol for communication between PostureDesk app and PostureSensorDaemon.
/// All parameter types must conform to NSSecureCoding for XPC transport.
@objc public protocol PostureSensorProtocol {
    /// Returns the latest sensor readings as a SensorSnapshot.
    func getSensorSnapshot(withReply reply: @escaping (SensorSnapshot) -> Void)

    /// Records the current sensor readings as the "good posture" baseline.
    func calibrateBaseline(withReply reply: @escaping (Bool) -> Void)

    /// Returns which sensors are available on this hardware.
    func getSensorStatus(withReply reply: @escaping (SensorAvailability) -> Void)
}

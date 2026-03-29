import Foundation

// MARK: - Apple SPU HID Device Constants

/// Matching dictionary values for AppleSPUHIDDevice on Apple Silicon Macs
enum HIDConstants {
    // Device identification
    static let appleVendorID: Int = 0x05AC

    // Accelerometer
    static let accelUsagePage: Int = 0xFF00  // Vendor-defined
    static let accelUsageID: Int = 0x03

    // Gyroscope
    static let gyroUsagePage: Int = 0xFF00
    static let gyroUsageID: Int = 0x09

    // Lid angle sensor
    static let lidAngleUsagePage: Int = 0x0020  // Sensor
    static let lidAngleUsageID: Int = 0x008A    // Orientation

    // Accelerometer report parsing
    static let reportSize: Int = 22
    static let xOffset: Int = 6     // bytes 6-9: int32 LE
    static let yOffset: Int = 10    // bytes 10-13: int32 LE
    static let zOffset: Int = 14    // bytes 14-17: int32 LE
    static let scaleFactor: Double = 65536.0  // raw / scaleFactor = g-force

    // Lid angle
    static let lidAngleReportID: CFIndex = 1
    static let lidAngleReportBufferSize: Int = 64
}

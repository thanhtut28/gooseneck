import CryptoKit
import Foundation
import IOKit

enum DeviceIdentity {
    /// Reads `IOPlatformUUID` from the IORegistry. Stable per-Mac; survives
    /// macOS reinstall; requires NVRAM reset to change. Returns `nil` if the
    /// registry entry can't be read (e.g. running in a sandboxed environment).
    static func platformUUID() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }

        guard let raw = IORegistryEntryCreateCFProperty(
            entry,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }
        return raw
    }

    /// First 8 hex chars of `sha256(platformUUID)`. Suitable for inclusion in
    /// a Polar activation label without exposing the raw hardware ID.
    /// Returns `nil` if the platform UUID is unavailable.
    static func shortHashedUUID() -> String? {
        guard let uuid = platformUUID() else { return nil }
        return shortHash(of: uuid)
    }

    /// Pure helper: returns first 8 hex chars of `sha256(input)`. Exposed
    /// internal for unit testing with deterministic inputs.
    static func shortHash(of input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.compactMap { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(8))
    }
}

import XCTest
@testable import GooseNeck

final class DeviceIdentityTests: XCTestCase {
    func testShortHashedUUIDIsStableEightHexFromKnownInput() {
        // Known SHA-256 of "0000FFFF-0000-1000-8000-00805F9B34FB" — the first
        // 8 hex chars of that digest must be reproducible.
        let hashed = DeviceIdentity.shortHash(of: "0000FFFF-0000-1000-8000-00805F9B34FB")
        XCTAssertEqual(hashed.count, 8)
        XCTAssertTrue(hashed.allSatisfy { $0.isHexDigit })
        // Stability: same input → same output across calls.
        XCTAssertEqual(hashed, DeviceIdentity.shortHash(of: "0000FFFF-0000-1000-8000-00805F9B34FB"))
    }

    func testShortHashedUUIDDiffersForDifferentInputs() {
        let a = DeviceIdentity.shortHash(of: "AAAAAAAA-0000-0000-0000-000000000000")
        let b = DeviceIdentity.shortHash(of: "BBBBBBBB-0000-0000-0000-000000000000")
        XCTAssertNotEqual(a, b)
    }
}

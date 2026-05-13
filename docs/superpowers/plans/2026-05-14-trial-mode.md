# Trial Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 7-day free trial gated to one-per-Mac via a Polar free product, without adding backend infrastructure.

**Architecture:** A new Polar product with a license-key benefit that auto-expires in 7 days. The existing `LicenseManager` learns to (a) read `expires_at` from Polar's response and treat any key with it as a trial, (b) write a Keychain marker after successful trial activation so the same Mac can't trial again, and (c) carry a `sha256(IOPlatformUUID)` suffix in the Polar activation `label` for future server-side dedupe. UI gains a "Start Trial" CTA in onboarding, a trial-status banner in the popover, and a Subscribe CTA when expired.

**Tech Stack:** Swift 5.10, SwiftUI, IOKit (for `IOPlatformUUID`), CryptoKit (for sha256), XCTest with `MockURLProtocol` URLSession mocking, XcodeGen for project generation.

**Spec:** `docs/superpowers/specs/2026-05-14-trial-mode-design.md`

---

## File Structure

**Create:**
- `PostureDesk/Services/DeviceIdentity.swift` — IORegistry read + sha256 prefix helper (~40 lines)
- `PostureDeskTests/DeviceIdentityTests.swift` — unit tests for the hash helper

**Modify:**
- `project.yml` — add `POLAR_TRIAL_CHECKOUT_URL` build setting for Debug + Release
- `PostureDesk/Info.plist` — add `PolarTrialCheckoutURL` substitution key
- `PostureDesk/Services/LicenseManager.swift` — Config, parsing, state, gating, label
- `PostureDesk/PostureDeskApp.swift` — `licenseRefreshTask` switch covers new states
- `PostureDesk/Views/OnboardingView.swift` — `activateStep` adds trial CTA
- `PostureDesk/Views/Settings/SettingsView.swift` — license row gets Subscribe CTA for trial states
- `PostureDesk/Views/MenuBarPopover.swift` — trial banner + trial-expired lock card
- `PostureDeskTests/LicenseManagerTests.swift` — new trial scenarios

**Why this split:** All Polar-API and gating logic stays in `LicenseManager` (single source of truth). `DeviceIdentity` is its own file so it's trivial to mock and test. UI files only consume `LicenseManager` state — no business logic seeps into views.

---

### Task 1: Build config — add `PolarTrialCheckoutURL` to project

**Files:**
- Modify: `project.yml`
- Modify: `PostureDesk/Info.plist`

- [ ] **Step 1: Add the substitution variable to both build configs**

Edit `project.yml`. After line 47 (`POLAR_ORGANIZATION_ID: "322cca40-…"` in Debug), add:

```yaml
          POLAR_TRIAL_CHECKOUT_URL: "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_TRIAL_SANDBOX_PLACEHOLDER/redirect"
```

After line 53 (`POLAR_ORGANIZATION_ID: "8e1ae0f6-…"` in Release), add:

```yaml
          POLAR_TRIAL_CHECKOUT_URL: "https://buy.polar.sh/polar_cl_TRIAL_PRODUCTION_PLACEHOLDER"
```

(The user will replace the `…_PLACEHOLDER` values with real checkout links generated in the Polar dashboard later. The format mirrors the existing `POLAR_CHECKOUT_URL`.)

- [ ] **Step 2: Surface the key in `Info.plist`**

Edit `PostureDesk/Info.plist`. After the existing `PolarOrganizationID` block (around line 30), add:

```xml
    <key>PolarTrialCheckoutURL</key>
    <string>$(POLAR_TRIAL_CHECKOUT_URL)</string>
```

- [ ] **Step 3: Regenerate the Xcode project**

```bash
make generate
```

Expected: `xcodegen` output ending with `Generated project successfully…`.

- [ ] **Step 4: Confirm the substituted value is reachable at runtime in Debug**

```bash
make build
plutil -p build/Build/Products/Debug/GooseNeck.app/Contents/Info.plist | grep PolarTrialCheckoutURL
```

Expected: a line of the form `"PolarTrialCheckoutURL" => "https://sandbox-api.polar.sh/v1/checkout-links/…"`.

- [ ] **Step 5: Commit**

```bash
git add project.yml PostureDesk/Info.plist GooseNeck.xcodeproj
git commit -m "build: add PolarTrialCheckoutURL build setting"
```

---

### Task 2: `LicenseManager.Config` learns about `trialCheckoutURL`

**Files:**
- Modify: `PostureDesk/Services/LicenseManager.swift:347-417`
- Modify: `PostureDeskTests/LicenseManagerTests.swift`

- [ ] **Step 1: Write the failing test for trial URL parsing**

Add to `LicenseManagerTests.swift`:

```swift
func testConfigSurfacesTrialCheckoutURLFromBundleKeys() {
    let bundle = Bundle.main
    // We don't assert exact contents — just that the Config picks up the
    // key from the bundle without erroring. The actual value is wired via
    // build settings.
    let config = LicenseManager.Config(bundle: bundle)
    if let url = config.trialCheckoutPageURL {
        XCTAssertTrue(url.absoluteString.contains("polar.sh"))
    }
}

func testConfigRejectsSandboxTrialCheckoutInReleaseBuild() {
    let config = LicenseManager.Config(
        organizationId: "org_123",
        checkoutURL: "https://buy.polar.sh/polar_cl_PAID",
        trialCheckoutURL: "https://sandbox-api.polar.sh/v1/checkout-links/trial/redirect",
        baseURL: "https://api.polar.sh/v1/customer-portal/license-keys",
        requiresProductionConfiguration: true
    )
    XCTAssertEqual(config.validationError, "Release build cannot use a sandbox Polar trial checkout URL.")
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testConfigRejectsSandboxTrialCheckoutInReleaseBuild
```

Expected: compile failure ("extra argument 'trialCheckoutURL'…") or test failure once Config compiles.

- [ ] **Step 3: Extend `Config` with the trial URL field**

In `LicenseManager.swift`, replace the `Config` struct's stored properties + initializers (lines 348-372) with:

```swift
struct Config {
    let organizationId: String
    let checkoutURL: String
    let trialCheckoutURL: String
    let baseURL: String
    let requiresProductionConfiguration: Bool

    init(
        organizationId: String,
        checkoutURL: String,
        trialCheckoutURL: String = "",
        baseURL: String,
        requiresProductionConfiguration: Bool = false
    ) {
        self.organizationId = organizationId
        self.checkoutURL = checkoutURL
        self.trialCheckoutURL = trialCheckoutURL
        self.baseURL = baseURL
        self.requiresProductionConfiguration = requiresProductionConfiguration
    }

    init(bundle: Bundle) {
        self.init(
            organizationId: Self.value(for: "PolarOrganizationID", in: bundle) ?? "322cca40-cd2e-4d58-83e9-ec08ee2b0c19",
            checkoutURL: Self.value(for: "PolarCheckoutURL", in: bundle) ?? "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_DOGu45YJUcHzeFxGZw5EqT0L9gN3L9Qm2dTQn2Z4xHn/redirect",
            trialCheckoutURL: Self.value(for: "PolarTrialCheckoutURL", in: bundle) ?? "",
            baseURL: Self.value(for: "PolarAPIBaseURL", in: bundle) ?? "https://sandbox-api.polar.sh/v1/customer-portal/license-keys",
            requiresProductionConfiguration: Self.defaultRequiresProductionConfiguration
        )
    }

    var checkoutPageURL: URL? {
        URL(string: checkoutURL)
    }

    var trialCheckoutPageURL: URL? {
        trialCheckoutURL.isEmpty ? nil : URL(string: trialCheckoutURL)
    }
```

Note: `trialCheckoutURL` defaults to `""` (empty) so existing call sites and tests that don't pass one still compile. An empty string means "trial not configured" → `trialCheckoutPageURL` returns `nil`.

- [ ] **Step 4: Extend `validationError` to cover the trial URL**

Replace the existing `validationError` computed property (~line 378) with:

```swift
    var validationError: String? {
        guard !organizationId.isEmpty, !checkoutURL.isEmpty, !baseURL.isEmpty else {
            return "License configuration is missing."
        }

        guard let apiURL = URL(string: baseURL),
              let checkoutPageURL = checkoutPageURL else {
            return "License configuration is invalid."
        }

        if requiresProductionConfiguration {
            if Self.isSandboxHost(apiURL.host) {
                return "Release build cannot use a sandbox Polar API URL."
            }

            if Self.isSandboxHost(checkoutPageURL.host) {
                return "Release build cannot use a sandbox Polar checkout URL."
            }

            if let trialURL = trialCheckoutPageURL, Self.isSandboxHost(trialURL.host) {
                return "Release build cannot use a sandbox Polar trial checkout URL."
            }
        }

        return nil
    }
```

Note: An *empty* trial URL is allowed (trial not configured); only a *sandbox* trial URL in release fails validation.

- [ ] **Step 5: Run tests to verify they pass**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testConfigRejectsSandboxTrialCheckoutInReleaseBuild -only-testing:GooseNeckTests/LicenseManagerTests/testConfigSurfacesTrialCheckoutURLFromBundleKeys
```

Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add PostureDesk/Services/LicenseManager.swift PostureDeskTests/LicenseManagerTests.swift
git commit -m "feat(license): surface PolarTrialCheckoutURL via Config"
```

---

### Task 3: `DeviceIdentity` helper

**Files:**
- Create: `PostureDesk/Services/DeviceIdentity.swift`
- Create: `PostureDeskTests/DeviceIdentityTests.swift`

- [ ] **Step 1: Write the failing test**

Create `PostureDeskTests/DeviceIdentityTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test — expected to fail (no DeviceIdentity yet)**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/DeviceIdentityTests
```

Expected: compile failure ("cannot find 'DeviceIdentity' in scope").

- [ ] **Step 3: Implement `DeviceIdentity`**

Create `PostureDesk/Services/DeviceIdentity.swift`:

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/DeviceIdentityTests
```

Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add PostureDesk/Services/DeviceIdentity.swift PostureDeskTests/DeviceIdentityTests.swift
git commit -m "feat: add DeviceIdentity for hardware-id based device fingerprint"
```

---

### Task 4: Activation `label` includes hashed device fingerprint

**Files:**
- Modify: `PostureDesk/Services/LicenseManager.swift:443-451` (the `activateKey` method)
- Modify: `PostureDeskTests/LicenseManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `LicenseManagerTests.swift`:

```swift
func testActivateLabelIncludesHashedDeviceFingerprint() async {
    var capturedLabel: String?
    let (manager, _) = makeManager { request in
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
        capturedLabel = body?["label"] as? String
        return (
            self.httpResponse(url: request.url!, statusCode: 200),
            self.json(["id": "act_xyz", "status": "granted"])
        )
    }

    await manager.activate(key: "license-key-ABCDEFGH")

    XCTAssertNotNil(capturedLabel)
    // Label format: "<host name> · <8-hex>". The hash may or may not be
    // present in test environment; the dot-separator+hash suffix only
    // appears when DeviceIdentity.shortHashedUUID() returns non-nil.
    let label = capturedLabel ?? ""
    if label.contains(" · ") {
        let parts = label.components(separatedBy: " · ")
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[1].count, 8)
        XCTAssertTrue(parts[1].allSatisfy { $0.isHexDigit })
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testActivateLabelIncludesHashedDeviceFingerprint
```

Expected: PASS if the test machine doesn't have an `IOPlatformUUID`, FAIL otherwise because the current label is just `Host.current().localizedName`. The test is permissive in the "no hash" branch so we can still detect when the suffix logic is wrong.

If it doesn't fail in your environment, force-fail by temporarily adding `XCTAssertTrue(label.contains(" · "))` after the existing assertion to confirm the change is observable, then revert that line before committing.

- [ ] **Step 3: Add the helper to `LicenseManager`**

In `LicenseManager.swift`, add this private method near the other helpers (e.g. just below `makeRequest` around line 513):

```swift
    private func activationLabel() -> String {
        let host = Host.current().localizedName ?? "Mac"
        if let fingerprint = DeviceIdentity.shortHashedUUID() {
            return "\(host) · \(fingerprint)"
        }
        return host
    }
```

- [ ] **Step 4: Use it in `activateKey`**

Replace lines 443-451 (the `activateKey` body up through the request build) — specifically the `"label"` assignment — with:

```swift
    private func activateKey(_ key: String) async throws -> ActivationResult {
        let request = try makeRequest(
            path: "activate",
            body: [
                "key": key,
                "organization_id": config.organizationId,
                "label": activationLabel()
            ]
        )
```

(Only the `"label"` value changes; the rest of the function stays.)

- [ ] **Step 5: Run the test to verify it passes**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testActivateLabelIncludesHashedDeviceFingerprint
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add PostureDesk/Services/LicenseManager.swift PostureDeskTests/LicenseManagerTests.swift
git commit -m "feat(license): include hashed device fingerprint in Polar activation label"
```

---

### Task 5: Add `.trialActive` and `.trialExpired` cases to `LicenseState`

**Files:**
- Modify: `PostureDesk/Services/LicenseManager.swift:4-12, 25-62, 264-294`

No new tests in this task — the new cases aren't reachable yet; subsequent tasks add the transitions that produce them.

- [ ] **Step 1: Add the new enum cases**

Replace the `LicenseState` enum (lines 4-12) with:

```swift
enum LicenseState: Equatable {
    case unlicensed
    case validating
    case active
    case trialActive(until: Date)
    case trialExpired
    case gracePeriod(until: Date)
    case invalid
    case networkError
    case configurationError
}
```

- [ ] **Step 2: Update `isLicensed` mapping in `init`**

Replace the trailing switch in `init` (lines 56-61) with:

```swift
        switch initialState {
        case .active, .trialActive, .gracePeriod:
            isLicensed = true
        default:
            isLicensed = false
        }
```

- [ ] **Step 3: Update `stateLabel`**

Replace the `stateLabel` switch (lines 264-281) with:

```swift
    var stateLabel: String {
        switch licenseState {
        case .unlicensed:
            return "Inactive"
        case .validating:
            return "Checking"
        case .active:
            return "Active"
        case .trialActive(let until):
            let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: until).day ?? 0)
            return daysLeft <= 0 ? "Trial · last day" : "Trial · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
        case .trialExpired:
            return "Trial Ended"
        case .gracePeriod:
            return "Offline Grace"
        case .invalid:
            return "Invalid"
        case .networkError:
            return "Network Error"
        case .configurationError:
            return "Config Error"
        }
    }
```

- [ ] **Step 4: Update `stateDetail`**

Replace the `stateDetail` switch (lines 283-294) with:

```swift
    var stateDetail: String? {
        switch licenseState {
        case .trialActive(let until):
            return "Free trial · ends \(until.formatted(date: .abbreviated, time: .shortened))."
        case .trialExpired:
            return "Your free trial has ended. Subscribe to keep using GooseNeck."
        case .gracePeriod(let until):
            return "Using the last validated license until \(until.formatted(date: .abbreviated, time: .shortened))."
        case .networkError:
            return error ?? "We could not reach the license server."
        case .configurationError:
            return error ?? "The app's license configuration is incomplete."
        default:
            return nil
        }
    }
```

- [ ] **Step 5: Build to ensure the project still compiles**

```bash
make build
```

Expected: BUILD SUCCEEDED. (The new cases are added but unreachable, so existing tests still pass.)

- [ ] **Step 6: Run the full test suite**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests
```

Expected: all existing tests PASS.

- [ ] **Step 7: Commit**

```bash
git add PostureDesk/Services/LicenseManager.swift
git commit -m "feat(license): add .trialActive and .trialExpired states (unreachable yet)"
```

---

### Task 6: Parse `expires_at` from Polar response

**Files:**
- Modify: `PostureDesk/Services/LicenseManager.swift:419-426, 460-469, 487-497, 709-720`

- [ ] **Step 1: Write the failing test**

Add to `LicenseManagerTests.swift`:

```swift
func testActivateWithExpiresAtTransitionsToTrialActive() async {
    let expectedExpiry = Date().addingTimeInterval(7 * 24 * 60 * 60)
    let isoFormatter = ISO8601DateFormatter()
    let (manager, _) = makeManager { request in
        return (
            self.httpResponse(url: request.url!, statusCode: 200),
            self.json([
                "id": "act_trial",
                "status": "granted",
                "expires_at": isoFormatter.string(from: expectedExpiry)
            ])
        )
    }

    await manager.activate(key: "trial-key")

    XCTAssertTrue(manager.isLicensed)
    switch manager.licenseState {
    case .trialActive(let until):
        // ±5 sec tolerance for ISO8601 rounding.
        XCTAssertEqual(until.timeIntervalSince1970, expectedExpiry.timeIntervalSince1970, accuracy: 5)
    default:
        XCTFail("Expected .trialActive, got \(manager.licenseState)")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testActivateWithExpiresAtTransitionsToTrialActive
```

Expected: FAIL — the state will be `.active`, not `.trialActive`.

- [ ] **Step 3: Add `expiresAt` to result structs**

Replace the two private structs at lines 419-426 with:

```swift
    private struct ActivationResult {
        let activationId: String
        let status: String
        let expiresAt: Date?
    }

    private struct ValidationResult {
        let status: String
        let expiresAt: Date?
    }
```

- [ ] **Step 4: Add an `extractExpiresAt` helper**

Insert near `extractStatus` (around line 709):

```swift
    private static func extractExpiresAt(from json: [String: Any]) -> Date? {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]

        func parse(_ raw: String) -> Date? {
            isoFormatter.date(from: raw) ?? fallbackFormatter.date(from: raw)
        }

        if let raw = json["expires_at"] as? String,
           let date = parse(raw) {
            return date
        }
        if let licenseKey = json["license_key"] as? [String: Any],
           let raw = licenseKey["expires_at"] as? String,
           let date = parse(raw) {
            return date
        }
        return nil
    }
```

- [ ] **Step 5: Populate `expiresAt` in `activateKey`**

Replace lines 460-469 (the tail of `activateKey`) with:

```swift
        let json = try decodeJSON(from: data)
        guard let id = json["id"] as? String else {
            throw LicenseError.serverTransient("Invalid response from server.")
        }

        let status = Self.extractStatus(from: json) ?? "granted"
        let expiresAt = Self.extractExpiresAt(from: json)
        return ActivationResult(activationId: id, status: status, expiresAt: expiresAt)
    }
```

- [ ] **Step 6: Populate `expiresAt` in `validateKey`**

Replace lines 487-497 with:

```swift
        let json = try decodeJSON(from: data)
        guard let status = Self.extractStatus(from: json) else {
            throw LicenseError.serverTransient("Invalid response from server.")
        }

        let expiresAt = Self.extractExpiresAt(from: json)
        return ValidationResult(status: status, expiresAt: expiresAt)
    }
```

- [ ] **Step 7: Branch on `expiresAt` in `activate(key:)`**

Replace the success branch inside `activate(key:)` (lines 84-95) with:

```swift
            let result = try await activateKey(trimmed)
            guard storeLicense(key: trimmed, activationId: result.activationId) else {
                error = "Unable to persist the license on this Mac."
                licenseState = .configurationError
                isLicensed = false
                isValidating = false
                return
            }
            recordSuccessfulValidation(status: result.status)
            licenseStatus = result.status
            if let expiry = result.expiresAt, expiry > Date() {
                licenseState = .trialActive(until: expiry)
            } else {
                licenseState = .active
            }
            isLicensed = true
```

- [ ] **Step 8: Branch on `expiresAt` in `refreshStatus()`**

Replace the success branch inside `refreshStatus()` (lines 151-155) with:

```swift
            recordSuccessfulValidation(status: result.status)
            licenseStatus = result.status
            if let expiry = result.expiresAt, expiry > Date() {
                licenseState = .trialActive(until: expiry)
            } else {
                licenseState = .active
            }
            isLicensed = true
```

- [ ] **Step 9: Run the test to verify it passes**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testActivateWithExpiresAtTransitionsToTrialActive
```

Expected: PASS.

- [ ] **Step 10: Run the full LicenseManager test suite**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests
```

Expected: all PASS — existing `.active` tests still hold because their mocks don't include `expires_at`.

- [ ] **Step 11: Commit**

```bash
git add PostureDesk/Services/LicenseManager.swift PostureDeskTests/LicenseManagerTests.swift
git commit -m "feat(license): detect trial keys via expires_at in Polar response"
```

---

### Task 7: Trial expiry produces `.trialExpired` instead of `.invalid`

**Files:**
- Modify: `PostureDesk/Services/LicenseManager.swift:139-150, 564-568`
- Modify: `PostureDeskTests/LicenseManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Add:

```swift
func testRefreshStatusWithExpiredTrialKeyTransitionsToTrialExpired() async {
    let pastDate = Date().addingTimeInterval(-3600)
    let isoFormatter = ISO8601DateFormatter()
    let (manager, keychain) = makeManager { request in
        XCTAssertEqual(request.url?.lastPathComponent, "validate")
        return (
            self.httpResponse(url: request.url!, statusCode: 200),
            self.json([
                "status": "expired",
                "expires_at": isoFormatter.string(from: pastDate)
            ])
        )
    }
    keychain.set("stored-license", for: "license-key")
    keychain.set("act_999", for: "license-activation-id")

    await manager.refreshStatus()

    XCTAssertFalse(manager.isLicensed)
    XCTAssertEqual(manager.licenseState, .trialExpired)
    // Credentials should be cleared, same as .invalid.
    XCTAssertNil(keychain.string(for: "license-key"))
    XCTAssertNil(keychain.string(for: "license-activation-id"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testRefreshStatusWithExpiredTrialKeyTransitionsToTrialExpired
```

Expected: FAIL — state will be `.invalid`.

- [ ] **Step 3: Route expired trial keys to `.trialExpired`**

Replace the not-accepted branch in `refreshStatus()` (lines 142-149) with:

```swift
            guard Self.isAccepted(status: result.status) else {
                isLicensed = false
                if result.status.lowercased() == "expired", result.expiresAt != nil {
                    invalidateStoredLicense(message: "Your free trial has ended.", finalState: .trialExpired)
                } else {
                    invalidateStoredLicense(message: "License is \(result.status).")
                }
                isValidating = false
                return
            }
```

- [ ] **Step 4: Add the overload to `invalidateStoredLicense`**

Replace the existing `invalidateStoredLicense` (lines 564-568) with:

```swift
    private func invalidateStoredLicense(message: String, finalState: LicenseState = .invalid) {
        clearLicense()
        error = message
        licenseState = finalState
    }
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testRefreshStatusWithExpiredTrialKeyTransitionsToTrialExpired
```

Expected: PASS.

- [ ] **Step 6: Run the regression test for `.invalid` status**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testRefreshStatusMarksRevokedLicenseInvalid
```

Expected: still PASS — revoked has no `expires_at`, so it still routes to `.invalid`.

- [ ] **Step 7: Commit**

```bash
git add PostureDesk/Services/LicenseManager.swift PostureDeskTests/LicenseManagerTests.swift
git commit -m "feat(license): route expired trial keys to .trialExpired"
```

---

### Task 8: Write Keychain `trial-used-marker` on first successful trial activation

**Files:**
- Modify: `PostureDesk/Services/LicenseManager.swift:14-23, 64-119, 326-343`
- Modify: `PostureDeskTests/LicenseManagerTests.swift:16-37`

- [ ] **Step 1: Write the failing test**

Add:

```swift
func testSuccessfulTrialActivationWritesDeviceMarker() async {
    let expectedExpiry = Date().addingTimeInterval(7 * 24 * 60 * 60)
    let isoFormatter = ISO8601DateFormatter()
    let (manager, keychain) = makeManager { request in
        return (
            self.httpResponse(url: request.url!, statusCode: 200),
            self.json([
                "id": "act_trial",
                "status": "granted",
                "expires_at": isoFormatter.string(from: expectedExpiry)
            ])
        )
    }

    XCTAssertFalse(manager.hasUsedTrialOnDevice)
    await manager.activate(key: "trial-key")
    XCTAssertTrue(manager.hasUsedTrialOnDevice)
    XCTAssertNotNil(keychain.string(for: "trial-used-marker"))
}

func testSuccessfulPaidActivationDoesNotWriteDeviceMarker() async {
    let (manager, keychain) = makeManager { request in
        return (
            self.httpResponse(url: request.url!, statusCode: 200),
            self.json(["id": "act_paid", "status": "granted"])
        )
    }

    await manager.activate(key: "paid-key")
    XCTAssertFalse(manager.hasUsedTrialOnDevice)
    XCTAssertNil(keychain.string(for: "trial-used-marker"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testSuccessfulTrialActivationWritesDeviceMarker -only-testing:GooseNeckTests/LicenseManagerTests/testSuccessfulPaidActivationDoesNotWriteDeviceMarker
```

Expected: FAIL — `hasUsedTrialOnDevice` doesn't exist yet.

- [ ] **Step 3: Add the marker account name + public read**

In `LicenseManager.swift`, add to the static constants (around line 23):

```swift
    private static let trialUsedAccount = "trial-used-marker"
```

Add the public read (after the existing `private(set) var` declarations, around line 30):

```swift
    var hasUsedTrialOnDevice: Bool {
        keychain.string(for: Self.trialUsedAccount) != nil
    }
```

- [ ] **Step 4: Write the marker after successful trial activation**

In `activate(key:)`, replace the success branch from Task 6 Step 7 with this version that also writes the marker:

```swift
            let result = try await activateKey(trimmed)
            guard storeLicense(key: trimmed, activationId: result.activationId) else {
                error = "Unable to persist the license on this Mac."
                licenseState = .configurationError
                isLicensed = false
                isValidating = false
                return
            }
            recordSuccessfulValidation(status: result.status)
            licenseStatus = result.status
            if let expiry = result.expiresAt, expiry > Date() {
                markTrialUsedIfNeeded()
                licenseState = .trialActive(until: expiry)
            } else {
                licenseState = .active
            }
            isLicensed = true
```

Add the private helper near the other storage helpers (around line 322):

```swift
    private func markTrialUsedIfNeeded() {
        guard keychain.string(for: Self.trialUsedAccount) == nil else { return }
        let isoFormatter = ISO8601DateFormatter()
        let stamp = isoFormatter.string(from: Date())
        _ = keychain.set(stamp, for: Self.trialUsedAccount)
    }
```

- [ ] **Step 5: Ensure `clearLicense()` does NOT remove the marker**

This is intentional — the marker survives deactivate/clear so the user can't reset their trial by deactivating. Confirm by reading the existing `clearLicense()` (line 325-343): it removes `licenseKeyAccount` and `activationIdAccount` only. **No code change** — just verify.

- [ ] **Step 6: Update `tearDown` in tests to clean up the marker between tests**

Replace the keychain cleanup loop in `tearDown` (lines 19-23) with:

```swift
        for keychain in keychains {
            keychain.removeValue(for: "license-key")
            keychain.removeValue(for: "license-activation-id")
            keychain.removeValue(for: "trial-used-marker")
        }
        keychains.removeAll()
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testSuccessfulTrialActivationWritesDeviceMarker -only-testing:GooseNeckTests/LicenseManagerTests/testSuccessfulPaidActivationDoesNotWriteDeviceMarker
```

Expected: PASS.

- [ ] **Step 8: Run the full LicenseManager suite**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests
```

Expected: all PASS.

- [ ] **Step 9: Commit**

```bash
git add PostureDesk/Services/LicenseManager.swift PostureDeskTests/LicenseManagerTests.swift
git commit -m "feat(license): write Keychain trial-used-marker on first trial activation"
```

---

### Task 9: Block trial re-activation when device marker is present

**Files:**
- Modify: `PostureDesk/Services/LicenseManager.swift:66-119, 213-243`
- Modify: `PostureDeskTests/LicenseManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Add:

```swift
func testActivateBlocksTrialReactivationWhenDeviceMarkerExists() async {
    let isoFormatter = ISO8601DateFormatter()
    let futureExpiry = Date().addingTimeInterval(7 * 24 * 60 * 60)

    var deactivateCalled = false
    let (manager, keychain) = makeManager { request in
        switch request.url?.lastPathComponent {
        case "activate":
            return (
                self.httpResponse(url: request.url!, statusCode: 200),
                self.json([
                    "id": "act_new_trial",
                    "status": "granted",
                    "expires_at": isoFormatter.string(from: futureExpiry)
                ])
            )
        case "deactivate":
            deactivateCalled = true
            return (
                self.httpResponse(url: request.url!, statusCode: 200),
                Data()
            )
        default:
            XCTFail("Unexpected request to \(request.url?.absoluteString ?? "?")")
            throw URLError(.badURL)
        }
    }

    // Pre-seed the marker as if the user had already used a trial.
    keychain.set("2026-01-01T00:00:00Z", for: "trial-used-marker")

    await manager.activate(key: "another-trial-key")

    XCTAssertFalse(manager.isLicensed)
    XCTAssertEqual(manager.licenseState, .unlicensed)
    XCTAssertNotNil(manager.error)
    XCTAssertTrue(manager.error?.contains("already used") ?? false)
    XCTAssertNil(keychain.string(for: "license-key"))
    XCTAssertNil(keychain.string(for: "license-activation-id"))
    // Marker stays put.
    XCTAssertNotNil(keychain.string(for: "trial-used-marker"))
    // We freed the wasted Polar slot.
    XCTAssertTrue(deactivateCalled)
}

func testActivateAllowsPaidKeyEvenWhenTrialMarkerExists() async {
    let (manager, keychain) = makeManager { request in
        XCTAssertEqual(request.url?.lastPathComponent, "activate")
        return (
            self.httpResponse(url: request.url!, statusCode: 200),
            self.json(["id": "act_paid", "status": "granted"])
        )
    }
    keychain.set("2026-01-01T00:00:00Z", for: "trial-used-marker")

    await manager.activate(key: "paid-key")

    XCTAssertTrue(manager.isLicensed)
    XCTAssertEqual(manager.licenseState, .active)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testActivateBlocksTrialReactivationWhenDeviceMarkerExists -only-testing:GooseNeckTests/LicenseManagerTests/testActivateAllowsPaidKeyEvenWhenTrialMarkerExists
```

Expected: blocking test FAILs (the trial activation succeeds today). Paid test should PASS already.

- [ ] **Step 3: Add the gating helper**

In `LicenseManager.swift`, add a private helper near `performDeactivation` (around line 213):

```swift
    private func deactivateSilently(key: String, activationId: String) async {
        // Fire-and-forget. Outcome doesn't matter for the user: they're
        // blocked locally regardless. We try once; if Polar is unreachable
        // the activation slot is wasted but the user is still blocked.
        _ = await performDeactivation(key: key, activationId: activationId)
    }
```

- [ ] **Step 4: Add the post-fact gate in `activate(key:)`**

Replace the success branch in `activate(key:)` (from Task 8 Step 4) with:

```swift
            let result = try await activateKey(trimmed)

            if let expiry = result.expiresAt, expiry > Date(), hasUsedTrialOnDevice {
                // Trial key, but this device has already burned its trial.
                // Free Polar's slot, surface the error, do NOT persist creds.
                await deactivateSilently(key: trimmed, activationId: result.activationId)
                error = "You've already used your free trial on this Mac. Subscribe to keep using GooseNeck."
                licenseState = .unlicensed
                isLicensed = false
                isValidating = false
                return
            }

            guard storeLicense(key: trimmed, activationId: result.activationId) else {
                error = "Unable to persist the license on this Mac."
                licenseState = .configurationError
                isLicensed = false
                isValidating = false
                return
            }
            recordSuccessfulValidation(status: result.status)
            licenseStatus = result.status
            if let expiry = result.expiresAt, expiry > Date() {
                markTrialUsedIfNeeded()
                licenseState = .trialActive(until: expiry)
            } else {
                licenseState = .active
            }
            isLicensed = true
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testActivateBlocksTrialReactivationWhenDeviceMarkerExists -only-testing:GooseNeckTests/LicenseManagerTests/testActivateAllowsPaidKeyEvenWhenTrialMarkerExists
```

Expected: both PASS.

- [ ] **Step 6: Run the full LicenseManager suite**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests
```

Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add PostureDesk/Services/LicenseManager.swift PostureDeskTests/LicenseManagerTests.swift
git commit -m "feat(license): block trial re-activation when device marker is present"
```

---

### Task 10: Add `openTrialCheckout()` method

**Files:**
- Modify: `PostureDesk/Services/LicenseManager.swift:245-253`
- Modify: `PostureDeskTests/LicenseManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Add:

```swift
func testOpenTrialCheckoutSetsConfigurationErrorWhenURLMissing() {
    let config = LicenseManager.Config(
        organizationId: "org_123",
        checkoutURL: "https://polar.sh/checkout",
        trialCheckoutURL: "",
        baseURL: "https://api.polar.sh/v1/customer-portal/license-keys"
    )
    let (manager, _) = makeManager(config: config) { _ in
        XCTFail("Network should not be called.")
        throw URLError(.badURL)
    }

    manager.openTrialCheckout()

    XCTAssertEqual(manager.licenseState, .configurationError)
    XCTAssertNotNil(manager.error)
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testOpenTrialCheckoutSetsConfigurationErrorWhenURLMissing
```

Expected: FAIL — `openTrialCheckout()` doesn't exist.

- [ ] **Step 3: Add the method**

In `LicenseManager.swift`, add a method just after the existing `openCheckout()` (around line 253):

```swift
    func openTrialCheckout() {
        guard config.validationError == nil, let url = config.trialCheckoutPageURL else {
            error = config.validationError ?? "Free trial is not configured."
            licenseState = .configurationError
            return
        }

        NSWorkspace.shared.open(url)
    }
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
xcodebuild test -scheme GooseNeck -only-testing:GooseNeckTests/LicenseManagerTests/testOpenTrialCheckoutSetsConfigurationErrorWhenURLMissing
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add PostureDesk/Services/LicenseManager.swift PostureDeskTests/LicenseManagerTests.swift
git commit -m "feat(license): add openTrialCheckout() to launch the free-trial Polar checkout"
```

---

### Task 11: `PostureDeskApp` reacts to new states

**Files:**
- Modify: `PostureDesk/PostureDeskApp.swift:215-226`

UI-only change; no unit test. The branches mirror existing `.active`/`.invalid` handling.

- [ ] **Step 1: Update the `licenseRefreshTask` switch**

Replace the switch in `licenseRefreshTask` (lines 216-225) with:

```swift
                switch GooseNeckApp.licenseManager.licenseState {
                case .active, .trialActive, .gracePeriod:
                    viewModel?.unlockMonitoring()
                    viewModel?.start()
                case .unlicensed, .invalid, .trialExpired:
                    viewModel?.stop(lockMonitoring: true, finalizeSession: false)
                    self.showOnboarding(startAt: .activate)
                default:
                    viewModel?.stop(lockMonitoring: true, finalizeSession: false)
                }
```

- [ ] **Step 2: Build**

```bash
make build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PostureDesk/PostureDeskApp.swift
git commit -m "feat(app): route .trialActive like .active and .trialExpired like .invalid at launch"
```

---

### Task 12: Onboarding `activateStep` — Start Trial CTA

**Files:**
- Modify: `PostureDesk/Views/OnboardingView.swift:807-926`

UI changes only; no unit test. Manual verification in Task 16.

- [ ] **Step 1: Update the step copy + add the trial button above Buy**

Find the `activateStep` body (line 807) and replace its inner content from the icon down to the "already have a key?" divider (lines 815-871) with:

```swift
            Spacer()

            // Icon
            Image(systemName: "key.fill")
                .font(.system(size: 44))
                .foregroundStyle(DS.Colors.accentInfo)
                .padding(.bottom, 8)

            VStack(spacing: 8) {
                Text("Activate GooseNeck")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.textPrimary)

                Text(licenseManager.hasUsedTrialOnDevice
                     ? "Enter your license key to start monitoring."
                     : "Try free for 7 days, or enter your license key.")
                    .font(DS.Font.body())
                    .foregroundStyle(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer().frame(height: 24)

            if !licenseManager.hasUsedTrialOnDevice {
                // Trial CTA — primary, only when device hasn't burned its trial.
                Button {
                    licenseManager.openTrialCheckout()
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13))
                            Text("Start 7-day Free Trial")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        Text("No card required")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 12)
                    .background(DS.Colors.accentInfo, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the Polar checkout page to start a 7-day free trial.")

                Spacer().frame(height: 12)

                // Buy — secondary when trial is available.
                Button {
                    licenseManager.openCheckout()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cart")
                            .font(.system(size: 12))
                        Text("Buy a License — $14.99")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(DS.Colors.textPrimary)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 10)
                    .background(DS.Colors.cardBg, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DS.Colors.cardBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the Polar checkout page to buy a GooseNeck license for $14.99.")
            } else {
                // Trial used — promote Buy to primary, surface caption.
                Button {
                    licenseManager.openCheckout()
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "cart")
                                .font(.system(size: 13))
                            Text("Buy a License — $14.99")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        Text("One-time purchase · Unlimited updates")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: 280)
                    .padding(.vertical, 12)
                    .background(DS.Colors.accentInfo, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the Polar checkout page to buy a GooseNeck license for $14.99.")

                Spacer().frame(height: 8)

                Text("Free trial already used on this Mac")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textMuted)
            }

            // Divider
            HStack(spacing: 12) {
                Rectangle()
                    .fill(DS.Colors.cardBorder)
                    .frame(height: 1)
                Text("already have a key?")
                    .font(DS.Font.caption())
                    .foregroundStyle(DS.Colors.textMuted)
                    .layoutPriority(1)
                Rectangle()
                    .fill(DS.Colors.cardBorder)
                    .frame(height: 1)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 40)
```

(The key-entry HStack and the trailing error text below it stay exactly as they are — they read `licenseManager.error` already.)

- [ ] **Step 2: Build**

```bash
make build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add PostureDesk/Views/OnboardingView.swift
git commit -m "feat(onboarding): add Start 7-day Free Trial CTA above Buy"
```

---

### Task 13: `SettingsView` — Subscribe CTA for trial states

**Files:**
- Modify: `PostureDesk/Views/Settings/SettingsView.swift:481-528`

- [ ] **Step 1: Extend the status color helper**

Replace `licenseStatusColor` (lines 481-492) with:

```swift
    private var licenseStatusColor: Color {
        switch licenseManager.licenseState {
        case .active:
            return DS.Colors.accentGood
        case .trialActive:
            return DS.Colors.accentInfo
        case .gracePeriod:
            return DS.Colors.accentWarn
        case .trialExpired:
            return DS.Colors.accentWarn
        case .validating:
            return DS.Colors.accentInfo
        default:
            return DS.Colors.accentDanger
        }
    }
```

- [ ] **Step 2: Extend the action button**

Replace `licenseActionButton` (lines 498-528) with:

```swift
    @ViewBuilder
    private var licenseActionButton: some View {
        switch licenseManager.licenseState {
        case .active, .gracePeriod:
            Button("Deactivate License") {
                showDeactivateAlert = true
            }
            .foregroundStyle(DS.Colors.accentDanger)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))

        case .trialActive:
            HStack(spacing: 12) {
                Button("Subscribe") {
                    licenseManager.openCheckout()
                }
                .foregroundStyle(DS.Colors.accentInfo)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))

                Button("Deactivate") {
                    showDeactivateAlert = true
                }
                .foregroundStyle(DS.Colors.accentDanger)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
            }

        case .trialExpired:
            Button("Subscribe") {
                licenseManager.openCheckout()
            }
            .foregroundStyle(DS.Colors.accentInfo)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))

        case .validating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Validating\u{2026}")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Colors.textMuted)
            }

        default:
            Button("Activate License") {
                DispatchQueue.main.async {
                    viewModel.stop(lockMonitoring: true)
                    UserDefaults.standard.set(false, forKey: "onboardingComplete")
                    AppDelegate.shared?.showOnboarding(startAt: .activate)
                }
            }
            .foregroundStyle(DS.Colors.accentInfo)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
        }
    }
```

- [ ] **Step 3: Build**

```bash
make build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add PostureDesk/Views/Settings/SettingsView.swift
git commit -m "feat(settings): surface Subscribe CTA for .trialActive and .trialExpired"
```

---

### Task 14: `MenuBarPopover` — trial banner + trial-expired lock card

**Files:**
- Modify: `PostureDesk/Views/MenuBarPopover.swift`

- [ ] **Step 1: Inject `LicenseManager`**

At the top of `MenuBarPopover` (after the existing `@Environment` declarations), add:

```swift
    @Environment(LicenseManager.self) private var licenseManager
```

- [ ] **Step 2: Add a trial banner and lock card inside `body`**

The current popover body starts with a Header `HStack` and a series of Dividers + sections. Wrap the existing content so:

- When `licenseState == .trialExpired`, show **only** a lock card (replacing the metrics + actions entirely).
- When `licenseState == .trialActive(let until)`, show the existing content with a thin banner just above the metrics.

Concretely, replace the `var body: some View { VStack(alignment: .leading, spacing: 0) { … } }` opening with:

```swift
    var body: some View {
        if case .trialExpired = licenseManager.licenseState {
            trialExpiredLockCard
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // …existing content stays exactly as-is…
            }
        }
    }
```

Then inside the existing `VStack` body, just after the Header `HStack`'s closing `.accessibilityValue(...)` (around line 32), insert:

```swift
            if case .trialActive(let until) = licenseManager.licenseState {
                trialBanner(until: until)
                Divider()
            }
```

- [ ] **Step 3: Add the helper views at the bottom of the struct**

Just before the closing brace of `MenuBarPopover`, add:

```swift
    private func trialBanner(until: Date) -> some View {
        let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: until).day ?? 0)
        let urgent = daysLeft <= 1
        return HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(urgent ? DS.Colors.accentWarn : DS.Colors.accentInfo)
            Text(daysLeft <= 0 ? "Trial · last day" : "Trial · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)
            Spacer()
            Button("Subscribe") {
                licenseManager.openCheckout()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(DS.Colors.accentInfo)
            .accessibilityHint("Opens the GooseNeck purchase page in your browser.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background((urgent ? DS.Colors.accentWarn : DS.Colors.accentInfo).opacity(0.08))
    }

    private var trialExpiredLockCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(DS.Colors.accentWarn)

            Text("Your free trial has ended")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.textPrimary)

            Text("Subscribe to keep monitoring your posture.")
                .font(DS.Font.caption())
                .foregroundStyle(DS.Colors.textSecondary)
                .multilineTextAlignment(.center)

            Button {
                licenseManager.openCheckout()
            } label: {
                Text("Subscribe — $14.99")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(DS.Colors.accentInfo, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the GooseNeck purchase page in your browser.")
        }
        .padding(16)
        .frame(width: 260)
    }
```

- [ ] **Step 4: Build**

```bash
make build
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add PostureDesk/Views/MenuBarPopover.swift
git commit -m "feat(popover): add trial banner and trial-expired lock card"
```

---

### Task 15: Manual smoke verification

This is the only end-to-end check before shipping. The earlier tasks cover correctness via unit tests; this confirms the wiring across processes (Polar checkout in a browser, redirect back, key paste).

- [ ] **Step 1: Configure the sandbox trial product in Polar**

In the Polar sandbox dashboard, in org `322cca40-cd2e-4d58-83e9-ec08ee2b0c19`:

1. Create a new product "GooseNeck Free Trial" with $0 / one-time pricing.
2. Attach a License Key benefit with:
   - `expires_at`: 7 days after issue (use the "expires after duration" option)
   - `activation_limit`: 1
   - `enable_user_admin`: off
3. Generate a hosted checkout link.
4. Replace the `POLAR_TRIAL_CHECKOUT_URL` placeholder in `project.yml` Debug config with the real URL.
5. `make generate && make build`.

- [ ] **Step 2: Reset local state**

```bash
defaults delete com.gooseneck.app onboardingComplete 2>/dev/null
defaults delete com.gooseneck.app onboardingSetupComplete 2>/dev/null
security delete-generic-password -a "trial-used-marker" -s "com.gooseneck.app.license" 2>/dev/null
security delete-generic-password -a "license-key" -s "com.gooseneck.app.license" 2>/dev/null
security delete-generic-password -a "license-activation-id" -s "com.gooseneck.app.license" 2>/dev/null
```

- [ ] **Step 3: Run the app and verify the trial path**

```bash
make run
```

Verify:
- Onboarding reaches the Activate step.
- "Start 7-day Free Trial" button is visible and primary.
- Click it → browser opens to the Polar trial checkout.
- Complete checkout with a test email → receive an email with a license key.
- Paste key into the field → click Activate.
- License state becomes `.trialActive`. Onboarding completes; the app starts monitoring.

- [ ] **Step 4: Verify the device-marker block**

Quit the app. Run:

```bash
security find-generic-password -a "trial-used-marker" -s "com.gooseneck.app.license" -w
```

Expected: prints an ISO-8601 timestamp.

Deactivate the license from Settings, then re-enter the activation step. Verify:
- "Start 7-day Free Trial" button is now hidden; "Free trial already used on this Mac" caption shows; Buy is primary.

- [ ] **Step 5: Verify the trial banner**

Re-activate with the same trial key (it'll fail with the "already used" error — good, that's the post-fact gate). To verify the banner instead, delete only the keychain credentials but **keep** the marker, then re-trial with a fresh email:

```bash
security delete-generic-password -a "license-key" -s "com.gooseneck.app.license"
security delete-generic-password -a "license-activation-id" -s "com.gooseneck.app.license"
# Marker stays
```

Try to activate a NEW trial key with a different email — should be blocked with "already used your free trial" message and the trial slot is deactivated on Polar's side. ✓

Reset the marker too:

```bash
security delete-generic-password -a "trial-used-marker" -s "com.gooseneck.app.license"
```

Trial again, then while in `.trialActive`, open the menu bar popover → confirm "Trial · N days left · Subscribe" banner appears.

- [ ] **Step 6: Verify trial-expired**

In Polar's sandbox dashboard, manually edit the license key's `expires_at` to a date in the past. Re-launch the app; `refreshStatus()` should route to `.trialExpired`:

- Popover shows the lock card.
- Settings shows "Trial Ended" + Subscribe.
- Onboarding re-opens at the Activate step (because `PostureDeskApp` treats `.trialExpired` like `.invalid`).

- [ ] **Step 7: Commit (manual verification log)**

No code changes in this task — just verification. Skip the commit.

---

## Self-Review

**Spec coverage:**
- §1 Polar dashboard setup → Task 1 (build config) + Task 15 Step 1 (Polar setup, manual)
- §2 Trial detection via `expires_at` → Task 6
- §3 New `LicenseState` cases → Task 5 + Task 7
- §4a `DeviceIdentity` → Task 3
- §4b Keychain marker → Task 8
- §4c Activation gate → Task 9
- §4d Activation `label` → Task 4
- §5a Onboarding CTA → Task 12
- §5b Popover banner + lock card → Task 14
- §5c Settings row → Task 13
- App-level state routing (not explicit in spec but required) → Task 11
- Tests → built into Tasks 2–10

**Placeholder scan:** No "TBD" / "TODO" / "fill in" anywhere in this plan. Trial URLs in `project.yml` are intentional placeholders the user replaces in Task 15 Step 1 — flagged explicitly there.

**Type consistency:**
- `ActivationResult` / `ValidationResult` get `expiresAt: Date?` in Task 6 and are used consistently in Tasks 7–9.
- `LicenseState.trialActive(until: Date)` — `until` parameter name matches across Tasks 5, 6, 7, 11, 12, 14.
- `hasUsedTrialOnDevice` — name matches across Tasks 8, 9, 12.
- `markTrialUsedIfNeeded()` — same name in Task 8 (definition) and Task 9 (usage).
- `deactivateSilently(key:activationId:)` — defined and called once, in Task 9.
- `activationLabel()` — defined and called once, in Task 4.
- `openTrialCheckout()` — defined in Task 10, called in Task 12.
- Keychain account string `"trial-used-marker"` — matches across Tasks 8 (definition), 9 (test), 15 (manual reset).

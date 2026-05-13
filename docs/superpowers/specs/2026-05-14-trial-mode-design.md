# Trial Mode (Polar Free Product + Device Gating)

**Date:** 2026-05-14
**Status:** Design — ready for implementation

## Goal

Let prospective users try GooseNeck for **7 days** without paying, while gating the trial to **one per Mac** so the obvious abuse loop (new email → new trial) is closed without adding backend infrastructure.

## Constraints

- No backend. Reuse the existing Polar `customer-portal/license-keys/{activate,validate,deactivate}` integration in `PostureDesk/Services/LicenseManager.swift`.
- App is non-sandboxed, so IORegistry / Keychain access is straightforward.
- No customer base yet — no migration, no backwards-compat shims. Change the code in place.

## Architecture

### 1. Polar dashboard setup

Create a new product in the same Polar organization (`322cca40-cd2e-4d58-83e9-ec08ee2b0c19`):

- **Name:** "GooseNeck Free Trial"
- **Pricing:** $0 / one-time
- **Benefit:** License Key with
  - `expires_at` = 7 days after issue
  - `activation_limit` = 1
  - `activations.enable_user_admin` = false (user can't deactivate to extend)

Generate a hosted checkout link. Store both sandbox and production URLs in `Info.plist` under a new key, mirroring the existing `PolarCheckoutURL`:

```
PolarTrialCheckoutURL = "https://…/checkout-links/polar_cl_TRIAL…/redirect"
```

`LicenseManager.Config` gets a `trialCheckoutURL: String` field and a `trialCheckoutPageURL: URL?` computed property, with the same sandbox-host check applied to it in release builds as the existing checkout URL.

### 2. Trial detection (`expires_at` based)

The Polar `activate` and `validate` responses already contain the license key object, which exposes `expires_at` for any time-limited key. The client treats *any* successfully validated key whose response includes `expires_at` as a trial.

Justification: today GooseNeck sells exactly one product — a perpetual paid license with no `expires_at`. Trial keys have `expires_at`. So `expires_at != nil ⇔ trial`. If a paid subscription product is added later, this rule needs to upgrade to reading `meta.kind` from the product benefit (already supported by Polar; just not configured today).

Parsing changes in `LicenseManager.swift`:

```swift
private struct ActivationResult {
    let activationId: String
    let status: String
    let expiresAt: Date?       // new
}

private struct ValidationResult {
    let status: String
    let expiresAt: Date?       // new
}
```

`extractStatus(from:)` gains a sibling `extractExpiresAt(from:)` that:
- Tries top-level `expires_at` first (ISO-8601 string).
- Falls back to `license_key.expires_at`.
- Returns `nil` if missing or unparsable.

### 3. `LicenseState` extensions

```swift
enum LicenseState: Equatable {
    case unlicensed
    case validating
    case active
    case trialActive(until: Date)   // new
    case trialExpired                // new
    case gracePeriod(until: Date)
    case invalid
    case networkError
    case configurationError
}
```

Transition rules in `LicenseManager`:

| Polar response | Resulting state |
|---|---|
| `status` accepted, `expires_at == nil` | `.active` |
| `status` accepted, `expires_at > now` | `.trialActive(until: expires_at)` |
| `status == "expired"` AND `expires_at != nil` (or stored credentials were a trial) | `.trialExpired` |
| `status == "expired"` AND no trial signal | `.invalid` (existing path) |
| All other rejected statuses (`blocked`, `disabled`, `revoked`) | `.invalid` (existing path) |

`isLicensed` is `true` for `.active` and `.trialActive`; `false` for `.trialExpired`.

`stateLabel`:
- `.trialActive` → "Trial" (UI computes "· N days left" from `until`)
- `.trialExpired` → "Trial Ended"

`stateDetail`:
- `.trialActive(let until)` → "Free trial · ends \(until.formatted(date: .abbreviated, time: .shortened))"
- `.trialExpired` → "Your free trial has ended. Subscribe to keep using GooseNeck."

Offline grace works identically for trial and paid keys — same 7-day window from last successful validation. A trial therefore could in theory run 7 days online + 7 days offline. Acceptable.

### 4. Device gating

#### 4a. Hardware identifier

New helper `PostureDesk/Services/DeviceIdentity.swift`:

```swift
enum DeviceIdentity {
    /// IOPlatformUUID from IORegistry. Stable per-Mac; survives macOS reinstall;
    /// requires NVRAM reset to change.
    static func platformUUID() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/")
        defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(
            entry,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else { return nil }
        return value
    }

    /// First 8 hex chars of sha256(IOPlatformUUID). Sent to Polar as part of
    /// activation `label` so we never share the raw hardware ID.
    static func shortHashedUUID() -> String? {
        guard let uuid = platformUUID() else { return nil }
        return uuid.sha256Prefix(8)
    }
}
```

(`sha256Prefix` is a small `String` extension using CryptoKit.)

#### 4b. Keychain marker

Add a new account name `Self.trialUsedAccount = "trial-used-marker"` to `LicenseManager`. The value is the ISO-8601 timestamp of first successful trial activation; existence of the entry is the signal.

Public reads:
```swift
var hasUsedTrialOnDevice: Bool {
    keychain.string(for: Self.trialUsedAccount) != nil
}
```

Writes:
- After a successful activation where the response carried `expires_at`, set the marker (if not already set).
- Never cleared by `deactivate()` or `clearLicense()` — the whole point is that it persists across reinstall and license churn.

The marker lives in the same `KeychainStore`. On macOS, generic password items in the user's login keychain are not removed when the app is deleted, which is the property we need.

#### 4c. Activation gate

`activate(key:)` flow when `hasUsedTrialOnDevice == true`:

1. Send the `activate` request as today (we need Polar's response to know whether the key is a trial).
2. If response includes `expires_at`:
   - Immediately fire `deactivate` to free Polar's activation slot.
   - Discard the activation ID locally; do NOT persist credentials.
   - Surface error: "You've already used your free trial on this Mac. Subscribe to keep using GooseNeck."
   - Set `licenseState = .unlicensed` and return.
3. If response has no `expires_at`, it's a paid key — proceed exactly as today.

Why post-fact rather than pre-flight? We don't know whether a key is a trial without calling Polar. Erring on "let activate happen, then revoke if it was a trial" keeps the rule strictly server-truthful and avoids an extra "is this a trial key?" probe.

If the follow-up `deactivate` fails (network blip, server error), the Polar activation is left dangling: from Polar's perspective the trial key is now "activated" against this Mac, but the app has no credentials persisted. That's harmless — the user is still blocked by the local marker, and Polar's activation slot is just wasted. We don't retry.

#### 4d. Activation `label`

Replace:
```swift
"label": Host.current().localizedName ?? "Mac"
```

with:
```swift
"label": activationLabel()
```

where:
```swift
private func activationLabel() -> String {
    let host = Host.current().localizedName ?? "Mac"
    if let fingerprint = DeviceIdentity.shortHashedUUID() {
        return "\(host) · \(fingerprint)"
    }
    return host
}
```

Polar's admin UI now shows entries like `Than's MBP · 7a3f2b1c`. Future server-side dedupe can group activations by suffix.

### 5. UI surfaces

#### 5a. Onboarding — `activateStep` (`OnboardingView.swift:807`)

Layout becomes (top to bottom):

```
"Activate GooseNeck"
"Enter your license key — or start a free 7-day trial"

[ Start 7-day Free Trial — no card required ]    ← primary, accentInfo
[ Buy a License — $14.99 · One-time            ]    ← secondary, neutral
              — already have a key? —
[ paste field ]                          [ Activate ]
```

When `licenseManager.hasUsedTrialOnDevice == true`:
- The trial button is replaced with caption text "Free trial already used on this Mac" in `textMuted`.
- The Buy button is promoted to primary (accentInfo).
- Copy under the title becomes: "Enter your license key to start monitoring."

Tap on "Start 7-day Free Trial" calls a new `LicenseManager.openTrialCheckout()` which opens `config.trialCheckoutPageURL`. The user then completes Polar's free checkout in the browser, receives an email with a trial license key, and pastes it into the existing key field.

#### 5b. Menu bar popover

When `licenseState == .trialActive(let until)`:
- A thin banner under the header reads `"Trial · \(daysLeft) days left"` with a chevron arrow opening Subscribe.
- Color: `accentInfo` normally; `accentWarning` when `daysLeft ≤ 1`.

When `licenseState == .trialExpired`:
- The popover content is replaced with a lock card: "Your free trial has ended" + a primary "Subscribe" button that calls `openCheckout()`. Mirrors the existing `.invalid` lock visually but with friendly copy.

#### 5c. Settings → License row

`SettingsView` license row (already shows `licenseManager.stateLabel`) gains:
- For `.trialActive`: a Subscribe CTA next to the status.
- For `.trialExpired`: status text in `accentWarning`, with Subscribe as a primary button.

### 6. Anti-abuse limitations (acknowledged, accepted)

These bypasses exist by design — closing them would require a backend:
- Manually deleting the Keychain entry via Keychain Access.app (uncommon).
- NVRAM reset (regenerates `IOPlatformUUID`; rare and user-initiated for boot issues).
- Different physical Mac.

We send `sha256(IOPlatformUUID)[..8]` to Polar as the activation `label`, so if/when a backend exists, server-side dedupe by that suffix is a one-day project.

## Testing strategy

Extend `PostureDeskTests/LicenseManagerTests.swift`. Existing tests already mock `URLSession`; we follow the same pattern.

New tests:
1. **Trial activation success** — Mock `activate` response includes `expires_at` 7 days out → `licenseState == .trialActive(until:)`, `isLicensed == true`, Keychain marker is written.
2. **Trial re-activation blocked** — With marker pre-set, mock `activate` returns trial response → state goes back to `.unlicensed`, `error` matches "already used your free trial", `deactivate` is fired against the new activation ID, no credentials persisted.
3. **Paid activation unaffected** — Response has no `expires_at` → existing `.active` path, no marker written.
4. **Trial validation expired** — Mock `validate` returns `status == "expired"` + past `expires_at` → `.trialExpired` (not `.invalid`); credentials cleared.
5. **Activation label format** — Mock `Host.current().localizedName` + `DeviceIdentity.shortHashedUUID()`; assert outgoing body's `label` equals `"\(host) · \(suffix)"`.
6. **DeviceIdentity** — Unit test for `shortHashedUUID()` producing stable 8-char hex from a known UUID input.

UI changes are not unit-tested; manually verified per the existing pattern (onboarding flow + popover banner + settings row).

## Out of scope

- Backend for stronger device dedupe.
- Soft grace period on trial expiry — hard cutoff at `expires_at`.
- "Extend trial" / promo codes.
- Polar product `meta.kind` tagging (defer until paid subscription with expiry is added).
- Trial-conversion analytics.

## Files affected

- `PostureDesk/Services/LicenseManager.swift` — Config additions, response parsing, new state cases, gating logic.
- `PostureDesk/Services/DeviceIdentity.swift` — new, ~30 lines.
- `PostureDesk/Services/KeychainStore.swift` — no changes (existing API suffices).
- `PostureDesk/Views/OnboardingView.swift` — `activateStep` layout updates.
- `PostureDesk/Views/MenuBarPopover.swift` — trial banner / trial-expired lock card.
- `PostureDesk/Views/Settings/SettingsView.swift` — license row CTAs.
- `PostureDesk/Info.plist` — new `PolarTrialCheckoutURL` key (both schemes).
- `project.yml` — surface the new Info.plist key (if managed there).
- `PostureDeskTests/LicenseManagerTests.swift` — new test cases.
- `PostureDeskTests/DeviceIdentityTests.swift` — new.

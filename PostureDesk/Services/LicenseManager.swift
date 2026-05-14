import AppKit
import Foundation

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

@Observable
final class LicenseManager {
    private static let offlineGracePeriod: TimeInterval = 7 * 24 * 60 * 60
    private static let licenseKeyAccount = "license-key"
    private static let activationIdAccount = "license-activation-id"
    private static let legacyLicenseKeyDefaultsKey = "licenseKey"
    private static let legacyActivationIdDefaultsKey = "licenseActivationId"
    private static let lastValidatedAtDefaultsKey = "licenseLastValidatedAt"
    private static let graceExpiresAtDefaultsKey = "licenseGraceExpiresAt"
    private static let cachedStatusDefaultsKey = "licenseCachedStatus"

    private(set) var isLicensed: Bool
    private(set) var isValidating: Bool = false
    private(set) var error: String?
    private(set) var licenseStatus: String?
    private(set) var licenseState: LicenseState

    private let config: Config
    private let keychain: KeychainStore
    private let session: URLSession

    init(
        bundle: Bundle = .main,
        keychain: KeychainStore = KeychainStore(),
        session: URLSession = .shared,
        config: Config? = nil
    ) {
        self.config = config ?? Config(bundle: bundle)
        self.keychain = keychain
        self.session = session

        Self.migrateUserDefaultsStoreIfNeeded(keychain: keychain)
        Self.migrateLegacyStorageIfNeeded(keychain: keychain)
        Self.bootstrapGracePeriodIfNeeded(keychain: keychain)

        let hasStoredLicense = keychain.string(for: Self.licenseKeyAccount) != nil
            && keychain.string(for: Self.activationIdAccount) != nil
        licenseStatus = UserDefaults.standard.string(forKey: Self.cachedStatusDefaultsKey)
        let initialState: LicenseState = hasStoredLicense ? Self.cachedLicenseState() : .unlicensed
        licenseState = initialState
        // Keep `isLicensed` consistent with `licenseState`: only true while we
        // either know the license is active or the offline-grace window covers us.
        switch initialState {
        case .active, .trialActive, .gracePeriod:
            isLicensed = true
        default:
            isLicensed = false
        }
    }

    // MARK: - Public

    func activate(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Please enter a license key."
            return
        }

        if let configurationError = config.validationError {
            error = configurationError
            licenseState = .configurationError
            return
        }

        isValidating = true
        licenseState = .validating
        error = nil

        do {
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
            licenseState = .active
            isLicensed = true
        } catch let LicenseError.api(message) {
            error = message
            licenseState = .invalid
        } catch let LicenseError.configuration(message) {
            error = message
            licenseState = .configurationError
        } catch let LicenseError.network(message) {
            error = message
            licenseState = .networkError
        } catch let LicenseError.serverTransient(message) {
            // Server reachable but unhealthy / parse failure. Surface a
            // network-error so the user can retry without losing input.
            error = message
            licenseState = .networkError
        } catch let urlError as URLError where Self.isOfflineURLError(urlError) {
            self.error = "Network error. Please check your connection and try again."
            licenseState = .networkError
        } catch {
            self.error = "Network error. Please check your connection and try again."
            licenseState = .networkError
        }

        isValidating = false
    }

    func refreshStatus() async {
        guard let key = storedLicenseKey(),
              let activationId = storedActivationId() else {
            isLicensed = false
            licenseState = .unlicensed
            licenseStatus = nil
            return
        }

        if let configurationError = config.validationError {
            applyValidationFailure(.configuration(configurationError))
            return
        }

        isValidating = true
        licenseState = .validating
        error = nil

        do {
            let result = try await validateKey(key, activationId: activationId)

            guard Self.isAccepted(status: result.status) else {
                // Order matters: drop `isLicensed` *before* invalidating
                // storage so observers never see a window where
                // `isLicensed == true && licenseState == .invalid`.
                isLicensed = false
                invalidateStoredLicense(message: "License is \(result.status).")
                isValidating = false
                return
            }

            recordSuccessfulValidation(status: result.status)
            licenseStatus = result.status
            licenseState = .active
            isLicensed = true
        } catch let failure as LicenseError {
            applyValidationFailure(failure)
        } catch let urlError as URLError where Self.isOfflineURLError(urlError) {
            // No network at all — let the offline-grace path keep the user
            // productive if it can.
            applyValidationFailure(.network("Unable to reach the license server right now."))
        } catch {
            // Some other transport error (TLS handshake, malformed response,
            // etc.). Treat as transient: do *not* extend offline grace and
            // do *not* invalidate credentials.
            applyValidationFailure(.serverTransient("Unable to validate your license right now."))
        }

        isValidating = false
    }

    func deactivate() async {
        guard let key = storedLicenseKey(),
              let activationId = storedActivationId() else {
            clearLicense()
            return
        }

        // If we can't even build a valid request (config error), wipe locally
        // — there is no server to confirm against from this build.
        guard config.validationError == nil else {
            clearLicense()
            return
        }

        let outcome = await performDeactivation(key: key, activationId: activationId)
        switch outcome {
        case .confirmed:
            clearLicense()
        case .clientErrorClearedLocally(let statusCode):
            #if DEBUG
            print("[LicenseManager] deactivate received unexpected client status \(statusCode); clearing local credentials anyway.")
            #endif
            clearLicense()
        case .retryable(let message):
            // Server didn't confirm — keep credentials so the user can retry.
            isValidating = false
            error = message
        }
    }

    private enum DeactivationOutcome {
        /// 2xx — server confirmed, or 404 — server says creds are gone.
        case confirmed
        /// Other 4xx. Server says creds are gone but in an unexpected way;
        /// we still clear locally but log so support can investigate.
        case clientErrorClearedLocally(Int)
        /// 5xx, transport failure, malformed response. Keep local creds so
        /// the user can retry once the server recovers.
        case retryable(String)
    }

    private func performDeactivation(key: String, activationId: String) async -> DeactivationOutcome {
        do {
            let request = try makeRequest(
                path: "deactivate",
                body: [
                    "key": key,
                    "organization_id": config.organizationId,
                    "activation_id": activationId
                ]
            )

            let (_, response) = try await session.data(for: request)
            let httpResponse = try requireHTTPResponse(response)
            let status = httpResponse.statusCode

            switch status {
            case 200...299, 404:
                return .confirmed
            case 500...599:
                return .retryable("License server is temporarily unavailable. Please try again.")
            case 400...499:
                return .clientErrorClearedLocally(status)
            default:
                return .retryable("Unexpected response from license server (\(status)). Please try again.")
            }
        } catch let urlError as URLError where Self.isOfflineURLError(urlError) {
            return .retryable("You appear to be offline. Connect and try again to deactivate.")
        } catch {
            return .retryable("Unable to reach the license server right now. Please try again.")
        }
    }

    func openCheckout() {
        guard config.validationError == nil, let url = config.checkoutPageURL else {
            error = config.validationError ?? "License checkout is not configured."
            licenseState = .configurationError
            return
        }

        NSWorkspace.shared.open(url)
    }

    var maskedKey: String? {
        guard let key = storedLicenseKey() else { return nil }
        if key.count > 8 {
            let suffix = String(key.suffix(8))
            return "••••••••-\(suffix)"
        }
        return key
    }

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

    // MARK: - Storage

    private func storedLicenseKey() -> String? {
        keychain.string(for: Self.licenseKeyAccount)
    }

    private func storedActivationId() -> String? {
        keychain.string(for: Self.activationIdAccount)
    }

    @discardableResult
    private func storeLicense(key: String, activationId: String) -> Bool {
        let storedKey = keychain.set(key, for: Self.licenseKeyAccount)
        let storedActivation = keychain.set(activationId, for: Self.activationIdAccount)

        guard storedKey,
              storedActivation,
              keychain.string(for: Self.licenseKeyAccount) == key,
              keychain.string(for: Self.activationIdAccount) == activationId else {
            keychain.removeValue(for: Self.licenseKeyAccount)
            keychain.removeValue(for: Self.activationIdAccount)
            return false
        }

        keychain.removeLegacyUserDefaultsValue(for: Self.licenseKeyAccount)
        keychain.removeLegacyUserDefaultsValue(for: Self.activationIdAccount)
        return true
    }

    private func clearLicense() {
        keychain.removeValue(for: Self.licenseKeyAccount)
        keychain.removeValue(for: Self.activationIdAccount)
        keychain.removeLegacyUserDefaultsValue(for: Self.licenseKeyAccount)
        keychain.removeLegacyUserDefaultsValue(for: Self.activationIdAccount)

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.lastValidatedAtDefaultsKey)
        defaults.removeObject(forKey: Self.graceExpiresAtDefaultsKey)
        defaults.removeObject(forKey: Self.cachedStatusDefaultsKey)
        defaults.removeObject(forKey: Self.legacyLicenseKeyDefaultsKey)
        defaults.removeObject(forKey: Self.legacyActivationIdDefaultsKey)

        isLicensed = false
        isValidating = false
        error = nil
        licenseStatus = nil
        licenseState = .unlicensed
    }

    // MARK: - API calls

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

        private static func value(for key: String, in bundle: Bundle) -> String? {
            (bundle.object(forInfoDictionaryKey: key) as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        private static func isSandboxHost(_ host: String?) -> Bool {
            host?.localizedCaseInsensitiveContains("sandbox") == true
        }

        private static var defaultRequiresProductionConfiguration: Bool {
            #if DEBUG
            false
            #else
            true
            #endif
        }
    }

    private struct ActivationResult {
        let activationId: String
        let status: String
    }

    private struct ValidationResult {
        let status: String
    }

    private enum LicenseError: Error {
        /// Server definitively rejected the request (4xx that's not 404 on
        /// deactivate). Causes the stored license to be invalidated locally.
        case api(String)
        /// True "no network" — URLSession failed before we ever reached the
        /// server. Lets the offline-grace window keep the user productive.
        case network(String)
        /// Server is reachable but transient (5xx, or 200 with malformed
        /// body). Surfaces a `.networkError` lock immediately and does *not*
        /// let the user lean on offline grace, but preserves credentials so
        /// the next `refreshStatus()` can recover.
        case serverTransient(String)
        case configuration(String)
    }

    private func activateKey(_ key: String) async throws -> ActivationResult {
        let request = try makeRequest(
            path: "activate",
            body: [
                "key": key,
                "organization_id": config.organizationId,
                "label": activationLabel()
            ]
        )

        let (data, response) = try await session.data(for: request)
        let httpResponse = try requireHTTPResponse(response)

        guard httpResponse.statusCode == 200 else {
            throw mapAPIError(data: data, statusCode: httpResponse.statusCode, fallback: "Activation failed. Please try again.")
        }

        let json = try decodeJSON(from: data)
        guard let id = json["id"] as? String else {
            // Treat as transient: server returned 200 but a body shape we
            // don't understand. Don't invalidate any stored credentials.
            throw LicenseError.serverTransient("Invalid response from server.")
        }

        let status = Self.extractStatus(from: json) ?? "granted"
        return ActivationResult(activationId: id, status: status)
    }

    private func validateKey(_ key: String, activationId: String) async throws -> ValidationResult {
        let request = try makeRequest(
            path: "validate",
            body: [
                "key": key,
                "organization_id": config.organizationId,
                "activation_id": activationId
            ]
        )

        let (data, response) = try await session.data(for: request)
        let httpResponse = try requireHTTPResponse(response)

        guard httpResponse.statusCode == 200 else {
            throw mapAPIError(data: data, statusCode: httpResponse.statusCode, fallback: "Unable to validate your license.")
        }

        let json = try decodeJSON(from: data)
        guard let status = Self.extractStatus(from: json) else {
            // Treat as transient: a malformed body on a 200 must not knock
            // the user out. Preserve credentials and let the next refresh
            // recover.
            throw LicenseError.serverTransient("Invalid response from server.")
        }

        return ValidationResult(status: status)
    }

    private func activationLabel() -> String {
        let host = Host.current().localizedName ?? "Mac"
        if let fingerprint = DeviceIdentity.shortHashedUUID() {
            return "\(host) · \(fingerprint)"
        }
        return host
    }

    private func makeRequest(path: String, body: [String: Any]) throws -> URLRequest {
        if let configurationError = config.validationError {
            throw LicenseError.configuration(configurationError)
        }

        guard let url = URL(string: "\(config.baseURL)/\(path)") else {
            throw LicenseError.configuration("License configuration is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func requireHTTPResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseError.network("Invalid server response.")
        }
        return httpResponse
    }

    private func decodeJSON(from data: Data) throws -> [String: Any] {
        // Called only on the 200 success path. A body that won't parse is a
        // transient server / network condition, not a license rejection.
        let raw = try? JSONSerialization.jsonObject(with: data)
        guard let json = raw as? [String: Any] else {
            throw LicenseError.serverTransient("Invalid response from server.")
        }
        return json
    }

    private func mapAPIError(data: Data, statusCode: Int, fallback: String) -> LicenseError {
        let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String

        switch statusCode {
        case 403:
            return .api("Activation limit reached for this license key.")
        case 404:
            return .api("License key not found. Please check and try again.")
        case 500...599:
            // Treat as transient: server is reachable but unhealthy. Don't
            // lean on offline-grace and don't invalidate credentials.
            return .serverTransient(detail ?? "License server unavailable.")
        default:
            return .api(detail ?? fallback)
        }
    }

    // MARK: - Validation State

    private func recordSuccessfulValidation(status: String) {
        let now = Date()
        let graceExpiry = now.addingTimeInterval(Self.offlineGracePeriod)

        let defaults = UserDefaults.standard
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Self.lastValidatedAtDefaultsKey)
        defaults.set(graceExpiry.timeIntervalSinceReferenceDate, forKey: Self.graceExpiresAtDefaultsKey)
        defaults.set(status, forKey: Self.cachedStatusDefaultsKey)

        isLicensed = true
        licenseStatus = status
    }

    private func invalidateStoredLicense(message: String) {
        clearLicense()
        error = message
        licenseState = .invalid
    }

    private func applyValidationFailure(_ failure: LicenseError) {
        switch failure {
        case .api(let message):
            // Server definitively rejected. Drop `isLicensed` *before*
            // invalidating storage so observers never see a window where
            // `isLicensed == true && licenseState == .invalid`.
            isLicensed = false
            invalidateStoredLicense(message: message)
        case .network(let message):
            // Pure no-network. Lean on the offline-grace cache if it's still
            // valid; otherwise lock the app behind a `.networkError`.
            if let graceExpiry = Self.cachedGraceExpiry(), graceExpiry > Date() {
                isLicensed = true
                licenseState = .gracePeriod(until: graceExpiry)
                error = nil
            } else {
                isLicensed = false
                licenseState = .networkError
                error = message
            }
        case .serverTransient(let message):
            // Server is reachable but unhealthy (5xx) or returned a body we
            // can't parse. Surface a `.networkError` lock immediately —
            // *without* extending or relying on offline grace, and without
            // touching stored credentials. Next refresh can recover.
            isLicensed = false
            licenseState = .networkError
            error = message
        case .configuration(let message):
            if let graceExpiry = Self.cachedGraceExpiry(), graceExpiry > Date() {
                isLicensed = true
                licenseState = .gracePeriod(until: graceExpiry)
                error = nil
            } else {
                isLicensed = false
                licenseState = .configurationError
                error = message
            }
        }
    }

    private static func cachedLicenseState() -> LicenseState {
        // We have stored credentials but have not yet re-validated since launch.
        // If the offline-grace window is still open and we have a recorded
        // last-validation timestamp, surface `.gracePeriod` so the UI reflects
        // the cached state; otherwise force a `.networkError` lock until the
        // next `refreshStatus()` either succeeds or definitively rejects.
        guard let graceExpiry = cachedGraceExpiry(),
              graceExpiry > Date(),
              lastValidatedAt() != nil else {
            return .networkError
        }
        return .gracePeriod(until: graceExpiry)
    }

    private static func lastValidatedAt() -> Date? {
        let value = UserDefaults.standard.double(forKey: lastValidatedAtDefaultsKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: value)
    }

    private static func cachedGraceExpiry() -> Date? {
        let value = UserDefaults.standard.double(forKey: graceExpiresAtDefaultsKey)
        guard value > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: value)
    }

    private static func migrateUserDefaultsStoreIfNeeded(keychain: KeychainStore) {
        guard keychain.string(for: licenseKeyAccount) == nil,
              keychain.string(for: activationIdAccount) == nil else { return }

        guard let storedKey = keychain.legacyUserDefaultsString(for: licenseKeyAccount),
              let storedActivationId = keychain.legacyUserDefaultsString(for: activationIdAccount) else {
            return
        }

        let storedKeyDidPersist = keychain.set(storedKey, for: licenseKeyAccount)
        let storedActivationDidPersist = keychain.set(storedActivationId, for: activationIdAccount)

        guard storedKeyDidPersist,
              storedActivationDidPersist,
              keychain.string(for: licenseKeyAccount) == storedKey,
              keychain.string(for: activationIdAccount) == storedActivationId else {
            keychain.removeValue(for: licenseKeyAccount)
            keychain.removeValue(for: activationIdAccount)
            return
        }

        keychain.removeLegacyUserDefaultsValue(for: licenseKeyAccount)
        keychain.removeLegacyUserDefaultsValue(for: activationIdAccount)
    }

    private static func migrateLegacyStorageIfNeeded(keychain: KeychainStore) {
        guard keychain.string(for: licenseKeyAccount) == nil,
              keychain.string(for: activationIdAccount) == nil else { return }

        let defaults = UserDefaults.standard
        guard let legacyKey = defaults.string(forKey: legacyLicenseKeyDefaultsKey),
              let legacyActivationId = defaults.string(forKey: legacyActivationIdDefaultsKey) else {
            return
        }

        let storedLegacyKey = keychain.set(legacyKey, for: licenseKeyAccount)
        let storedLegacyActivation = keychain.set(legacyActivationId, for: activationIdAccount)

        guard storedLegacyKey,
              storedLegacyActivation,
              keychain.string(for: licenseKeyAccount) == legacyKey,
              keychain.string(for: activationIdAccount) == legacyActivationId else {
            keychain.removeValue(for: licenseKeyAccount)
            keychain.removeValue(for: activationIdAccount)
            return
        }

        defaults.removeObject(forKey: legacyLicenseKeyDefaultsKey)
        defaults.removeObject(forKey: legacyActivationIdDefaultsKey)
    }

    private static func bootstrapGracePeriodIfNeeded(keychain: KeychainStore) {
        guard keychain.string(for: licenseKeyAccount) != nil,
              keychain.string(for: activationIdAccount) != nil,
              cachedGraceExpiry() == nil else {
            return
        }

        // Treat the migration moment as the implicit last-validation time so
        // that `cachedLicenseState()` (which requires both a future grace
        // expiry *and* a non-nil last-validated timestamp per L1) can lift
        // the user into `.gracePeriod` immediately. The next `refreshStatus`
        // will overwrite both with real values.
        let now = Date()
        let graceExpiry = now.addingTimeInterval(offlineGracePeriod)
        let defaults = UserDefaults.standard
        defaults.set(graceExpiry.timeIntervalSinceReferenceDate, forKey: graceExpiresAtDefaultsKey)
        if defaults.double(forKey: lastValidatedAtDefaultsKey) <= 0 {
            defaults.set(now.timeIntervalSinceReferenceDate, forKey: lastValidatedAtDefaultsKey)
        }
    }

    private static func extractStatus(from json: [String: Any]) -> String? {
        if let status = json["status"] as? String {
            return status
        }

        if let licenseKey = json["license_key"] as? [String: Any],
           let status = licenseKey["status"] as? String {
            return status
        }

        return nil
    }

    private static func isAccepted(status: String) -> Bool {
        !["blocked", "disabled", "expired", "revoked"].contains(status.lowercased())
    }

    /// `URLError` codes that indicate the request never reached a healthy
    /// server, so leaning on the offline-grace cache is appropriate.
    /// Anything else (TLS errors, bad responses, etc.) is treated as a
    /// transient server failure and bypasses the grace path.
    private static func isOfflineURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut:
            return true
        default:
            return false
        }
    }
}

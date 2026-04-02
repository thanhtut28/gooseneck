import AppKit
import Foundation

enum LicenseState: Equatable {
    case unlicensed
    case validating
    case active
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
        isLicensed = hasStoredLicense
        licenseStatus = UserDefaults.standard.string(forKey: Self.cachedStatusDefaultsKey)
        licenseState = hasStoredLicense ? Self.cachedLicenseState() : .unlicensed
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
        } catch {
            applyValidationFailure(.network("Unable to validate your license right now."))
        }

        isValidating = false
    }

    func deactivate() async {
        guard let key = storedLicenseKey(),
              let activationId = storedActivationId() else {
            clearLicense()
            return
        }

        if config.validationError == nil {
            do {
                try await deactivateKey(key, activationId: activationId)
            } catch {
                // Local deactivation still wins.
            }
        }

        clearLicense()
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
        let baseURL: String
        let requiresProductionConfiguration: Bool

        init(
            organizationId: String,
            checkoutURL: String,
            baseURL: String,
            requiresProductionConfiguration: Bool = false
        ) {
            self.organizationId = organizationId
            self.checkoutURL = checkoutURL
            self.baseURL = baseURL
            self.requiresProductionConfiguration = requiresProductionConfiguration
        }

        init(bundle: Bundle) {
            self.init(
                organizationId: Self.value(for: "PolarOrganizationID", in: bundle) ?? "322cca40-cd2e-4d58-83e9-ec08ee2b0c19",
                checkoutURL: Self.value(for: "PolarCheckoutURL", in: bundle) ?? "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_DOGu45YJUcHzeFxGZw5EqT0L9gN3L9Qm2dTQn2Z4xHn/redirect",
                baseURL: Self.value(for: "PolarAPIBaseURL", in: bundle) ?? "https://sandbox-api.polar.sh/v1/customer-portal/license-keys",
                requiresProductionConfiguration: Self.defaultRequiresProductionConfiguration
            )
        }

        var checkoutPageURL: URL? {
            URL(string: checkoutURL)
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
        case api(String)
        case network(String)
        case configuration(String)
    }

    private func activateKey(_ key: String) async throws -> ActivationResult {
        let request = try makeRequest(
            path: "activate",
            body: [
                "key": key,
                "organization_id": config.organizationId,
                "label": Host.current().localizedName ?? "Mac"
            ]
        )

        let (data, response) = try await session.data(for: request)
        let httpResponse = try requireHTTPResponse(response)

        guard httpResponse.statusCode == 200 else {
            throw mapAPIError(data: data, statusCode: httpResponse.statusCode, fallback: "Activation failed. Please try again.")
        }

        let json = try decodeJSON(from: data)
        guard let id = json["id"] as? String else {
            throw LicenseError.api("Invalid response from server.")
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
            throw LicenseError.api("Invalid response from server.")
        }

        return ValidationResult(status: status)
    }

    private func deactivateKey(_ key: String, activationId: String) async throws {
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

        if httpResponse.statusCode != 204 {
            throw LicenseError.api("Failed to deactivate license.")
        }
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
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LicenseError.api("Invalid response from server.")
        }
        return json
    }

    private func mapAPIError(data: Data, statusCode: Int, fallback: String) -> LicenseError {
        let detail = (try? decodeJSON(from: data))?["detail"] as? String

        switch statusCode {
        case 403:
            return .api("Activation limit reached for this license key.")
        case 404:
            return .api("License key not found. Please check and try again.")
        case 500...599:
            return .network(detail ?? "License server unavailable.")
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
            invalidateStoredLicense(message: message)
        case .network(let message):
            if let graceExpiry = Self.cachedGraceExpiry(), graceExpiry > Date() {
                isLicensed = true
                licenseState = .gracePeriod(until: graceExpiry)
                error = nil
            } else {
                isLicensed = false
                licenseState = .networkError
                error = message
            }
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
        if let graceExpiry = cachedGraceExpiry(), graceExpiry > Date(), lastValidatedAt() != nil {
            return .active
        }
        return .active
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

        let graceExpiry = Date().addingTimeInterval(offlineGracePeriod)
        UserDefaults.standard.set(graceExpiry.timeIntervalSinceReferenceDate, forKey: graceExpiresAtDefaultsKey)
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
}

import AppKit
import Foundation

@Observable
final class LicenseManager {
    private(set) var isLicensed: Bool
    private(set) var isValidating: Bool = false
    private(set) var error: String?
    private(set) var licenseStatus: String?

    // MARK: - Polar config (replace with your actual values)

    private let organizationId = "322cca40-cd2e-4d58-83e9-ec08ee2b0c19"
    private let checkoutURL = "https://sandbox-api.polar.sh/v1/checkout-links/polar_cl_DOGu45YJUcHzeFxGZw5EqT0L9gN3L9Qm2dTQn2Z4xHn/redirect"

    // MARK: - Polar API
    // Switch to "https://api.polar.sh/..." for production

    private let baseURL = "https://sandbox-api.polar.sh/v1/customer-portal/license-keys"

    init() {
        isLicensed = Self.storedLicenseKey() != nil && Self.storedActivationId() != nil
    }

    // MARK: - Public

    func activate(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error = "Please enter a license key."
            return
        }

        isValidating = true
        error = nil

        do {
            let result = try await activateKey(trimmed)
            Self.storeLicense(key: trimmed, activationId: result.activationId)
            licenseStatus = result.status
            isLicensed = true
        } catch let LicenseError.api(message) {
            error = message
        } catch {
            self.error = "Network error. Please check your connection and try again."
        }

        isValidating = false
    }

    func deactivate() async {
        guard let key = Self.storedLicenseKey(),
              let activationId = Self.storedActivationId() else {
            Self.clearLicense()
            isLicensed = false
            return
        }

        do {
            try await deactivateKey(key, activationId: activationId)
        } catch {
            // Deactivate locally even if API fails
        }

        Self.clearLicense()
        isLicensed = false
        licenseStatus = nil
    }

    func openCheckout() {
        guard let url = URL(string: checkoutURL) else { return }
        NSWorkspace.shared.open(url)
    }

    var maskedKey: String? {
        guard let key = Self.storedLicenseKey() else { return nil }
        if key.count > 8 {
            let suffix = String(key.suffix(8))
            return "••••••••-\(suffix)"
        }
        return key
    }

    // MARK: - Storage

    static func storedLicenseKey() -> String? {
        UserDefaults.standard.string(forKey: "licenseKey")
    }

    private static func storedActivationId() -> String? {
        UserDefaults.standard.string(forKey: "licenseActivationId")
    }

    private static func storeLicense(key: String, activationId: String) {
        UserDefaults.standard.set(key, forKey: "licenseKey")
        UserDefaults.standard.set(activationId, forKey: "licenseActivationId")
    }

    static func clearLicense() {
        UserDefaults.standard.removeObject(forKey: "licenseKey")
        UserDefaults.standard.removeObject(forKey: "licenseActivationId")
    }

    // MARK: - API calls

    private struct ActivationResult {
        let activationId: String
        let status: String
    }

    private enum LicenseError: Error {
        case api(String)
    }

    private func activateKey(_ key: String) async throws -> ActivationResult {
        let url = URL(string: "\(baseURL)/activate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "key": key,
            "organization_id": organizationId,
            "label": Host.current().localizedName ?? "Mac"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode == 200 {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let id = json?["id"] as? String else {
                throw LicenseError.api("Invalid response from server.")
            }
            let licenseKey = json?["license_key"] as? [String: Any]
            let status = licenseKey?["status"] as? String ?? "granted"
            return ActivationResult(activationId: id, status: status)
        }

        // Error handling
        if httpResponse.statusCode == 404 {
            throw LicenseError.api("License key not found. Please check and try again.")
        }
        if httpResponse.statusCode == 403 {
            throw LicenseError.api("Activation limit reached for this license key.")
        }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let detail = json?["detail"] as? String ?? "Activation failed. Please try again."
        throw LicenseError.api(detail)
    }

    private func deactivateKey(_ key: String, activationId: String) async throws {
        let url = URL(string: "\(baseURL)/deactivate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "key": key,
            "organization_id": organizationId,
            "activation_id": activationId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse

        if httpResponse.statusCode != 204 {
            throw LicenseError.api("Failed to deactivate license.")
        }
    }
}

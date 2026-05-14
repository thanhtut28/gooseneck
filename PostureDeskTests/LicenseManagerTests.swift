import Foundation
import XCTest
@testable import GooseNeck

@MainActor
final class LicenseManagerTests: XCTestCase {
    private let cachedStatusKey = "licenseCachedStatus"
    private let graceExpiresAtKey = "licenseGraceExpiresAt"
    private let lastValidatedAtKey = "licenseLastValidatedAt"
    private let legacyLicenseKeyKey = "licenseKey"
    private let legacyActivationIdKey = "licenseActivationId"

    private var keychains: [KeychainStore] = []
    private var userDefaultsShimKeys: [String] = []

    override func tearDown() {
        MockURLProtocol.requestHandler = nil

        for keychain in keychains {
            keychain.removeValue(for: "license-key")
            keychain.removeValue(for: "license-activation-id")
        }
        keychains.removeAll()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: cachedStatusKey)
        defaults.removeObject(forKey: graceExpiresAtKey)
        defaults.removeObject(forKey: lastValidatedAtKey)
        defaults.removeObject(forKey: legacyLicenseKeyKey)
        defaults.removeObject(forKey: legacyActivationIdKey)
        for key in userDefaultsShimKeys {
            defaults.removeObject(forKey: key)
        }
        userDefaultsShimKeys.removeAll()

        super.tearDown()
    }

    func testKeychainStoreRoundTripsGenericPasswordValues() {
        let (keychain, _) = makeStandaloneKeychain()

        XCTAssertTrue(keychain.set("stored-license", for: "license-key"))
        XCTAssertEqual(keychain.string(for: "license-key"), "stored-license")
        XCTAssertTrue(keychain.removeValue(for: "license-key"))
        XCTAssertNil(keychain.string(for: "license-key"))
    }

    func testActivateStoresLicenseAndSetsActiveState() async {
        let licenseKey = "license-key-ABCDEFGH"
        let (manager, keychain) = makeManager { request in
            XCTAssertEqual(request.url?.lastPathComponent, "activate")
            return (
                self.httpResponse(url: request.url!, statusCode: 200),
                self.json([
                    "id": "act_123",
                    "status": "granted"
                ])
            )
        }

        await manager.activate(key: licenseKey)

        XCTAssertTrue(manager.isLicensed)
        XCTAssertEqual(manager.licenseState, .active)
        XCTAssertEqual(keychain.string(for: "license-key"), licenseKey)
        XCTAssertEqual(keychain.string(for: "license-activation-id"), "act_123")
    }

    func testRefreshStatusAcceptsValidStatus() async {
        let (manager, keychain) = makeManager { request in
            XCTAssertEqual(request.url?.lastPathComponent, "validate")
            return (
                self.httpResponse(url: request.url!, statusCode: 200),
                self.json(["status": "granted"])
            )
        }
        keychain.set("stored-license", for: "license-key")
        keychain.set("act_999", for: "license-activation-id")

        await manager.refreshStatus()

        XCTAssertTrue(manager.isLicensed)
        XCTAssertEqual(manager.licenseState, .active)
        XCTAssertEqual(manager.licenseStatus, "granted")
    }

    func testRefreshStatusMarksRevokedLicenseInvalid() async {
        let (manager, keychain) = makeManager { request in
            XCTAssertEqual(request.url?.lastPathComponent, "validate")
            return (
                self.httpResponse(url: request.url!, statusCode: 200),
                self.json(["status": "revoked"])
            )
        }
        keychain.set("stored-license", for: "license-key")
        keychain.set("act_999", for: "license-activation-id")

        await manager.refreshStatus()

        XCTAssertFalse(manager.isLicensed)
        XCTAssertEqual(manager.licenseState, .invalid)
        XCTAssertEqual(manager.error, "License is revoked.")
        XCTAssertNil(keychain.string(for: "license-key"))
        XCTAssertNil(keychain.string(for: "license-activation-id"))
    }

    func testRefreshStatusUsesGracePeriodOnNetworkFailure() async {
        let (manager, keychain) = makeManager { _ in
            throw URLError(.notConnectedToInternet)
        }
        keychain.set("stored-license", for: "license-key")
        keychain.set("act_999", for: "license-activation-id")
        UserDefaults.standard.set(
            Date().addingTimeInterval(300).timeIntervalSinceReferenceDate,
            forKey: graceExpiresAtKey
        )

        await manager.refreshStatus()

        XCTAssertTrue(manager.isLicensed)
        switch manager.licenseState {
        case .gracePeriod(let until):
            XCTAssertGreaterThan(until, Date())
        default:
            XCTFail("Expected grace period state, got \(manager.licenseState)")
        }
    }

    func testActivateHandlesNonHTTPResponseAsNetworkError() async {
        let (manager, _) = makeManager { request in
            let response = URLResponse(
                url: request.url!,
                mimeType: "application/json",
                expectedContentLength: 0,
                textEncodingName: nil
            )
            return (response, Data())
        }

        await manager.activate(key: "license-key-ABCDEFGH")

        XCTAssertFalse(manager.isLicensed)
        XCTAssertEqual(manager.licenseState, .networkError)
        XCTAssertEqual(manager.error, "Invalid server response.")
    }

    func testStrictConfigRejectsSandboxReleaseConfig() async {
        let config = LicenseManager.Config(
            organizationId: "org_123",
            checkoutURL: "https://sandbox-api.polar.sh/v1/checkout-links/test/redirect",
            baseURL: "https://sandbox-api.polar.sh/v1/customer-portal/license-keys",
            requiresProductionConfiguration: true
        )
        let (manager, _) = makeManager(config: config) { _ in
            XCTFail("Network should not be called for invalid release configuration.")
            throw URLError(.badURL)
        }

        await manager.activate(key: "license-key-ABCDEFGH")

        XCTAssertEqual(manager.licenseState, .configurationError)
        XCTAssertEqual(manager.error, "Release build cannot use a sandbox Polar API URL.")
    }

    func testInitMigratesUserDefaultsShimIntoKeychain() {
        let (keychain, service) = makeStandaloneKeychain()
        let licenseKey = service + ".license-key"
        let activationKey = service + ".license-activation-id"
        UserDefaults.standard.set("shim-license", forKey: licenseKey)
        UserDefaults.standard.set("shim-activation", forKey: activationKey)

        let manager = LicenseManager(
            keychain: keychain,
            session: makeSession(),
            config: .init(
                organizationId: "org_123",
                checkoutURL: "https://polar.sh/checkout",
                baseURL: "https://api.polar.sh/v1/customer-portal/license-keys"
            )
        )

        XCTAssertTrue(manager.isLicensed)
        XCTAssertEqual(keychain.string(for: "license-key"), "shim-license")
        XCTAssertEqual(keychain.string(for: "license-activation-id"), "shim-activation")
        XCTAssertNil(UserDefaults.standard.string(forKey: licenseKey))
        XCTAssertNil(UserDefaults.standard.string(forKey: activationKey))
    }

    func testInitDoesNotOverrideExistingKeychainValuesDuringShimMigration() {
        let (keychain, service) = makeStandaloneKeychain()
        XCTAssertTrue(keychain.set("keychain-license", for: "license-key"))
        XCTAssertTrue(keychain.set("keychain-activation", for: "license-activation-id"))

        let licenseKey = service + ".license-key"
        let activationKey = service + ".license-activation-id"
        UserDefaults.standard.set("shim-license", forKey: licenseKey)
        UserDefaults.standard.set("shim-activation", forKey: activationKey)

        let manager = LicenseManager(
            keychain: keychain,
            session: makeSession(),
            config: .init(
                organizationId: "org_123",
                checkoutURL: "https://polar.sh/checkout",
                baseURL: "https://api.polar.sh/v1/customer-portal/license-keys"
            )
        )

        XCTAssertTrue(manager.isLicensed)
        XCTAssertEqual(keychain.string(for: "license-key"), "keychain-license")
        XCTAssertEqual(keychain.string(for: "license-activation-id"), "keychain-activation")
        XCTAssertEqual(UserDefaults.standard.string(forKey: licenseKey), "shim-license")
        XCTAssertEqual(UserDefaults.standard.string(forKey: activationKey), "shim-activation")
    }

    func testConfigTrialCheckoutPageURLIsNilWhenStringEmpty() {
        let config = LicenseManager.Config(
            organizationId: "org_123",
            checkoutURL: "https://polar.sh/checkout",
            trialCheckoutURL: "",
            baseURL: "https://api.polar.sh/v1/customer-portal/license-keys"
        )
        XCTAssertNil(config.trialCheckoutPageURL)
    }

    func testConfigTrialCheckoutPageURLParsesNonEmptyString() {
        let config = LicenseManager.Config(
            organizationId: "org_123",
            checkoutURL: "https://polar.sh/checkout",
            trialCheckoutURL: "https://buy.polar.sh/polar_cl_TRIAL",
            baseURL: "https://api.polar.sh/v1/customer-portal/license-keys"
        )
        XCTAssertEqual(config.trialCheckoutPageURL?.absoluteString, "https://buy.polar.sh/polar_cl_TRIAL")
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

    private func makeManager(
        config: LicenseManager.Config = .init(
            organizationId: "org_123",
            checkoutURL: "https://polar.sh/checkout",
            baseURL: "https://api.polar.sh/v1/customer-portal/license-keys"
        ),
        handler: @escaping (URLRequest) throws -> (URLResponse, Data)
    ) -> (LicenseManager, KeychainStore) {
        let (keychain, _) = makeStandaloneKeychain()
        MockURLProtocol.requestHandler = handler

        return (
            LicenseManager(
                keychain: keychain,
                session: makeSession(withMockProtocol: true),
                config: config
            ),
            keychain
        )
    }

    private func makeStandaloneKeychain() -> (KeychainStore, String) {
        let service = "com.posturedesk.tests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: service)
        keychains.append(keychain)
        userDefaultsShimKeys.append(service + ".license-key")
        userDefaultsShimKeys.append(service + ".license-activation-id")
        return (keychain, service)
    }

    private func makeSession(withMockProtocol: Bool = false) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        if withMockProtocol {
            configuration.protocolClasses = [MockURLProtocol.self]
        }
        return URLSession(configuration: configuration)
    }

    private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

    private func json(_ object: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var requestHandler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("Missing request handler.")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

import Foundation
import Security

/// macOS Keychain-backed credential store using standard generic password items.
/// This intentionally avoids the data protection keychain path so it also works
/// in local ad-hoc builds.
struct KeychainStore {
    private let service: String

    init(service: String = "\(Bundle.main.bundleIdentifier ?? "com.gooseneck.app").license") {
        self.service = service
    }

    func string(for account: String) -> String? {
        guard let data = data(for: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func set(_ value: String, for account: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        return set(data, for: account)
    }

    @discardableResult
    func removeValue(for account: String) -> Bool {
        let status = SecItemDelete(query(for: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            Self.logFailure("delete", status: status, account: account, service: service)
            return false
        }
        return true
    }

    func legacyUserDefaultsString(for account: String) -> String? {
        UserDefaults.standard.string(forKey: legacyUserDefaultsKey(for: account))
    }

    func removeLegacyUserDefaultsValue(for account: String) {
        UserDefaults.standard.removeObject(forKey: legacyUserDefaultsKey(for: account))
    }

    private func data(for account: String) -> Data? {
        var query = query(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            Self.logFailure("read", status: status, account: account, service: service)
            return nil
        }
    }

    private func set(_ data: Data, for account: String) -> Bool {
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query(for: account) as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        if updateStatus != errSecItemNotFound {
            Self.logFailure("update", status: updateStatus, account: account, service: service)
            return false
        }

        var newItem = query(for: account)
        newItem[kSecValueData as String] = data
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            Self.logFailure("add", status: addStatus, account: account, service: service)
            return false
        }

        return true
    }

    private func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func legacyUserDefaultsKey(for account: String) -> String {
        service + "." + account
    }

    private static func logFailure(_ operation: String, status: OSStatus, account: String, service: String) {
        #if DEBUG
        print("[KeychainStore] \(operation) failed for \(service)/\(account): \(status)")
        #endif
    }
}

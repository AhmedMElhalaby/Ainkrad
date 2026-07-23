import Foundation
import Security
import AinkradHostRuntime

/// `SecretStore` backed by the macOS Keychain (generic password items).
/// Each secret is one item keyed by `(service, account=id)`.
final class KeychainSecretStore: SecretStore {
    private let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "com.ainkrad.app") {
        self.service = service
    }

    private func baseQuery(for id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
        ]
    }

    func secret(for id: String) -> String? {
        var query = baseQuery(for: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            if status != errSecSuccess && status != errSecItemNotFound {
                Log.persistence.error("Keychain read failed for \(id, privacy: .public): \(status)")
            }
            return nil
        }
        return value
    }

    func setSecret(_ value: String?, for id: String) {
        guard let value else {
            SecItemDelete(baseQuery(for: id) as CFDictionary)
            return
        }
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery(for: id) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var insert = baseQuery(for: id)
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            if addStatus != errSecSuccess {
                Log.persistence.error("Keychain add failed for \(id, privacy: .public): \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            Log.persistence.error("Keychain update failed for \(id, privacy: .public): \(updateStatus)")
        }
    }
}

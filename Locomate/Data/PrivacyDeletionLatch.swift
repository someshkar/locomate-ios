import Foundation
import Security

/// Separate from session credentials and erased files, so interrupted deletion cannot resume uploads.
public enum PrivacyDeletionLatch {
    public static var isPending: Bool { PrivacyDeletionMarker().isPending }
    static func begin() throws { try PrivacyDeletionMarker().begin() }
    static func finish() -> Bool { PrivacyDeletionMarker().finish() }
}

struct PrivacyDeletionMarker {
    var account = "pending-installation-deletion"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.locomate.app.privacy-deletion",
         kSecAttrAccount as String: account]
    }
    var isPending: Bool {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        // An unavailable Keychain must not be interpreted as permission to resume uploads.
        return SecItemCopyMatching(request as CFDictionary, &result) != errSecItemNotFound
    }
    func begin() throws {
        var request = query
        request[kSecValueData as String] = Data([1])
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(request as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw APIError(status: 0, code: "privacy_marker_unavailable", requestId: "", retryable: true,
                message: "Could not save the deletion request securely. Unlock the device and try again.")
        }
    }
    func finish() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

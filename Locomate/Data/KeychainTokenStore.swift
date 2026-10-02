//
//  KeychainTokenStore.swift
//  Locomate
//
//  Auth session persistence in the Keychain — the native equivalent of the RN
//  SecureStore token store (`src/auth/tokenStore.native.ts`).
//

import Foundation
import Security

public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    private let service: String
    private let account: String

    public init(service: String = "com.locomate.app.session", account: String = "rail-session") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let attributes = item as? [String: Any] else { return nil }
        guard let accessibility = attributes[kSecAttrAccessible as String] as? String,
              accessibility == (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String),
              let data = attributes[kSecValueData as String] as? Data else {
            // Old builds created migratable sessions; force a fresh device
            // registration rather than reusing one restored from a backup.
            clear()
            return nil
        }
        return try? JSONDecoder.locomote.decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        SecItemDelete(baseQuery as CFDictionary)
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    public static func clearAllSessions() -> Bool {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.locomate.app.session",
        ] as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    public enum KeychainError: Error { case saveFailed(OSStatus) }
}

/// In-memory store for previews and tests.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private var session: AuthSession?
    public init(session: AuthSession? = nil) { self.session = session }
    public func load() -> AuthSession? { session }
    public func save(_ session: AuthSession) throws { self.session = session }
    public func clear() { session = nil }
}

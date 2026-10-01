//
//  Services.swift
//  Locomate
//
//  Dependency container injected through the environment.
//

import SwiftUI
import Security

@MainActor
public final class LocomoteServices {
    public let railService: RailServiceProtocol?
    public let cache: JourneyCache
    public let passport: PassportRepository
    public let contribution: ContributionService
    public let mode: RailDataMode

    public init(
        railService: RailServiceProtocol?,
        cache: JourneyCache,
        passport: PassportRepository,
        contribution: ContributionService = ContributionService(),
        mode: RailDataMode
    ) {
        self.railService = railService
        self.cache = cache
        self.passport = passport
        self.contribution = contribution
        self.mode = mode
    }

    public static func live() -> LocomoteServices {
        let mode = RailDataMode.resolve()
        switch mode {
        case .preview:
            return LocomoteServices(
                railService: nil,
                cache: JourneyCache(),
                passport: PassportRepository(),
                mode: mode
            )
        case .production(let baseURL):
            let installationId = InstallationIdentity.current()
            let scope = RailStorageScope.gateway(baseURL)
            let client = APIClient(
                baseURL: baseURL,
                tokenStore: KeychainTokenStore(account: "rail-session-\(scope)"),
                installationId: installationId
            )
            return LocomoteServices(
                railService: RailService(client: client),
                cache: JourneyCache(scope: scope),
                passport: PassportRepository(scope: scope),
                mode: mode
            )
        }
    }
}

/// Stable on this device. A restored backup starts a new gateway installation.
enum InstallationIdentity {
    private static let fallback = UUID().uuidString
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.locomate.app.installation",
            kSecAttrAccount as String: "installation-id",
        ]
    }

    static func current() -> String {
        // Earlier builds used backed-up preferences. Do not carry that value
        // into the installation's device-only identity.
        UserDefaults.standard.removeObject(forKey: "locomote.installationId")
        if let existing = load() { return existing }
        let generated = UUID().uuidString
        var query = baseQuery
        query[kSecValueData as String] = Data(generated.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(query as CFDictionary, nil) == errSecSuccess { return generated }
        return load() ?? fallback
    }

    private static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct LocomoteServicesKey: EnvironmentKey {
    static var defaultValue: LocomoteServices {
        MainActor.assumeIsolated { LocomoteServices.live() }
    }
}

public extension EnvironmentValues {
    var locomoteServices: LocomoteServices {
        get { self[LocomoteServicesKey.self] }
        set { self[LocomoteServicesKey.self] = newValue }
    }
}

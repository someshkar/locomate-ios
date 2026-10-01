//
//  Services.swift
//  Locomate
//
//  Dependency container injected through the environment.
//

import SwiftUI

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

/// Stable per-install identifier (hashed by the gateway, never sent raw as PII).
enum InstallationIdentity {
    private static let key = "locomote.installationId"

    static func current() -> String {
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let generated = UUID().uuidString
        UserDefaults.standard.set(generated, forKey: key)
        return generated
    }
}

private struct LocomoteServicesKey: @preconcurrency EnvironmentKey {
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

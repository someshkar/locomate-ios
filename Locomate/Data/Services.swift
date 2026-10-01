//
//  Services.swift
//  Locomate
//
//  Dependency container injected through the environment.
//

import SwiftUI
import Security
import UserNotifications

@MainActor
public final class LocomoteServices {
    public enum ContributionConsentError: Error { case gatewayRequired }
    public let railService: RailServiceProtocol?
    public let cache: JourneyCache
    public let passport: PassportRepository
    public let contribution: ContributionService
    public let liveActivity: LiveActivityService
    public let journeyAlerts: JourneyAlertService
    public let mode: RailDataMode

    public init(
        railService: RailServiceProtocol?,
        cache: JourneyCache,
        passport: PassportRepository,
        contribution: ContributionService = ContributionService(),
        liveActivity: LiveActivityService = LiveActivityService(),
        mode: RailDataMode,
        journeyAlerts: JourneyAlertService? = nil
    ) {
        self.railService = railService
        self.cache = cache
        self.passport = passport
        self.contribution = contribution
        self.liveActivity = liveActivity
        self.mode = mode
        let alertScope: String
        if case .production(let baseURL) = mode { alertScope = RailStorageScope.gateway(baseURL) }
        else { alertScope = "preview" }
        self.journeyAlerts = journeyAlerts ?? JourneyAlertService(api: railService, scope: alertScope)
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
                contribution: ContributionService(scope: scope),
                mode: mode
            )
        }
    }

    public func grantContributionConsent(preferences: Preferences) async throws {
        guard let railService else { throw ContributionConsentError.gatewayRequired }
        try await contribution.flushConsentEvidence(using: railService)
        try await railService.recordCommunityConsent(CommunityConsentEvidence(granted: true))
        preferences.contributionsEnabled = true
    }

    @discardableResult
    public func revokeContributionConsent(preferences: Preferences) -> Bool {
        preferences.contributionsEnabled = false
        preferences.backgroundLocationEnabled = false
        contribution.revoke()
        do {
            try contribution.queueWithdrawal()
            return true
        } catch {
            return false
        }
    }

    public func flushPendingConsentEvidence() async throws {
        try await contribution.flushConsentEvidence(using: railService)
    }

    /// The export keeps the gateway's exact schema and every local data-source
    /// scope, including Passport, pending observations, and cached run/plan files.
    public func exportPrivacyData(preferences: Preferences) async throws -> URL {
        let gatewayExport: Any
        if let railService {
            gatewayExport = try JSONSerialization.jsonObject(with: try await railService.exportPrivacyData())
        } else {
            gatewayExport = NSNull()
        }
        let saved = try JSONSerialization.jsonObject(with: JSONEncoder.locomote.encode(await passport.load()))
        let queued = try JSONSerialization.jsonObject(with: JSONEncoder.locomote.encode(
            contribution.pendingBatch(limit: Int.max)))
        let archive: [String: Any] = [
            "schemaVersion": 1,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "gateway": gatewayExport,
            "local": [
                "passport": saved,
                "pendingObservations": queued,
                "localFilesBase64": try Self.exportLocalFilesBase64(),
                "preferences": [
                    "dark": preferences.dark,
                    "mapLighting": preferences.mapLighting.rawValue,
                    "contributionsEnabled": preferences.contributionsEnabled,
                    "backgroundLocationEnabled": preferences.backgroundLocationEnabled,
                ] as [String: Any],
            ] as [String: Any],
        ]
        let data = try JSONSerialization.data(withJSONObject: archive, options: [.prettyPrinted, .sortedKeys])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("locomote-exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        excludeFromBackup(folder)
        let file = folder.appendingPathComponent("locomote-data-\(UUID().uuidString).json")
        try data.write(to: file, options: .atomic)
        excludeFromBackup(file)
        return file
    }

    static func exportLocalFilesBase64(documentRoot: URL? = nil, cacheRoot: URL? = nil) throws -> [String: String] {
        let manager = FileManager.default
        let roots = [
            ("Documents", documentRoot ?? manager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("locomote", isDirectory: true)),
            ("Caches", cacheRoot ?? manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("locomote", isDirectory: true)),
        ]
        var files: [String: String] = [:]
        for (label, root) in roots where manager.fileExists(atPath: root.path) {
            for relative in try manager.subpathsOfDirectory(atPath: root.path) {
                let file = root.appendingPathComponent(relative)
                var isDirectory: ObjCBool = false
                guard manager.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                    continue
                }
                files["\(label)/locomote/\(relative)"] = try Data(contentsOf: file).base64EncodedString()
            }
        }
        return files
    }

    /// Delete the server installation first, then erase every local data-source
    /// scope and rotate the device identity. Appearance preferences are retained.
    /// A false result means the server succeeded but local erasure was partial.
    public func deletePrivacyData(preferences: Preferences) async throws -> Bool {
        // Stop the token observer before the server deletion can invalidate its session.
        await journeyAlerts.beginPrivacyDeletion()
        await liveActivity.beginPrivacyDeletion()
        do {
            try await railService?.deletePrivacyData()
        } catch {
            journeyAlerts.restoreAfterPrivacyDeletion()
            liveActivity.restoreAfterPrivacyDeletion()
            throw error
        }
        contribution.revoke()
        JourneyAlertPushBridge.shared.pendingPayload = nil
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        preferences.contributionsEnabled = false
        preferences.backgroundLocationEnabled = false
        let manager = FileManager.default
        let roots = [
            manager.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("locomote"),
            manager.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("locomote"),
            manager.temporaryDirectory.appendingPathComponent("locomote-exports"),
        ]
        var complete = true
        for root in roots where manager.fileExists(atPath: root.path) {
            do { try manager.removeItem(at: root) } catch { complete = false }
        }
        let sessionsCleared = KeychainTokenStore.clearAllSessions()
        let identityCleared = InstallationIdentity.clear()
        return complete && sessionsCleared && identityCleared
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

    static func clear() -> Bool {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
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

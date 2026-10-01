import Foundation
import Observation
import CryptoKit

public enum JourneyAlertConsent {
    public static let version = "journey-alerts-v1"
    public static let noticeHash = "025a174cd8ee918c5bab69cf42d5d497128a0493a33631e5582b78dd361e2250"
    public static let notice = "Journey alerts send this device's push token, selected train runs, alert channels, and quiet hours to Locomate's gateway. The gateway uses fresh rail updates to send notifications for those runs. You can turn alerts off at any time; turning them off stops future sends after the gateway receives the change. Alerts may appear on your Lock Screen."
}

public enum JourneyAlertChannel: String, Codable, CaseIterable, Sendable, Hashable {
    case position, delay, platform, departure, arrival
    public var label: String {
        switch self {
        case .position: "Station progress"
        case .delay: "Delay changes"
        case .platform: "Platform changes"
        case .departure: "Departures"
        case .arrival: "Arrivals"
        }
    }
}

public struct JourneyAlertQuietHours: Codable, Sendable, Equatable {
    public var startHour: Int
    public var endHour: Int
    public var timezone: String
    public var isValid: Bool {
        (0...23).contains(startHour) && (0...23).contains(endHour) && startHour != endHour &&
            TimeZone(identifier: timezone) != nil
    }
    var wire: JourneyAlertRegistration.QuietHours {
        .init(start: String(format: "%02d:00", startHour), end: String(format: "%02d:00", endHour), timeZone: timezone)
    }
}

public enum JourneyAlertIdentity {
    public static func normalize(_ runId: String) -> String {
        runId.hasPrefix("run:") ? String(runId.dropFirst(4)) : runId
    }
    public static func parse(_ runId: String) -> Routes.JourneyDestination? {
        let fields = normalize(runId).split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 2, Routes.isValidTrainNumber(String(fields[0])),
              Routes.isValidCalendarDate(String(fields[1])) else { return nil }
        return .init(trainNumber: String(fields[0]), date: String(fields[1]))
    }
}

public struct JourneyAlertSubscription: Codable, Sendable, Identifiable, Equatable {
    public var id: String { runId }
    public var runId: String
    public var trainNumber: String
    public var serviceDate: String
    public var channels: Set<JourneyAlertChannel>
    public var quietHours: JourneyAlertQuietHours?
    public var expiresAt: Date
    public var pending: Bool
    public var enabled: Bool
    public var revision: Int64
    // Only a fingerprint is persisted. APNs tokens are requested anew every launch.
    var targetFingerprint: String?
    var consentVersion: String?
    var noticeHash: String?
}

public struct JourneyAlertRegistration: Encodable, Sendable {
    public struct Target: Encodable, Sendable {
        let kind = "apns"
        let token: String
        let environment: String
    }
    public struct QuietHours: Encodable, Sendable {
        let start: String
        let end: String
        let timeZone: String
    }
    let runId: String
    let revision: Int64
    let target: Target
    let channels: [JourneyAlertChannel]
    let quietHours: QuietHours?
    let consentVersion = JourneyAlertConsent.version
    let noticeHash = JourneyAlertConsent.noticeHash
    private enum CodingKeys: String, CodingKey { case runId, revision, target, channels, quietHours, consentVersion, noticeHash }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(consentVersion, forKey: .consentVersion)
        try container.encode(noticeHash, forKey: .noticeHash)
        try container.encode(runId, forKey: .runId)
        try container.encode(revision, forKey: .revision)
        try container.encode(target, forKey: .target)
        try container.encode(channels, forKey: .channels)
        if let quietHours { try container.encode(quietHours, forKey: .quietHours) }
        else { try container.encodeNil(forKey: .quietHours) }
    }
}

public struct JourneyAlertAcknowledgement: Decodable, Sendable {
    let stored: Bool
    let runId: String
    let revision: Int64
    let expiresAt: Double
}

public protocol JourneyAlertAPI: Sendable {
    func registerJourneyAlerts(_ request: JourneyAlertRegistration) async throws -> JourneyAlertAcknowledgement
    func unregisterJourneyAlerts(runId: String, revision: Int64) async throws
}

// Existing preview/test implementations do not silently acknowledge an unsupported endpoint.
public extension JourneyAlertAPI {
    func registerJourneyAlerts(_ request: JourneyAlertRegistration) async throws -> JourneyAlertAcknowledgement {
        throw JourneyAlertError.unavailable
    }
    func unregisterJourneyAlerts(runId: String, revision: Int64) async throws { throw JourneyAlertError.unavailable }
}

public enum JourneyAlertError: LocalizedError {
    case unavailable, invalidJourney, invalidOptions, permissionDenied, registrationUnavailable, storageUnavailable
    public var errorDescription: String? {
        switch self {
        case .unavailable: "Journey alerts require a configured rail gateway."
        case .invalidJourney: "Alerts require an upcoming or current dated train journey."
        case .invalidOptions: "Choose at least one alert and a valid quiet-hours interval."
        case .permissionDenied: "Allow notifications for Locomate in iOS Settings to enable alerts."
        case .registrationUnavailable: "Apple push registration is unavailable. Check your connection and try again."
        case .storageUnavailable: "Alert preferences could not be saved. Try again before leaving this screen."
        }
    }
}

/// A durable desired-state log. Disabled rows retain their revision to prevent a late request reviving a run.
struct JourneyAlertStore {
    let file: URL
    init(directory: URL? = nil, scope: String) {
        let root = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("locomote", isDirectory: true)
        file = root.appendingPathComponent(scope, isDirectory: true).appendingPathComponent("journey-alerts.json")
    }
    func load() throws -> [JourneyAlertSubscription] {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return try JSONDecoder().decode([JourneyAlertSubscription].self, from: Data(contentsOf: file))
    }
    func markPresented(eventId: String, expiresAt: Date, now: Date = Date()) throws -> Bool {
        let receiptFile = file.deletingLastPathComponent().appendingPathComponent("journey-alert-events.json")
        var seen: [String: Date] = [:]
        if FileManager.default.fileExists(atPath: receiptFile.path) {
            seen = try JSONDecoder().decode([String: Date].self, from: Data(contentsOf: receiptFile))
                .filter { $0.value > now }
        }
        guard seen[eventId] == nil else { return false }
        seen[eventId] = expiresAt
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(seen).write(to: receiptFile, options: .atomic)
        excludeFromBackup(receiptFile)
        return true
    }

    func save(_ subscriptions: [JourneyAlertSubscription]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        excludeFromBackup(file.deletingLastPathComponent())
        try JSONEncoder().encode(subscriptions).write(to: file, options: [.atomic])
        excludeFromBackup(file)
    }
}

@MainActor
public protocol JourneyAlertPushAuthorization: AnyObject {
    var token: String? { get }
    var environment: String { get }
    func requestPermission() async throws -> Bool
    func isDenied() async -> Bool
    func register()
}

@Observable @MainActor
public final class JourneyAlertService {
    public private(set) var subscriptions: [JourneyAlertSubscription] = []
    public private(set) var isBusy = false
    public private(set) var message: String?
    private let api: (any JourneyAlertAPI)?
    private let store: JourneyAlertStore
    private let push: any JourneyAlertPushAuthorization
    private var storageReadable = true
    private var privacyDeletionPending = false
    private var mutationEpoch = 0
    private var syncTask: Task<Void, Error>?
    private var retryTask: Task<Void, Never>?

    public init(api: (any JourneyAlertAPI)?, scope: String = "preview", directory: URL? = nil,
                push: (any JourneyAlertPushAuthorization)? = nil) {
        self.api = api
        self.store = JourneyAlertStore(directory: directory, scope: scope)
        self.push = push ?? JourneyAlertPushBridge.shared
        do { subscriptions = try store.load() }
        catch { storageReadable = false; message = "Saved alert preferences could not be read. Export your data before resetting it." }
    }

    public func start() async {
        guard !privacyDeletionPending && !PrivacyDeletionLatch.isPending else { return }
        if subscriptions.contains(where: { $0.enabled }) { push.register() }
        await refresh()
        guard !privacyDeletionPending && !PrivacyDeletionLatch.isPending, retryTask == nil else { return }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self else { return }
                if JourneyAlertPushBridge.appIsActive { await self.refresh() }
            }
        }
    }

    public func enable(journey: Journey, channels: Set<JourneyAlertChannel>, quietHours: JourneyAlertQuietHours?) async throws {
        guard api != nil, !privacyDeletionPending && !PrivacyDeletionLatch.isPending else { throw JourneyAlertError.unavailable }
        mutationEpoch += 1
        let epoch = mutationEpoch
        guard let identity = JourneyAlertIdentity.parse(journey.id), identity.trainNumber == journey.trainNumber,
              let schedule = CalendarDetails.build(journey: journey, originDate: identity.date, plan: nil),
              schedule.endDate.addingTimeInterval(24 * 60 * 60) > Date(), journey.completion < 1 else {
            throw JourneyAlertError.invalidJourney
        }
        guard !channels.isEmpty, quietHours?.isValid != false else { throw JourneyAlertError.invalidOptions }
        guard try await push.requestPermission() else { throw JourneyAlertError.permissionDenied }
        push.register()
        // Permission and token registration are separate asynchronous system operations.
        for _ in 0..<50 {
            if push.token != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard !privacyDeletionPending && !PrivacyDeletionLatch.isPending, epoch == mutationEpoch, let token = push.token else { throw JourneyAlertError.registrationUnavailable }
        let runId = JourneyAlertIdentity.normalize(journey.id)
        let previous = subscriptions.first { $0.runId == runId }
        let desired = JourneyAlertSubscription(runId: runId, trainNumber: identity.trainNumber, serviceDate: identity.date,
            channels: channels, quietHours: quietHours,
            expiresAt: min(schedule.endDate.addingTimeInterval(24 * 60 * 60), Date().addingTimeInterval(5 * 24 * 60 * 60)),
            pending: true, enabled: true, revision: nextRevision(previous?.revision), targetFingerprint: fingerprint(token),
            consentVersion: JourneyAlertConsent.version, noticeHash: JourneyAlertConsent.noticeHash)
        try replace(desired)
        try await synchronize()
    }

    public func disable(runId: String) async throws {
        mutationEpoch += 1
        guard !privacyDeletionPending && !PrivacyDeletionLatch.isPending else { throw JourneyAlertError.unavailable }
        guard var current = subscriptions.first(where: { $0.runId == JourneyAlertIdentity.normalize(runId) }) else { return }
        current.enabled = false
        current.pending = true
        current.revision = nextRevision(current.revision)
        try replace(current)
        try await synchronize()
    }

    public func disableAll() async throws {
        mutationEpoch += 1
        guard !privacyDeletionPending && !PrivacyDeletionLatch.isPending else { throw JourneyAlertError.unavailable }
        var changed = subscriptions
        for index in changed.indices where changed[index].enabled {
            changed[index].enabled = false
            changed[index].pending = true
            changed[index].revision = nextRevision(changed[index].revision)
        }
        try persist(changed)
        try await synchronize()
    }

    public func refresh() async {
        guard api != nil, !privacyDeletionPending && !PrivacyDeletionLatch.isPending, storageReadable else { return }
        do {
            let epoch = mutationEpoch
            let denied = await push.isDenied()
            guard !privacyDeletionPending && !PrivacyDeletionLatch.isPending, storageReadable, epoch == mutationEpoch else { return }
            var changed = subscriptions
            let targetFingerprint = push.token.map(fingerprint)
            for index in changed.indices where changed[index].enabled {
                if denied || changed[index].expiresAt <= Date() ||
                    changed[index].consentVersion != JourneyAlertConsent.version ||
                    changed[index].noticeHash != JourneyAlertConsent.noticeHash {
                    changed[index].enabled = false
                    changed[index].pending = true
                    changed[index].revision = nextRevision(changed[index].revision)
                } else if let targetFingerprint, changed[index].targetFingerprint != targetFingerprint {
                    changed[index].targetFingerprint = targetFingerprint
                    changed[index].pending = true
                    changed[index].revision = nextRevision(changed[index].revision)
                }
            }
            if changed != subscriptions { try persist(changed) }
            if subscriptions.contains(where: { $0.enabled }) && push.token == nil { push.register() }
            try await synchronize()
        } catch { message = error.localizedDescription }
    }

    public func beginPrivacyDeletion() async {
        privacyDeletionPending = true
        mutationEpoch += 1
        retryTask?.cancel()
        retryTask = nil
        syncTask?.cancel()
        _ = try? await syncTask?.value
    }

    public func restoreAfterPrivacyDeletion() {
        privacyDeletionPending = false
        Task { await start() }
    }

    /// Used before presentation and tap routing. Server revision guards are also enforced at delivery.
    func accepts(_ payload: JourneyAlertPayload, presenting: Bool) -> Bool {
        guard !privacyDeletionPending && !PrivacyDeletionLatch.isPending, payload.expiresAt > Date(),
              let subscription = subscriptions.first(where: { $0.runId == payload.runId }),
              subscription.enabled, subscription.revision == payload.revision,
              subscription.expiresAt > Date(), subscription.channels.contains(payload.channel) else { return false }
        if presenting {
            do {
                guard try store.markPresented(eventId: payload.eventId, expiresAt: payload.expiresAt) else { return false }
            } catch {
                message = "This notification could not be recorded on the device."
                return false
            }
        }
        return true
    }

    private func nextRevision(_ previous: Int64?) -> Int64 {
        max((previous ?? 0) + 1, Int64(Date().timeIntervalSince1970 * 1000))
    }

    private func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data("\(push.environment):\(token)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func replace(_ value: JourneyAlertSubscription) throws {
        var changed = subscriptions.filter { $0.runId != value.runId }
        changed.append(value)
        try persist(changed)
    }

    private func persist(_ changed: [JourneyAlertSubscription]) throws {
        guard storageReadable else { throw JourneyAlertError.storageUnavailable }
        do { try store.save(changed); subscriptions = changed }
        catch { throw JourneyAlertError.storageUnavailable }
    }

    private func synchronize() async throws {
        if let syncTask { return try await syncTask.value }
        guard let api, !privacyDeletionPending && !PrivacyDeletionLatch.isPending else { return }
        isBusy = true
        let task = Task { @MainActor [weak self, api] in
            guard let self else { return }
            var conflictRecoveries = 0
            while let desired = self.subscriptions.first(where: { $0.pending && (!$0.enabled || self.push.token != nil) }) {
                try Task.checkCancellation()
                guard !self.privacyDeletionPending && !PrivacyDeletionLatch.isPending else { return }
                var acknowledged = desired
                do {
                if desired.enabled {
                    guard let token = self.push.token else { return }
                    let request = JourneyAlertRegistration(runId: desired.runId, revision: desired.revision,
                        target: .init(token: token, environment: self.push.environment),
                        channels: desired.channels.sorted { $0.rawValue < $1.rawValue }, quietHours: desired.quietHours?.wire)
                    let ack = try await api.registerJourneyAlerts(request)
                    guard ack.stored, ack.runId == desired.runId, ack.revision == desired.revision,
                          ack.expiresAt.isFinite, ack.expiresAt > Date().timeIntervalSince1970 * 1000 else {
                        throw URLError(.badServerResponse)
                    }
                    acknowledged.expiresAt = Date(timeIntervalSince1970: ack.expiresAt / 1000)
                } else {
                    try await api.unregisterJourneyAlerts(runId: desired.runId, revision: desired.revision)
                }
                } catch let error as APIError {
                    guard error.status == 409, let serverRevision = error.currentRevision,
                          conflictRecoveries < 2, !self.privacyDeletionPending && !PrivacyDeletionLatch.isPending,
                          let index = self.subscriptions.firstIndex(where: { $0.runId == desired.runId }) else { throw error }
                    // Recover only the latest desired state. A newer local disable remains a disable.
                    var changed = self.subscriptions
                    changed[index].revision = self.nextRevision(max(serverRevision, changed[index].revision))
                    changed[index].pending = true
                    try self.persist(changed)
                    conflictRecoveries += 1
                    continue
                }
                try Task.checkCancellation()
                // A disable or token rotation during this request owns the next revision.
                if self.subscriptions.first(where: { $0.runId == desired.runId })?.revision == desired.revision {
                    acknowledged.pending = false
                    try self.replace(acknowledged)
                }
            }
        }
        syncTask = task
        defer { syncTask = nil; isBusy = false }
        do { try await task.value; message = nil }
        catch { message = "Changes saved on this device; gateway sync is pending. \(error.localizedDescription)"; throw error }
    }
}

//
//  ContributionService.swift
//  Locomate
//
//  Consent-gated community contribution — the native CoreLocation counterpart
//  to SmartRail's `src/location/contribution.native.ts`.
//
//  Rules preserved:
//  - Nothing is collected without an explicit, versioned consent.
//  - Nothing is collected or queued for a preview run.
//  - Observations are map-matched, compacted, and queued offline.
//  - Revoking consent stops collection AND wipes the local queue immediately.
//

import Foundation
import CoreLocation
import Observation

enum Consent {
    static let version = 2
    static let scope = "community_observations"
    static let noticeHash = "85e622e058a604e15d9dd794416785a09245e085f69c97381e7cc47a600f4f25"
    static let notice = "SmartRail privacy notice v2: optional community observations include onboard positions and user-entered physical locomotive or coach-plate numbers; no photos, GPS, PNR, coach/seat, or notes are collected with physical ID reports, and consent can be withdrawn at any time."
}

public struct CommunityConsentEvidence: Codable, Sendable {
    public let evidenceId: String
    public let purpose: String
    public let decision: String
    public let consentVersion: String
    public let noticeHash: String
    public let recordedAt: Int

    public init(granted: Bool) {
        evidenceId = UUID().uuidString
        purpose = Consent.scope
        decision = granted ? "granted" : "withdrawn"
        consentVersion = String(Consent.version)
        noticeHash = Consent.noticeHash
        recordedAt = Int(Date().timeIntervalSince1970 * 1_000)
    }
}

/// A withdrawal survives a network failure and is retried on the next foreground session.
@MainActor
final class ConsentEvidenceQueue {
    private let url: URL

    init(directory: URL? = nil, scope: String? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("locomote", isDirectory: true)
        let folder = scope.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        excludeFromBackup(folder)
        url = folder.appendingPathComponent("consent-evidence.json")
        if FileManager.default.fileExists(atPath: url.path) { excludeFromBackup(url) }
    }

    var pending: [CommunityConsentEvidence] {
        (try? load()) ?? []
    }

    func append(_ evidence: CommunityConsentEvidence) throws {
        try save(load() + [evidence])
    }

    func remove(_ evidenceId: String) throws {
        try save(load().filter { $0.evidenceId != evidenceId })
    }

    fileprivate func load() throws -> [CommunityConsentEvidence] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([CommunityConsentEvidence].self, from: Data(contentsOf: url))
    }

    private func save(_ records: [CommunityConsentEvidence]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
        excludeFromBackup(url)
    }
}

@MainActor
@Observable
public final class ContributionService: NSObject {
    public enum State: Sendable, Equatable {
        case idle
        case collecting
        case denied
        case unavailable
    }

    public private(set) var state: State = .idle
    public private(set) var queuedCount: Int = 0
    public private(set) var lastObservation: CompactObservation?

    private let manager = CLLocationManager()
    private var context: ContributionContext?
    private var consentVersion: Int = Consent.version
    private let queue: ObservationQueue
    private let consentEvidence: ConsentEvidenceQueue
    private var observationSync: ObservationSync?
    private var flushTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var stopAt: Date?
    private var syncRevision = 0
    private var backgroundEnabled = false

    public init(queue: ObservationQueue? = nil, scope: String? = nil, consentDirectory: URL? = nil) {
        self.queue = queue ?? ObservationQueue(scope: scope)
        self.consentEvidence = ConsentEvidenceQueue(directory: consentDirectory, scope: scope)
        super.init()
        if self.queue.peek(limit: Int.max).contains(where: { $0.consentVersion != Consent.version }) {
            self.queue.clear()
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 50
        manager.activityType = .otherNavigation
        queuedCount = self.queue.count()
    }

    // MARK: Consent-aware lifecycle

    /// Begin contributing for a specific run. `background` additionally enables
    /// background updates and an ongoing-location session.
    public func start(runId: String, route: [RailCoordinate], background: Bool,
                      service: RailServiceProtocol? = nil, stopAt: Date? = nil) async {
        // Preview runs are never contributed.
        guard !ContributionObservation.isPreviewRunId(runId), route.count >= 2 else {
            state = .unavailable
            return
        }
        if context?.runId == runId && backgroundEnabled == background && state == .collecting { return }
        stop()
        if let stopAt, stopAt <= Date() { state = .unavailable; return }
        context = ContributionContext(runId: runId, route: route)
        observationSync = ObservationSync(queue: queue, service: service)
        self.stopAt = stopAt
        if let stopAt {
            expiryTask = Task { [weak self] in
                let interval = max(0, stopAt.timeIntervalSinceNow)
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.stop()
            }
        }
        flushPendingObservations()

        guard manager.authorizationStatus != .denied, manager.authorizationStatus != .restricted else {
            stop()
            state = .denied
            return
        }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }
        guard manager.accuracyAuthorization == .fullAccuracy else {
            stop()
            state = .unavailable
            return
        }
        updateBackground(background)
        manager.startUpdatingLocation()
        state = .collecting
    }

    public func updateBackground(_ enabled: Bool) {
        backgroundEnabled = enabled
        guard context != nil,
              (manager.authorizationStatus == .authorizedWhenInUse
                || manager.authorizationStatus == .authorizedAlways),
              manager.accuracyAuthorization == .fullAccuracy else { return }
        manager.allowsBackgroundLocationUpdates = enabled
        manager.distanceFilter = enabled ? 100 : 50
        manager.pausesLocationUpdatesAutomatically = true
        manager.showsBackgroundLocationIndicator = enabled
    }

    public func stop() {
        syncRevision += 1
        expiryTask?.cancel()
        expiryTask = nil
        flushTask?.cancel()
        flushTask = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.pausesLocationUpdatesAutomatically = true
        context = nil
        observationSync = nil
        stopAt = nil
        backgroundEnabled = false
        state = .idle
    }

    /// Revoke consent: stop immediately and erase everything queued locally.
    public func revoke() {
        stop()
        queue.clear()
        queuedCount = 0
        lastObservation = nil
    }

    /// Observations waiting for upload (for the batch endpoint).
    public func pendingBatch(limit: Int = 64) -> [CompactObservation] {
        queue.peek(limit: limit)
    }

    public func acknowledge(_ sent: [CompactObservation]) {
        queue.remove(sent)
        queuedCount = queue.count()
    }

    func queueWithdrawal() throws {
        try consentEvidence.append(CommunityConsentEvidence(granted: false))
    }

    func flushConsentEvidence(using service: RailServiceProtocol?) async throws {
        guard let service else { return }
        for evidence in try consentEvidence.load() {
            try await service.recordCommunityConsent(evidence)
            try consentEvidence.remove(evidence.evidenceId)
        }
    }

    private func record(_ location: CLLocation) {
        guard let context else { return }
        if let stopAt, Date() >= stopAt { stop(); return }
        let device = DeviceLocation(
            timestamp: location.timestamp.timeIntervalSince1970 * 1000,
            mocked: location.sourceInformation?.isSimulatedBySoftware ?? false,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            accuracy: location.horizontalAccuracy,
            speed: location.speed
        )
        guard let observation = ContributionObservation.compact(
            location: device,
            context: context,
            consentVersion: consentVersion
        ) else { return }
        queue.append(observation)
        queuedCount = queue.count()
        lastObservation = observation
        flushPendingObservations()
    }

    private func flushPendingObservations() {
        guard flushTask == nil, let observationSync else { return }
        let revision = syncRevision
        flushTask = Task { [weak self] in
            _ = await observationSync.flush(consentGranted: self?.context != nil)
            if self?.syncRevision == revision { self?.flushTask = nil }
        }
    }
}

extension ContributionService: CLLocationManagerDelegate {
    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            guard let latest else { return }
            self.record(latest)
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .denied, .restricted:
                self.stop()
                self.state = .denied
            case .authorizedWhenInUse, .authorizedAlways:
                if self.context != nil {
                    guard self.manager.accuracyAuthorization == .fullAccuracy else {
                        self.stop()
                        self.state = .unavailable
                        return
                    }
                    self.updateBackground(self.backgroundEnabled)
                    self.manager.startUpdatingLocation()
                    self.state = .collecting
                }
            default:
                break
            }
        }
    }
}

// MARK: - Offline queue

/// File-backed FIFO queue of pending observations. Survives relaunch so a
/// tunnel or dead zone never loses accepted evidence.
public final class ObservationQueue: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(directory: URL? = nil, scope: String? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("locomote", isDirectory: true)
        let folder = scope.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        excludeFromBackup(folder)
        self.url = folder.appendingPathComponent("observations.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            excludeFromBackup(self.url)
        }
    }

    private func read() -> [CompactObservation] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([CompactObservation].self, from: data)) ?? []
    }

    private func write(_ items: [CompactObservation]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        if (try? data.write(to: url, options: .atomic)) != nil {
            excludeFromBackup(url)
        }
    }

    public func append(_ observation: CompactObservation) {
        lock.lock(); defer { lock.unlock() }
        let existing = read().filter {
            $0.runId != observation.runId || $0.timestamp != observation.timestamp
        }
        write(existing + [observation])
    }

    public func peek(limit: Int) -> [CompactObservation] {
        lock.lock(); defer { lock.unlock() }
        return Array(read().prefix(limit))
    }

    public func remove(_ sent: [CompactObservation]) {
        lock.lock(); defer { lock.unlock() }
        let ids = Set(sent.map { "\($0.runId)-\($0.timestamp)" })
        write(read().filter { !ids.contains("\($0.runId)-\($0.timestamp)") })
    }

    public func count() -> Int {
        lock.lock(); defer { lock.unlock() }
        return read().count
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        write([])
    }
}

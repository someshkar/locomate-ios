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

    public init(queue: ObservationQueue = ObservationQueue()) {
        self.queue = queue
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 25
        manager.activityType = .otherNavigation
        queuedCount = queue.count()
    }

    // MARK: Consent-aware lifecycle

    /// Begin contributing for a specific run. `background` additionally enables
    /// background updates and an ongoing-location session.
    public func start(runId: String, route: [RailCoordinate], background: Bool) async {
        // Preview runs are never contributed.
        guard !ContributionObservation.isPreviewRunId(runId), route.count >= 2 else {
            state = .unavailable
            return
        }
        context = ContributionContext(runId: runId, route: route)

        guard manager.authorizationStatus != .denied, manager.authorizationStatus != .restricted else {
            state = .denied
            return
        }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if background {
            manager.allowsBackgroundLocationUpdates = true
            manager.pausesLocationUpdatesAutomatically = false
            manager.showsBackgroundLocationIndicator = true
            if #available(iOS 17.0, *) {
                manager.showsBackgroundLocationIndicator = true
            }
        }
        manager.startUpdatingLocation()
        state = .collecting
    }

    public func stop() {
        manager.stopUpdatingLocation()
        context = nil
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

    private func record(_ location: CLLocation) {
        guard let context else { return }
        let device = DeviceLocation(
            timestamp: location.timestamp.timeIntervalSince1970 * 1000,
            mocked: false,
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
                self.state = .denied
                self.manager.stopUpdatingLocation()
            case .authorizedWhenInUse, .authorizedAlways:
                if self.context != nil { self.state = .collecting }
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

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("locomote", isDirectory: true)
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
        write(read() + [observation])
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

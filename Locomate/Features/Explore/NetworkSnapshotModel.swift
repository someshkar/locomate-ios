import Foundation
import Observation

/// The displayed marker value is also its update identity: source, kind and
/// timestamp changes must update MapKit even when the coordinate is unchanged.
struct NetworkMarker: Identifiable, Equatable {
    let id: String
    let latitude: Double
    let longitude: Double
    let title: String
    let subtitle: String
    let kind: NetworkPositionKind
    var observed: Bool { kind == .observed }
}

struct NetworkSnapshot {
    private struct Entry {
        let marker: NetworkMarker
        let observedAt: Date
    }

    let generatedAt: Date
    let freshUntil: Date
    private let entries: [Entry]

    init(_ response: NetworkTrainsResponse, now: Date) throws {
        guard let generated = Self.date(response.generatedAt),
              let expiry = Self.date(response.freshUntil),
              expiry >= generated, generated <= now.addingTimeInterval(60) else {
            throw SnapshotError.invalidTiming
        }
        generatedAt = generated
        freshUntil = expiry
        entries = response.trains.compactMap { train in
            let point = train.coordinate
            guard point.latitude.isFinite, point.longitude.isFinite,
                  (-90...90).contains(point.latitude), (-180...180).contains(point.longitude),
                  let observedAt = Self.date(train.observedAt) else { return nil }
            // An observed label needs an observation source. Do not relabel an
            // inconsistent entry as a prediction that the gateway did not send.
            if train.positionKind == .observed,
               ![DataSource.official, .community, .device].contains(train.source) { return nil }
            return Entry(marker: NetworkMarker(
                id: train.runId, latitude: point.latitude, longitude: point.longitude,
                title: "\(train.trainNumber) · \(train.name)",
                subtitle: "\(train.positionKind.rawValue) · \(train.source.rawValue) · \(train.observedAt)",
                kind: train.positionKind
            ), observedAt: observedAt)
        }
    }

    func isFresh(at now: Date) -> Bool {
        now < freshUntil && generatedAt <= now.addingTimeInterval(60)
    }

    func markers(at now: Date) -> [NetworkMarker] {
        guard isFresh(at: now) else { return [] }
        return entries.filter {
            let age = now.timeIntervalSince($0.observedAt)
            return age >= -60 && age <= 10 * 60
        }.map(\.marker)
    }

    private static func date(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter.locomote.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value)
    }

    enum SnapshotError: LocalizedError {
        case invalidTiming
        var errorDescription: String? { "The gateway returned invalid network timing." }
    }
}

/// Request epochs cover cancellation-ignoring transports and changes in map
/// bounds. A failed request never extends the last snapshot's freshness window.
@MainActor @Observable
final class NetworkSnapshotModel {
    private(set) var bounds: NetworkBounds
    private(set) var snapshot: NetworkSnapshot?
    private(set) var now: Date
    private(set) var loading = false
    private(set) var error: String?
    @ObservationIgnored private var requestEpoch = 0
    @ObservationIgnored private let clock: () -> Date

    init(bounds: NetworkBounds = NetworkBounds(west: 68, south: 6, east: 98, north: 37),
         clock: @escaping () -> Date = Date.init) {
        self.bounds = bounds
        self.clock = clock
        self.now = clock()
    }

    var markers: [NetworkMarker] { snapshot?.markers(at: now) ?? [] }
    var expired: Bool { snapshot.map { !$0.isFresh(at: now) } ?? false }

    func tick() { now = clock() }

    func setBounds(_ newBounds: NetworkBounds) {
        guard newBounds != bounds else { return }
        bounds = newBounds
        invalidateRequest()
    }

    func invalidateRequest() {
        requestEpoch += 1
        loading = false
    }

    func refresh(using fetch: (NetworkBounds) async throws -> NetworkTrainsResponse) async {
        requestEpoch += 1
        let epoch = requestEpoch
        let requestedBounds = bounds
        loading = true
        defer { if epoch == requestEpoch { loading = false } }
        do {
            let response = try await fetch(requestedBounds)
            guard !Task.isCancelled, epoch == requestEpoch, bounds == requestedBounds else { return }
            tick()
            snapshot = try NetworkSnapshot(response, now: now)
            error = nil
        } catch {
            guard !Task.isCancelled, epoch == requestEpoch, bounds == requestedBounds else { return }
            tick()
            self.error = error.localizedDescription
        }
    }
}

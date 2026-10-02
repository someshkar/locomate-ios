import Foundation
import Observation

/// In-memory state is confined to a source, selected train/date and explicit
/// attempt. History never participates in the Journey's periodic load/cache.
@MainActor @Observable
final class ReliabilityHistoryModel {
    struct Key: Equatable {
        let source: ObjectIdentifier
        let trainNumber: String
        let originDate: String
        let preview: Bool
        var attempt = 0
    }
    enum Phase {
        case idle, loading, unavailable, blocked
        case loaded(TrainHistoryResponse)
        case failed
    }
    private(set) var phase: Phase = .idle
    private var key: Key?
    @ObservationIgnored private var requestID: UUID?
    @ObservationIgnored private let privacyPending: () -> Bool

    init(privacyPending: @escaping () -> Bool = { PrivacyDeletionLatch.isPending }) {
        self.privacyPending = privacyPending
    }

    /// Rendering checks ownership synchronously, before the new SwiftUI task
    /// can reset state after a train, source, preview or attempt change.
    func phase(for key: Key) -> Phase {
        if privacyPending() { return .blocked }
        if key.preview { return .unavailable }
        guard self.key == key else { return .idle }
        return phase
    }

    func load(key: Key, fetch: () async throws -> TrainHistoryResponse) async {
        if self.key != key {
            cancel()
            self.key = key
            phase = .idle
        }
        guard !privacyPending() else { cancel(); phase = .blocked; return }
        guard !key.preview else { cancel(); phase = .unavailable; return }
        guard !Task.isCancelled else { return }
        guard case .idle = phase else { return }
        let id = UUID()
        requestID = id
        phase = .loading
        do {
            let response = try await fetch()
            guard requestID == id else { return }
            guard !privacyPending() else { phase = .blocked; requestID = nil; return }
            guard !Task.isCancelled else { phase = .idle; requestID = nil; return }
            try ReliabilitySummary.validate(response, trainNumber: key.trainNumber)
            phase = .loaded(response)
        } catch {
            guard requestID == id else { return }
            if privacyPending() { phase = .blocked }
            else if Task.isCancelled || error is CancellationError { phase = .idle }
            else { phase = .failed }
        }
        if requestID == id { requestID = nil }
    }

    func cancel() {
        requestID = nil
        if case .loading = phase { phase = .idle }
    }
}

//
//  ObservationSync.swift
//  Locomate
//
//  Flushes consented, queued observations to the gateway in idempotent batches.
//  Ported from SmartRail `src/services/observationSync.ts`.
//
//  Rules preserved: consent is re-checked before every flush, preview runs are
//  never uploaded, and a failed batch stays queued for the next opportunity.
//

import Foundation

public actor ObservationSync {
    private let queue: ObservationQueue
    private let service: RailServiceProtocol?
    private let batchSize: Int

    public init(queue: ObservationQueue, service: RailServiceProtocol?, batchSize: Int = 64) {
        self.queue = queue
        self.service = service
        self.batchSize = batchSize
    }

    public struct Outcome: Sendable, Equatable {
        public let uploaded: Int
        public let remaining: Int
        public let failed: Bool
    }

    /// Drain up to `maxBatches` batches. Stops early on the first failure so a
    /// flaky connection does not burn through the queue.
    @discardableResult
    public func flush(
        consentGranted: Bool,
        maxBatches: Int = 4
    ) async -> Outcome {
        guard consentGranted else {
            return Outcome(uploaded: 0, remaining: queue.count(), failed: false)
        }
        guard let service else {
            // Preview / no gateway: nothing can be uploaded yet.
            return Outcome(uploaded: 0, remaining: queue.count(), failed: false)
        }

        var uploaded = 0
        for _ in 0..<maxBatches {
            if Task.isCancelled { break }
            let now = Int(Date().timeIntervalSince1970 * 1_000)
            let queued = queue.peek(limit: min(batchSize, 100))
            let discarded = queued.filter {
                $0.timestamp < now - 9 * 60_000 || $0.timestamp > now + 60_000
                    || $0.consentVersion != Consent.version
                    || ContributionObservation.isPreviewRunId($0.runId)
            }
            if !discarded.isEmpty { queue.remove(discarded) }
            let batch = queued.filter { !discarded.contains($0) }
            if batch.isEmpty {
                if discarded.isEmpty { break }
                continue
            }
            do {
                let accepted = Set(try await service.uploadObservations(batch))
                let acknowledged = batch.filter { accepted.contains("\($0.runId):\($0.timestamp)") }
                queue.remove(acknowledged)
                uploaded += acknowledged.count
                if acknowledged.isEmpty { break }
            } catch {
                return Outcome(uploaded: uploaded, remaining: queue.count(), failed: true)
            }
        }
        return Outcome(uploaded: uploaded, remaining: queue.count(), failed: false)
    }

    public func pendingCount() -> Int { queue.count() }
}

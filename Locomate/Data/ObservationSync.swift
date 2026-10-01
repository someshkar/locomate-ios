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
            let batch = queue.peek(limit: batchSize)
                .filter { !ContributionObservation.isPreviewRunId($0.runId) }
            guard !batch.isEmpty else { break }
            do {
                _ = try await service.uploadObservations(batch)
                // Acknowledge regardless of the per-item list: the gateway
                // de-duplicates by local id, and a rejected item is not useful
                // to retry forever.
                queue.remove(batch)
                uploaded += batch.count
            } catch {
                return Outcome(uploaded: uploaded, remaining: queue.count(), failed: true)
            }
        }
        return Outcome(uploaded: uploaded, remaining: queue.count(), failed: false)
    }

    public func pendingCount() -> Int { queue.count() }
}

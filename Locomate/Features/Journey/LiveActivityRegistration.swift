import Foundation
import Observation

/// Tokens remain in memory. Durable revisions order every registration/withdrawal,
/// including a late POST completing after the traveller stopped the activity.
@MainActor @Observable
public final class LiveActivityRegistration {
    public enum Status: Equatable {
        case idle, pending, registered, retrying
        public var message: String? {
            switch self {
            case .idle: nil
            case .pending: "Connecting Lock Screen updates…"
            case .registered: "Lock Screen updates connected."
            case .retrying: "Lock Screen card is local; remote updates will retry."
            }
        }
    }
    private struct Journal: Codable {
        var revisions: [String: Int64] = [:]
        var withdrawals: [String: Int64] = [:]
    }
    public private(set) var status: Status = .idle
    public var pendingWithdrawals: Set<String> { Set(journal.withdrawals.keys) }
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var withdrawals: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = UUID()
    private var journal: Journal
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let sleep: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private let corruptJournal: Bool

    public init(scope: String = "preview", directory: URL? = nil,
                sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        file = base.appendingPathComponent("locomote/\(scope)/live-activity-unregister.json")
        let data = try? Data(contentsOf: file)
        let decoded = data.flatMap { try? JSONDecoder().decode(Journal.self, from: $0) }
        journal = decoded ?? Journal()
        corruptJournal = data != nil && decoded == nil
        self.sleep = sleep
    }

    public func register(runId: String, send: @escaping @MainActor (Int64) async throws -> Void) {
        cancelRegistration()
        guard !PrivacyDeletionLatch.isPending else { return }
        withdrawals.removeValue(forKey: runId)?.cancel()
        status = .pending
        let current = generation
        registrationTask = Task { [weak self] in
            var attempt = 0
            var revision: Int64?
            while let self, !Task.isCancelled, current == self.generation, !PrivacyDeletionLatch.isPending {
                do {
                    if revision == nil { revision = try self.prepare(runId: runId, withdrawing: false) }
                    try await send(revision!)
                    guard !Task.isCancelled, current == self.generation, !PrivacyDeletionLatch.isPending else { return }
                    self.status = .registered
                    return
                } catch {
                    guard !Task.isCancelled, current == self.generation, !PrivacyDeletionLatch.isPending else { return }
                    self.status = .retrying
                    attempt += 1
                    do { try await self.sleep(.seconds(min(30, 1 << min(attempt - 1, 5)))) }
                    catch { return }
                }
            }
        }
    }

    public func cancelRegistration() {
        generation = UUID()
        registrationTask?.cancel()
        registrationTask = nil
        status = .idle
    }

    public func withdraw(_ runId: String, send: @escaping @MainActor (String, Int64) async throws -> Void) {
        guard !PrivacyDeletionLatch.isPending, runId.hasPrefix("run:") else { return }
        withdrawals.removeValue(forKey: runId)?.cancel()
        withdrawals[runId] = Task { [weak self] in
            var attempt = 0
            var revision: Int64?
            while let self, !Task.isCancelled, !PrivacyDeletionLatch.isPending {
                do {
                    if revision == nil { revision = try self.prepare(runId: runId, withdrawing: true) }
                    try await send(runId, revision!)
                    guard !Task.isCancelled, !PrivacyDeletionLatch.isPending,
                          self.journal.withdrawals[runId] == revision else { return }
                    var updated = self.journal
                    updated.withdrawals.removeValue(forKey: runId)
                    try self.persist(updated)
                    self.withdrawals.removeValue(forKey: runId)
                    return
                } catch {
                    guard !Task.isCancelled, !PrivacyDeletionLatch.isPending else { return }
                    attempt += 1
                    do { try await self.sleep(.seconds(min(30, 1 << min(attempt - 1, 5)))) }
                    catch { return }
                }
            }
        }
    }

    public func resumeWithdrawals(send: @escaping @MainActor (String, Int64) async throws -> Void) {
        guard !PrivacyDeletionLatch.isPending else { return }
        for (runId, revision) in journal.withdrawals where withdrawals[runId] == nil {
            withdrawals[runId] = Task { [weak self] in
                var attempt = 0
                while let self, !Task.isCancelled, self.journal.withdrawals[runId] == revision, !PrivacyDeletionLatch.isPending {
                    do {
                        try await send(runId, revision)
                        guard !Task.isCancelled, !PrivacyDeletionLatch.isPending else { return }
                        var updated = self.journal
                        updated.withdrawals.removeValue(forKey: runId)
                        try self.persist(updated)
                        self.withdrawals.removeValue(forKey: runId)
                        return
                    } catch {
                        guard !Task.isCancelled, !PrivacyDeletionLatch.isPending else { return }
                        attempt += 1
                        do { try await self.sleep(.seconds(min(30, 1 << min(attempt - 1, 5)))) }
                        catch { return }
                    }
                }
            }
        }
    }

    public func erase() {
        cancelRegistration()
        for task in withdrawals.values { task.cancel() }
        withdrawals.removeAll()
        journal = Journal()
        try? FileManager.default.removeItem(at: file)
    }

    private func prepare(runId: String, withdrawing: Bool) throws -> Int64 {
        guard !corruptJournal, !PrivacyDeletionLatch.isPending else { throw URLError(.cannotWriteToFile) }
        var updated = journal
        let revision = max((updated.revisions[runId] ?? 0) + 1, Int64(Date().timeIntervalSince1970 * 1_000) * 1_000)
        updated.revisions[runId] = revision
        if withdrawing { updated.withdrawals[runId] = revision }
        else { updated.withdrawals.removeValue(forKey: runId) }
        try persist(updated) // No network dispatch before its ordering revision is durable.
        return revision
    }
    private func persist(_ updated: Journal) throws {
        guard !PrivacyDeletionLatch.isPending else { throw CancellationError() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(updated).write(to: file, options: .atomic)
        excludeFromBackup(file)
        journal = updated
    }
}

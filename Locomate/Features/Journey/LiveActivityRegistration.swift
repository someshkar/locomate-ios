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
        let decoded = data.flatMap { bytes -> Journal? in
            guard let value = try? JSONDecoder().decode(Journal.self, from: bytes),
                  value.revisions.count <= 512, value.withdrawals.count <= 512,
                  value.revisions.allSatisfy({ OperationalValidation.runID($0.key) && (1...9_007_199_254_740_990).contains($0.value) }),
                  value.withdrawals.allSatisfy({ OperationalValidation.runID($0.key) && (1...9_007_199_254_740_990).contains($0.value)
                      && $0.value <= (value.revisions[$0.key] ?? 0) }) else { return nil }
            return value
        }
        journal = decoded ?? Journal()
        corruptJournal = FileManager.default.fileExists(atPath: file.path) && decoded == nil
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
                    if let conflict = error as? APIError, let remote = conflict.currentRevision {
                        do { try self.adoptRevision(remote, runId: runId); revision = nil } catch { }
                    }
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
        let prepared = try? prepare(runId: runId, withdrawing: true)
        withdrawals[runId] = Task { [weak self] in
            var attempt = 0
            var revision = prepared
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
                    if let conflict = error as? APIError, let remote = conflict.currentRevision {
                        do { try self.adoptRevision(remote, runId: runId); revision = nil } catch { }
                    }
                    attempt += 1
                    do { try await self.sleep(.seconds(min(30, 1 << min(attempt - 1, 5)))) }
                    catch { return }
                }
            }
        }
    }

    public func resumeWithdrawals(send: @escaping @MainActor (String, Int64) async throws -> Void) {
        guard !PrivacyDeletionLatch.isPending else { return }
        for runId in pendingWithdrawals where withdrawals[runId] == nil { withdraw(runId, send: send) }
    }

    public func erase() {
        cancelRegistration()
        for task in withdrawals.values { task.cancel() }
        withdrawals.removeAll()
        journal = Journal()
        try? FileManager.default.removeItem(at: file)
    }

    private func adoptRevision(_ revision: Int64, runId: String) throws {
        guard (0...9_007_199_254_740_990).contains(revision) else { throw URLError(.badServerResponse) }
        var updated = journal
        updated.revisions[runId] = max(updated.revisions[runId] ?? 0, revision)
        try persist(updated)
    }

    private func prepare(runId: String, withdrawing: Bool) throws -> Int64 {
        guard !corruptJournal, !PrivacyDeletionLatch.isPending else { throw URLError(.cannotWriteToFile) }
        guard OperationalValidation.runID(runId) else { throw URLError(.badURL) }
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

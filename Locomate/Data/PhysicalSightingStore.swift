import Foundation
import Observation

/// Equipment reports are authorized individually. This queue never starts GPS,
/// renews consent, or creates another idempotency key during an uncertain retry.
@MainActor @Observable
public final class PhysicalSightingStore {
    public struct Pending: Codable, Sendable {
        public let trainNumber: String
        public let originDate: String
        public let request: PhysicalSightingRequest
        public var id: String { request.consent.evidenceId }
        public func consentIsCurrent(now: Date = Date()) -> Bool {
            let age = now.timeIntervalSince1970 * 1_000 - Double(request.consent.consentedAt)
            return (-60_000...15 * 60_000).contains(age)
                && request.consent.consentVersion == String(Consent.version) && request.consent.noticeHash == Consent.noticeHash
        }
    }
    private struct State: Codable {
        var pending: [Pending] = []
        var remoteConsentMayExist = false
        var withdrawal: CommunityConsentEvidence?
    }
    private var state: State
    private var corruptState: Bool
    @ObservationIgnored private let file: URL
    @ObservationIgnored private let withdrawalMarker: PrivacyDeletionMarker
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var inFlight: Set<String> = []
    public var pendingCount: Int { state.pending.count }
    public var remoteConsentMayExist: Bool { state.remoteConsentMayExist }
    public var withdrawalPending: Bool { state.withdrawal != nil }

    public init(scope: String = "preview", directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        file = base.appendingPathComponent("locomote/\(scope)/physical-reports.json")
        withdrawalMarker = PrivacyDeletionMarker(account: "equipment-withdrawal-\(RailStorageScope.gateway(file))")
        let data = try? Data(contentsOf: file)
        let decoded = data.flatMap { bytes -> State? in
            guard let result = try? JSONDecoder().decode(State.self, from: bytes), result.pending.count <= 32,
                  Set(result.pending.map(\.id)).count == result.pending.count,
                  result.pending.allSatisfy({ Routes.isValidTrainNumber($0.trainNumber) && Routes.isValidCalendarDate($0.originDate)
                      && (try? $0.request.validated()) != nil }) else { return nil }
            return result
        }
        state = decoded ?? State()
        corruptState = FileManager.default.fileExists(atPath: file.path) && decoded == nil
        if corruptState { state.remoteConsentMayExist = true }
        if withdrawalMarker.isPending {
            state.pending.removeAll()
            state.withdrawal = state.withdrawal ?? CommunityConsentEvidence(granted: false)
            state.remoteConsentMayExist = true
        }
    }
    public func pending(trainNumber: String, originDate: String) -> Pending? {
        state.pending.first { $0.trainNumber == trainNumber && $0.originDate == originDate }
    }
    public func enqueue(trainNumber: String, originDate: String, request: PhysicalSightingRequest) throws {
        guard !corruptState, !PrivacyDeletionLatch.isPending, state.withdrawal == nil,
              Routes.isValidTrainNumber(trainNumber), Routes.isValidCalendarDate(originDate) else { throw CancellationError() }
        try request.validated()
        if let existing = state.pending.first(where: { $0.id == request.consent.evidenceId }) {
            // Existing keys must retain byte-identical requests.
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            guard try encoder.encode(existing.request) == encoder.encode(request),
                  existing.trainNumber == trainNumber, existing.originDate == originDate else { throw URLError(.badURL) }
            return
        }
        guard state.pending.count < 32 else { throw URLError(.dataLengthExceedsMaximum) }
        var updated = state
        updated.pending.append(.init(trainNumber: trainNumber, originDate: originDate, request: request))
        updated.remoteConsentMayExist = true // An uncertain response may already have recorded consent remotely.
        try persist(updated)
    }
    public func submit(_ report: Pending, using service: RailServiceProtocol) async throws -> PhysicalSightingResponse {
        guard !PrivacyDeletionLatch.isPending, state.withdrawal == nil, report.consentIsCurrent(),
              state.pending.contains(where: { $0.id == report.id && $0.trainNumber == report.trainNumber && $0.originDate == report.originDate }), !inFlight.contains(report.id) else { throw CancellationError() }
        try report.request.validated()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let persisted = state.pending.first(where: { $0.id == report.id }),
              try encoder.encode(persisted.request) == encoder.encode(report.request) else { throw URLError(.badURL) }
        let snapshot = generation
        inFlight.insert(report.id)
        defer { inFlight.remove(report.id) }
        let response = try await service.submitPhysicalSightings(trainNumber: report.trainNumber, originDate: report.originDate, request: report.request)
        guard !PrivacyDeletionLatch.isPending, generation == snapshot, state.withdrawal == nil else { throw CancellationError() }
        try OperationalValidation.sightingResponse(response, expectedCount: report.request.sightings.count)
        var updated = state
        updated.pending.removeAll { $0.id == report.id }
        try persist(updated)
        return response
    }
    public func retry(using service: RailServiceProtocol?) async {
        guard let service, !PrivacyDeletionLatch.isPending else { return }
        if state.withdrawal != nil { try? await flushWithdrawal(using: service); return }
        for report in state.pending where report.consentIsCurrent() {
            guard !PrivacyDeletionLatch.isPending, state.withdrawal == nil else { return }
            _ = try? await submit(report, using: service)
        }
    }
    public func discard(_ id: String) throws {
        var updated = state
        updated.pending.removeAll { $0.id == id }
        try persist(updated)
    }
    public func withdraw() throws {
        generation = UUID()
        var updated = state
        updated.pending.removeAll()
        updated.withdrawal = state.withdrawal ?? CommunityConsentEvidence(granted: false)
        // Withdrawal must stop this process even if storage becomes unavailable.
        // Keep the evidence in memory for an immediate remote attempt; a failed
        // write must never leave an authorized queue available to retry.
        state = updated
        // A separate Keychain latch survives a failed report-file write and a
        // process restart. Failure of either store is reported, while the other
        // store still gets an opportunity to preserve withdrawal.
        var storageError: (any Error)?
        do { try withdrawalMarker.begin() } catch { storageError = error }
        do { try persist(updated) } catch { storageError = storageError ?? error }
        if let storageError { throw storageError }
        corruptState = false
    }
    public func flushWithdrawal(using service: RailServiceProtocol?) async throws {
        guard let service, let evidence = state.withdrawal, !PrivacyDeletionLatch.isPending else { return }
        let snapshot = generation
        try await service.recordCommunityConsent(evidence)
        guard snapshot == generation, !PrivacyDeletionLatch.isPending else { throw CancellationError() }
        var updated = state
        updated.withdrawal = nil
        updated.remoteConsentMayExist = false
        try persist(updated)
        guard withdrawalMarker.finish() else { throw URLError(.cannotWriteToFile) }
    }
    public func beginPrivacyDeletion() {
        generation = UUID()
        state = State()
        corruptState = false
        inFlight.removeAll()
        try? FileManager.default.removeItem(at: file)
        _ = withdrawalMarker.finish()
    }
    private func persist(_ updated: State) throws {
        guard !PrivacyDeletionLatch.isPending else { throw CancellationError() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(updated).write(to: file, options: .atomic)
        excludeFromBackup(file)
        state = updated
    }
}

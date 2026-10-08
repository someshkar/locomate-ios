import Foundation
import Testing
@testable import Locomate

@Suite("Private durable equipment reports")
@MainActor struct PhysicalSightingStoreTests {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func request(now: Date = Date()) throws -> PhysicalSightingRequest {
        try #require(PhysicalSighting.request(locomotive: "30210", coaches: "123456", now: now, evidenceId: "equipment-proof-12345"))
    }
    @Test("uncertain retries preserve the exact scoped request across process restart")
    func restart() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let service = EquipmentService(); service.fail = true
        let first = PhysicalSightingStore(scope: "gateway-one", directory: folder)
        let body = try request()
        try first.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: body)
        let report = try #require(first.pending(trainNumber: "12345", originDate: "2026-10-08"))
        await #expect(throws: URLError.self) { try await first.submit(report, using: service) }
        let second = PhysicalSightingStore(scope: "gateway-one", directory: folder)
        #expect(second.pendingCount == 1 && second.remoteConsentMayExist)
        #expect(PhysicalSightingStore(scope: "gateway-two", directory: folder).pendingCount == 0)
        service.fail = false
        _ = try await second.submit(#require(second.pending(trainNumber: "12345", originDate: "2026-10-08")), using: service)
        #expect(service.bodies.count == 2 && service.bodies[0] == service.bodies[1])
        #expect(second.pendingCount == 0)
        #expect(PhysicalSightingStore(scope: "gateway-one", directory: folder).pendingCount == 0)
    }
    @Test("expired authorization never retries automatically or renews its evidence time")
    func expiration() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = PhysicalSightingStore(directory: folder)
        let expired = try request(now: Date().addingTimeInterval(-901))
        try store.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: expired)
        let service = EquipmentService()
        await store.retry(using: service)
        #expect(service.bodies.isEmpty && store.pendingCount == 1)
        #expect(store.pending(trainNumber: "12345", originDate: "2026-10-08")?.request.consent.consentedAt == expired.consent.consentedAt)
    }
    @Test("withdrawal works when GPS was never enabled and survives offline restart")
    func withdrawal() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = PhysicalSightingStore(directory: folder)
        try store.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: request())
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let preferences = Preferences(defaults: defaults)
        let service = EquipmentService()
        let services = LocomoteServices(railService: service, cache: JourneyCache(directory: folder), passport: PassportRepository(directory: folder), physicalSightings: store, mode: .preview)
        #expect(!preferences.contributionsEnabled && !preferences.backgroundLocationEnabled)
        #expect(services.revokeContributionConsent(preferences: preferences))
        #expect(store.pendingCount == 0 && store.withdrawalPending)
        #expect(!preferences.contributionsEnabled && !preferences.backgroundLocationEnabled)
        let restarted = PhysicalSightingStore(directory: folder)
        await restarted.retry(using: service)
        #expect(service.bodies.isEmpty)
        #expect(service.consents.count == 1 && service.consents[0].decision == "withdrawn")
        #expect(!restarted.remoteConsentMayExist && !restarted.withdrawalPending)
    }
    @Test("withdrawal and erasure defeat a cancellation-ignoring late report acknowledgment")
    func lateAck() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = PhysicalSightingStore(directory: folder)
        let service = EquipmentService(); service.hold = true
        try store.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: request())
        let report = try #require(store.pending(trainNumber: "12345", originDate: "2026-10-08"))
        let task = Task { try await store.submit(report, using: service) }
        for _ in 0..<100 where service.callback == nil { await Task.yield() }
        let callback = try #require(service.callback)
        try store.withdraw()
        callback.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(store.pendingCount == 0 && store.withdrawalPending)
        store.beginPrivacyDeletion()
        #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("locomote/preview/physical-reports.json").path))
    }
    @Test("disk failure prevents dispatch and changed payload cannot reuse an idempotency key")
    func immutableAndDurable() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        try Data("blocked".utf8).write(to: folder)
        let blocked = PhysicalSightingStore(directory: folder)
        #expect(throws: (any Error).self) { try blocked.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: request()) }
        #expect(blocked.pendingCount == 0)
        try FileManager.default.removeItem(at: folder)
        let store = PhysicalSightingStore(directory: folder)
        let original = try request()
        try store.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: original)
        let changed = try #require(PhysicalSighting.request(locomotive: "30211", coaches: "123456", evidenceId: original.consent.evidenceId))
        #expect(throws: URLError.self) { try store.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: changed) }
        #expect(store.pendingCount == 1)
    }
    @Test("corrupt or withdrawn disk consent fails closed but still permits explicit remote withdrawal")
    func corrupt() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("locomote/preview/physical-reports.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid".utf8).write(to: file)
        let store = PhysicalSightingStore(directory: folder)
        #expect(store.remoteConsentMayExist)
        #expect(throws: CancellationError.self) { try store.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: request()) }
        try store.withdraw()
        let service = EquipmentService()
        try await store.flushWithdrawal(using: service)
        #expect(!store.remoteConsentMayExist)
        var wire = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request())) as? [String: Any])
        var consent = wire["consent"] as! [String: Any]; consent["granted"] = false; wire["consent"] = consent
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(PhysicalSightingRequest.self, from: JSONSerialization.data(withJSONObject: wire)) }
    }

    @Test("withdrawal stops retries and attempts remote revocation even when its disk write fails")
    func withdrawalStorageFailure() async throws {
        let folder = directory(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = PhysicalSightingStore(directory: folder)
        try store.enqueue(trainNumber: "12345", originDate: "2026-10-08", request: request())
        let parent = folder.appendingPathComponent("locomote/preview")
        try FileManager.default.removeItem(at: parent)
        try Data("blocked".utf8).write(to: parent)
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let preferences = Preferences(defaults: defaults)
        preferences.contributionsEnabled = true; preferences.backgroundLocationEnabled = true
        let service = EquipmentService()
        let services = LocomoteServices(railService: service, cache: JourneyCache(directory: folder), passport: PassportRepository(directory: folder), physicalSightings: store, mode: .preview)
        await #expect(throws: (any Error).self) { try await services.withdrawPhysicalSightingConsent(preferences: preferences) }
        #expect(!preferences.contributionsEnabled && !preferences.backgroundLocationEnabled)
        #expect(store.pendingCount == 0 && store.withdrawalPending)
        #expect(service.consents.count == 1 && service.consents[0].decision == "withdrawn")
        let restarted = PhysicalSightingStore(directory: folder)
        #expect(restarted.pendingCount == 0 && restarted.withdrawalPending)
        await restarted.retry(using: service)
        #expect(service.bodies.isEmpty)
        restarted.beginPrivacyDeletion()
    }
}

@MainActor private final class EquipmentService: RailServiceProtocol {
    var fail = false
    var hold = false
    var callback: CheckedContinuation<Void, Never>?
    var bodies: [Data] = []
    var consents: [CommunityConsentEvidence] = []
    func submitPhysicalSightings(trainNumber: String, originDate: String, request: PhysicalSightingRequest) async throws -> PhysicalSightingResponse {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; bodies.append(try encoder.encode(request))
        if hold { await withCheckedContinuation { callback = $0 } }
        if fail { throw URLError(.notConnectedToInternet) }
        return .init(acceptedIds: request.sightings.indices.map { "accepted-\($0)" }, evidenceState: .init(locomotive: "proposed", rake: "proposed"), message: "Recorded")
    }
    func recordCommunityConsent(_ evidence: CommunityConsentEvidence) async throws { consents.append(evidence) }
    func exportPrivacyData() async throws -> Data { Data() }
    func deletePrivacyData() async throws {}
    func registerLiveActivityToken(runId: String, token: String, state: JourneyActivityAttributes.ContentState, revision: Int64) async throws {}
    func unregisterLiveActivity(runId: String, revision: Int64) async throws {}
    func uploadObservations(_ batch: [CompactObservation]) async throws -> [String] { [] }
    func searchTrains(_ query: String) async throws -> [TrainSearchResult] { [] }
    func journey(trainNumber: String, originDate: String) async throws -> Journey { throw URLError(.notConnectedToInternet) }
    func operationalChain(trainNumber: String, originDate: String) async throws -> OperationalChainResponse { throw URLError(.notConnectedToInternet) }
    func networkTrains(bounds: NetworkBounds) async throws -> NetworkTrainsResponse { throw URLError(.notConnectedToInternet) }
    func trainHistory(trainNumber: String, limit: Int) async throws -> TrainHistoryResponse { throw URLError(.notConnectedToInternet) }
}

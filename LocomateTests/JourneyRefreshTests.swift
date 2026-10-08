import Foundation
import Testing
@testable import Locomate

@Suite("Active dated journey refresh")
@MainActor
struct JourneyRefreshTests {
    @Test("refresh keeps visible journey and plan; concurrent requests are shared")
    func retainsVisibleStateAndCoalesces() async throws {
        let environment = try Environment()
        defer { environment.remove() }
        let first = try fixture(name: "First response")
        let service = ScriptedService(first)
        let model = environment.model(service)
        await model.load()
        let plan = try JourneyPlanLogic.create(journey: first, originDate: first.travelDate,
                                               boardingIndex: 1, alightingIndex: 2)
        await model.savePlan(plan)
        await service.pause()
        let refresh = Task { await model.refresh() }
        try await waitForCalls(service, 2)
        #expect(model.journey?.trainName == "First response")
        #expect(!model.isCached)
        let duplicate = Task { await model.refresh() }
        await Task.yield()
        #expect(await service.count == 2)
        await service.complete(1, with: try fixture(name: "Updated response"))
        await refresh.value
        await duplicate.value
        #expect(model.journey?.trainName == "Updated response")
        #expect(model.plan == plan)
        #expect(await service.consentOrRegistrationCalls == 0)
    }

    @Test("refresh failure retains honest saved data and successful recovery clears its error")
    func failureAndRecovery() async throws {
        let environment = try Environment()
        defer { environment.remove() }
        let service = ScriptedService(try fixture())
        let model = environment.model(service)
        await model.load()
        await service.failNext()
        await model.refresh()
        #expect(model.journey != nil)
        #expect(model.isCached && !model.isPreview)
        #expect(model.cachedAt != nil && model.refreshError != nil)
        #expect(model.positionDisplay != .observed)
        await service.respond(with: try fixture(name: "Recovered"))
        await model.refresh()
        #expect(model.journey?.trainName == "Recovered")
        #expect(!model.isCached && model.cachedAt == nil && model.refreshError == nil)
    }

    @Test("A to B to A rejects late replies even when train/date match again")
    func selectionEpochRejectsLateReplies() async throws {
        let environment = try Environment()
        defer { environment.remove() }
        let service = ScriptedService(nil)
        let model = environment.model(service)
        let oldA = Task { await model.load() }
        try await waitForCalls(service, 1)
        let oldB = Task { await model.update(trainNumber: "12951", originDate: "2026-09-19") }
        try await waitForCalls(service, 2)
        let newA = Task { await model.update(trainNumber: "12137", originDate: "2026-09-18") }
        try await waitForCalls(service, 3)
        await service.complete(2, with: try fixture(name: "Current A"))
        await newA.value
        await service.complete(0, with: try fixture(name: "Obsolete A"))
        await service.complete(1, with: try fixture(name: "Obsolete B", train: "12951", date: "2026-09-19"))
        await oldA.value
        await oldB.value
        #expect(model.journey?.trainName == "Current A")
        #expect(model.trainNumber == "12137" && model.originDate == "2026-09-18")
        let cached = await environment.cache.loadJourney(trainNumber: "12137", originDate: "2026-09-18")
        #expect(cached?.journey.trainName == "Current A")
    }

    @Test("active loop refreshes immediately and after 60 seconds; sleep cancellation stops it")
    func activeCadence() async throws {
        let environment = try Environment()
        defer { environment.remove() }
        let service = ScriptedService(try fixture())
        let model = environment.model(service)
        var delays: [Duration] = []
        await model.runActiveRefresh(sleep: { delay in
            delays.append(delay)
            if delays.count == 2 { throw CancellationError() }
        })
        #expect(delays == [.seconds(60), .seconds(60)])
        #expect(await service.count == 2)
        // A new active lifecycle starts immediately, without waiting a minute.
        await model.runActiveRefresh(sleep: { _ in throw CancellationError() })
        #expect(await service.count == 3)
        #expect(await service.consentOrRegistrationCalls == 0)
    }

    @Test("background cancellation cannot turn a late response into visible data or an offline error")
    func cancellationAndResume() async throws {
        let environment = try Environment()
        defer { environment.remove() }
        let service = ScriptedService(try fixture(name: "Visible"))
        let model = environment.model(service)
        await model.load()
        await service.pause()
        let active = Task { await model.runActiveRefresh() }
        try await waitForCalls(service, 2)
        active.cancel()
        model.cancelLoad()
        await service.complete(1, with: try fixture(name: "Cancelled response"))
        await active.value
        #expect(model.journey?.trainName == "Visible")
        #expect(!model.isCached && model.refreshError == nil)
        await service.respond(with: try fixture(name: "Resumed"))
        await model.runActiveRefresh(sleep: { _ in throw CancellationError() })
        #expect(model.journey?.trainName == "Resumed")
        #expect(await service.count == 3)
    }

    @Test("resume restores the saved personal plan when initial load was cancelled after displaying data")
    func cancelledInitialPlanRestoration() async throws {
        let environment = try Environment()
        defer { environment.remove() }
        let journey = try fixture()
        let plan = try JourneyPlanLogic.create(journey: journey, originDate: journey.travelDate,
                                               boardingIndex: 1, alightingIndex: 2)
        await environment.cache.savePlan(plan)
        let service = ScriptedService(journey)
        await service.pauseOperations()
        let model = environment.model(service)
        let initial = Task { await model.load() }
        for _ in 0..<100 {
            if await service.hasPendingOperations { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await service.hasPendingOperations)
        #expect(model.journey != nil && model.plan == nil)
        initial.cancel()
        model.cancelLoad()
        await service.finishOperations()
        await initial.value
        await model.refresh()
        #expect(model.plan == plan)
    }

    @Test("position freshness expires on its deadline even while the refresh request is suspended")
    func independentEvidenceClock() async throws {
        let environment = try Environment()
        defer { environment.remove() }
        let observed = Date().addingTimeInterval(-599)
        let service = ScriptedService(try fixture(observed: observed))
        let model = environment.model(service)
        await model.load()
        model.refreshClock(now: observed.addingTimeInterval(599))
        #expect(model.positionDisplay == .observed)
        #expect(abs(try #require(model.nextEvidenceDeadline).timeIntervalSince(observed.addingTimeInterval(600.001))) < 0.001)
        await service.pause()
        let refresh = Task { await model.refresh() }
        try await waitForCalls(service, 2)
        model.refreshClock(now: observed.addingTimeInterval(600.002))
        #expect(model.positionDisplay == .hidden)
        #expect(model.modeInput?.live == false)
        model.cancelLoad()
        await service.complete(1, with: try fixture(observed: observed))
        await refresh.value
        #expect(model.positionDisplay == .hidden)
        await service.respond(with: try fixture(observed: Date().addingTimeInterval(3_600)))
        await model.refresh()
        #expect(model.positionDisplay == .hidden)
        #expect(model.nextEvidenceDeadline == nil, "An invalid provider future clock must not schedule an unbounded timer.")
    }

    @MainActor private struct Environment {
        let directory: URL
        let cache: JourneyCache
        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            cache = JourneyCache(directory: directory)
        }
        func model(_ service: RailServiceProtocol) -> JourneyModel {
            JourneyModel(trainNumber: "12137", originDate: "2026-09-18", service: service,
                         cache: cache, passport: PassportRepository(directory: directory))
        }
        func remove() { try? FileManager.default.removeItem(at: directory) }
    }

    private func fixture(name: String = "Punjab Mail", train: String = "12137",
                         date: String = "2026-09-18", observed: Date? = nil) throws -> Journey {
        let file = try #require(Bundle(for: RefreshFixtureAnchor.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var raw = try #require(envelope["journey"] as? [String: Any])
        raw["trainName"] = name
        raw["trainNumber"] = train
        raw["travelDate"] = date
        raw["id"] = "run:\(train):\(date)"
        if let observed {
            var position = raw["position"] as! [String: Any]
            position["observedAt"] = observed.timeIntervalSince1970 * 1_000
            position["source"] = "official"
            raw["position"] = position
            var provenance = raw["provenance"] as! [String: Any]
            provenance["freshness"] = "live"
            raw["provenance"] = provenance
            var stops = raw["stops"] as! [[String: Any]]
            stops[0]["delayStatus"] = "observed"
            raw["stops"] = stops
        }
        return try JSONDecoder.locomote.decode(Journey.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    private func waitForCalls(_ service: ScriptedService, _ count: Int) async throws {
        for _ in 0..<100 {
            if await service.count >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await service.count == count, "Expected request did not start")
        throw CancellationError()
    }
}

private actor ScriptedService: RailServiceProtocol {
    private var response: Journey?
    private var shouldFail = false
    private var pending: [Int: CheckedContinuation<Journey, Error>] = [:]
    private var suspendedOperations = false
    private var operationContinuation: CheckedContinuation<OperationalChainResponse, Error>?
    var hasPendingOperations: Bool { operationContinuation != nil }
    func pauseOperations() { suspendedOperations = true }
    func finishOperations() {
        suspendedOperations = false
        operationContinuation?.resume(throwing: URLError(.notConnectedToInternet))
        operationContinuation = nil
    }
    private(set) var count = 0
    private(set) var consentOrRegistrationCalls = 0
    init(_ response: Journey?) { self.response = response }
    func pause() { response = nil; shouldFail = false }
    func failNext() { shouldFail = true }
    func respond(with value: Journey) { response = value; shouldFail = false }
    func complete(_ index: Int, with value: Journey) { pending.removeValue(forKey: index)?.resume(returning: value) }
    func journey(trainNumber: String, originDate: String) async throws -> Journey {
        let index = count
        count += 1
        if shouldFail { throw URLError(.notConnectedToInternet) }
        if let response { return response }
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func operationalChain(trainNumber: String, originDate: String) async throws -> OperationalChainResponse {
        if suspendedOperations {
            return try await withCheckedThrowingContinuation { operationContinuation = $0 }
        }
        throw URLError(.notConnectedToInternet)
    }
    func recordCommunityConsent(_ evidence: CommunityConsentEvidence) async throws { consentOrRegistrationCalls += 1 }
    func exportPrivacyData() async throws -> Data { Data() }
    func deletePrivacyData() async throws {}
    func searchTrains(_ query: String) async throws -> [TrainSearchResult] { [] }
    func networkTrains(bounds: NetworkBounds) async throws -> NetworkTrainsResponse { throw URLError(.notConnectedToInternet) }
    func trainHistory(trainNumber: String, limit: Int) async throws -> TrainHistoryResponse { throw URLError(.notConnectedToInternet) }
    func registerLiveActivityToken(runId: String, token: String, state: JourneyActivityAttributes.ContentState, revision: Int64) async throws { consentOrRegistrationCalls += 1 }
    func unregisterLiveActivity(runId: String, revision: Int64) async throws {}
    func uploadObservations(_ batch: [CompactObservation]) async throws -> [String] { consentOrRegistrationCalls += 1; return [] }
}
private final class RefreshFixtureAnchor: NSObject {}

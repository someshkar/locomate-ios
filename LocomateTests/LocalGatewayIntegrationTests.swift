import Foundation
import Testing
@testable import Locomate

/// Run with LOCOMOTE_LOCAL_GATEWAY_URL=http://127.0.0.1:8787 after starting
/// Wrangler locally. CI skips this because current public-feed data is external.
@Suite(
    "Local gateway integration",
    .enabled(if: ProcessInfo.processInfo.environment["LOCOMOTE_LOCAL_GATEWAY_URL"]?
        .hasPrefix("http://127.0.0.1:") == true)
)
struct LocalGatewayIntegrationTests {
    @Test("native service decodes current search, journey, and network responses")
    func currentPublicFeed() async throws {
        let rawURL = try #require(ProcessInfo.processInfo.environment["LOCOMOTE_LOCAL_GATEWAY_URL"])
        let baseURL = try RailAPIURL.validate(rawURL, development: true)
        let client = APIClient(
            baseURL: baseURL,
            tokenStore: InMemoryTokenStore(),
            installationId: UUID().uuidString
        )
        let service = RailService(client: client)
        let search = try await service.searchTrains("12137")
        #expect(search.contains { $0.number == "12137" })

        let journey = try await service.journey(trainNumber: "12137", originDate: IndiaDate.today())
        #expect(journey.trainNumber == "12137")
        #expect(journey.stops.count > 1)
        #expect(journey.routeCoordinates?.isEmpty == false)
        let working = try await service.operationalChain(trainNumber: "12137", originDate: IndiaDate.today())
        #expect(working.trainNumber == "12137" && working.originDate == IndiaDate.today())

        let network = try await service.networkTrains(
            bounds: NetworkBounds(west: 68, south: 7, east: 97, north: 36)
        )
        #expect(!network.trains.isEmpty)
    }
}

extension LocalGatewayIntegrationTests {
    @Test("native delivery revision withdrawal defeats a late registration and physical reads decode")
    func deliveryContract() async throws {
        let url = try RailAPIURL.validate(#require(ProcessInfo.processInfo.environment["LOCOMOTE_LOCAL_GATEWAY_URL"]), development: true)
        let service = RailService(client: APIClient(baseURL: url, tokenStore: InMemoryTokenStore(), installationId: UUID().uuidString))
        let date = IndiaDate.today()
        _ = try await service.journey(trainNumber: "12137", originDate: date)
        let physical = try await service.physicalChain(trainNumber: "12137", originDate: date)
        #expect(physical.runId == "run:12137:\(date)")
        let runId = "run:12137:\(date)"
        let revision = Int64(Date().timeIntervalSince1970 * 1_000) * 1_000
        let state = JourneyActivityAttributes.ContentState(nextStation: "DR", eta: "19:47", delayMinutes: 2.5,
            delayLabel: "2.5 minutes late", distanceToNextKm: 8.9, confidence: "MEDIUM", etaLabel: "Scheduled arrival")
        try await service.registerLiveActivityToken(runId: runId, token: String(repeating: "ab", count: 32), state: state, revision: revision)
        try await service.unregisterLiveActivity(runId: runId, revision: revision + 1)
        do {
            try await service.registerLiveActivityToken(runId: runId, token: String(repeating: "ab", count: 32), state: state, revision: revision)
            Issue.record("A late registration must not revive a withdrawn token")
        } catch let error as APIError {
            #expect(error.status == 409 && error.currentRevision == revision + 1)
        }
    }
}

extension LocalGatewayIntegrationTests {
    @Test("native physical sighting replay preserves evidence IDs and later withdrawal rejects stale consent")
    func physicalWriteContract() async throws {
        let url = try RailAPIURL.validate(#require(ProcessInfo.processInfo.environment["LOCOMOTE_LOCAL_GATEWAY_URL"]), development: true)
        let service = RailService(client: APIClient(baseURL: url, tokenStore: InMemoryTokenStore(), installationId: UUID().uuidString))
        // The local Worker owns a synthetic in-window 12345 run. No public or remote writes occur.
        let date = IndiaDate.today()
        let report = try #require(PhysicalSighting.request(locomotive: "30210", coaches: "123456", evidenceId: UUID().uuidString))
        let first = try await service.submitPhysicalSightings(trainNumber: "12345", originDate: date, request: report)
        let replay = try await service.submitPhysicalSightings(trainNumber: "12345", originDate: date, request: report)
        #expect(first.acceptedIds == replay.acceptedIds && first.acceptedIds.count == 2)
        // Other isolated probes can have contributed independent evidence for this run.
        // Replay must preserve the server's evidence state, whichever truthful state it reached.
        #expect(first.evidenceState.locomotive == replay.evidenceState.locomotive && first.evidenceState.rake == replay.evidenceState.rake)
        try await service.recordCommunityConsent(CommunityConsentEvidence(granted: false))
        let stale = try #require(PhysicalSighting.request(locomotive: "30211", coaches: "", now: Date(timeIntervalSince1970: Double(report.consent.consentedAt) / 1_000), evidenceId: UUID().uuidString))
        do {
            _ = try await service.submitPhysicalSightings(trainNumber: "12345", originDate: date, request: stale)
            Issue.record("Earlier consent must never revive sharing after withdrawal")
        } catch let error as APIError { #expect(error.status == 403 || error.status == 409) }
    }
}


extension LocalGatewayIntegrationTests {
    @Test("native GPS queue canonicalizes legacy IDs, replays exactly, and cannot contribute after withdrawal or erasure")
    func gpsContributionContract() async throws {
        let url = try RailAPIURL.validate(#require(ProcessInfo.processInfo.environment["LOCOMOTE_LOCAL_GATEWAY_URL"]), development: true)
        let service = RailService(client: APIClient(baseURL: url, tokenStore: InMemoryTokenStore(), installationId: UUID().uuidString))
        let date = IndiaDate.today()
        let journey = try await service.journey(trainNumber: "12137", originDate: date)
        let point = try #require(journey.routeCoordinates?.first)
        try await service.recordCommunityConsent(CommunityConsentEvidence(granted: true))
        let now = Int(Date().timeIntervalSince1970 * 1_000)
        func sample(_ offset: Int, run: String) -> CompactObservation {
            .init(runId: run, timestamp: now + offset, latE5: Int((point.latitude * 100_000).rounded()),
                  lonE5: Int((point.longitude * 100_000).rounded()), speedKph: 80, accuracyM: 30,
                  routeProgress: 0, matchDistanceM: 0, consentVersion: Consent.version)
        }
        let legacy = sample(-2_000, run: "12137-\(date)")
        let canonical = sample(-1_000, run: journey.id)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let queue = ObservationQueue(directory: folder, scope: "local-proof")
        queue.append(legacy); queue.append(canonical)
        let bytes = try ObservationBatchCodec.encode(queue.peek(limit: 100))
        let tuples = try #require(bytes.body["observations"] as? [[Any]])
        #expect(tuples.allSatisfy { $0[1] as? String == journey.id })
        let first = try await service.uploadObservations(queue.peek(limit: 100))
        let replay = try await service.uploadObservations(queue.peek(limit: 100))
        #expect(Set(first) == ["\(legacy.runId):\(legacy.timestamp)", "\(canonical.runId):\(canonical.timestamp)"])
        #expect(first == replay)
        let sync = ObservationSync(queue: queue, service: service)
        let outcome = await sync.flush(consentGranted: true, maxBatches: 1)
        #expect(outcome.uploaded == 2 && outcome.remaining == 0 && !outcome.failed)
        try await service.recordCommunityConsent(CommunityConsentEvidence(granted: false))
        do {
            _ = try await service.uploadObservations([sample(0, run: journey.id)])
            Issue.record("Withdrawn GPS sharing must not upload a new batch")
        } catch let error as APIError { #expect(error.status == 403) }
        try await service.deletePrivacyData()
        do {
            _ = try await service.uploadObservations([sample(1, run: journey.id)])
            Issue.record("Erased installation must not contribute")
        } catch let error as APIError { #expect(error.status == 401) }
    }
}

import Foundation
import Testing
@testable import Locomate

@Suite("Durable journey restoration")
@MainActor
struct JourneyRestorationTests {
    @Test("a new store restores the exact dated route only in its source scope")
    func scopedRoundTripAndExport() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = Routes.JourneyDestination(trainNumber: "01234", date: "2024-02-29")
        let store = SelectedJourneyStore(directory: directory, scope: "gateway-a", privacyDeletionPending: { false })
        try store.save(destination)
        let reopened = SelectedJourneyStore(directory: directory, scope: "gateway-a", privacyDeletionPending: { false })
        #expect(reopened.load() == destination)
        #expect(SelectedJourneyStore(directory: directory, scope: "gateway-b", privacyDeletionPending: { false }).load() == nil)
        #expect(SelectedJourneyStore(directory: directory, scope: "preview", privacyDeletionPending: { false }).load() == nil)
        let file = directory.appendingPathComponent("locomote/gateway-a/selected-journey.json")
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let exported = try LocomoteServices.exportLocalFilesBase64(
            documentRoot: directory.appendingPathComponent("locomote"), cacheRoot: directory.appendingPathComponent("unused"))
        #expect(exported["Documents/locomote/gateway-a/selected-journey.json"] == (try Data(contentsOf: file)).base64EncodedString())
    }

    @Test("malformed records and invalid route fields never restore")
    func validation() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SelectedJourneyStore(directory: directory, scope: "preview", privacyDeletionPending: { false })
        #expect(throws: SelectedJourneyStore.StorageError.self) {
            try store.save(.init(trainNumber: "12137\n", date: "2026-10-01"))
        }
        #expect(throws: SelectedJourneyStore.StorageError.self) {
            try store.save(.init(trainNumber: "12137", date: "2026-02-29"))
        }
        try store.save(.init(trainNumber: "12137", date: "2026-10-01"))
        let file = directory.appendingPathComponent("locomote/preview/selected-journey.json")
        try Data("{\"trainNumber\":\"12137\",\"originDate\":\"invalid\"}".utf8).write(to: file)
        #expect(store.load() == nil)
        try Data("truncated".utf8).write(to: file)
        #expect(store.load() == nil)
    }

    @Test("pending deletion and invalidated old services cannot restore or recreate selection")
    func deletionCannotReviveSelection() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let latch = Latch()
        let store = SelectedJourneyStore(directory: directory, scope: "gateway-a", privacyDeletionPending: { latch.pending })
        let destination = Routes.JourneyDestination(trainNumber: "12137", date: "2026-10-01")
        try store.save(destination)
        latch.pending = true
        store.beginPrivacyDeletion()
        let duringDeletion = SelectedJourneyStore(directory: directory, scope: "gateway-a", privacyDeletionPending: { latch.pending })
        #expect(duringDeletion.load() == nil)
        #expect(throws: SelectedJourneyStore.StorageError.self) { try duringDeletion.save(destination) }
        // This is the same all-scope private root erased by Services.
        try FileManager.default.removeItem(at: directory.appendingPathComponent("locomote"))
        latch.pending = false
        #expect(store.load() == nil)
        #expect(throws: SelectedJourneyStore.StorageError.self) { try store.save(destination) }
        #expect(SelectedJourneyStore(directory: directory, scope: "gateway-a", privacyDeletionPending: { false }).load() == nil)
    }

    @Test("saved ISO dates decode and a new offline model loads the aged production run")
    func cacheRoundTripAndOfflineRecovery() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journey = try fixtureJourney()
        let cache = JourneyCache(directory: directory, scope: "gateway-a")
        await cache.saveJourney(journey, originDate: "2026-09-18")
        let reopened = JourneyCache(directory: directory, scope: "gateway-a")
        let stored = try #require(await reopened.loadJourney(trainNumber: "12137", originDate: "2026-09-18"))
        #expect(stored.journey.id == journey.id)
        #expect(abs(stored.cachedAt.timeIntervalSinceNow) < 5)
        #expect(await JourneyCache(directory: directory, scope: "gateway-b").loadJourney(trainNumber: "12137", originDate: "2026-09-18") == nil)
        let model = JourneyModel(trainNumber: "12137", originDate: "2026-09-18", service: OfflineService(),
                                 cache: reopened, passport: PassportRepository(directory: directory, scope: "gateway-a"))
        await model.load()
        #expect(model.journey?.id == journey.id)
        #expect(model.isCached && !model.isPreview)
        #expect(model.cachedAt == stored.cachedAt)
        #expect(StatusMapping.journeyModeLabel(model.statusKind, cached: model.isCached) == "SAVED JOURNEY")
        #expect(StatusMapping.journeyModeLabel(.scheduled) == "UPCOMING JOURNEY")
        #expect(StatusMapping.journeyModeLabel(.preview, cached: true) == "ROUTE REPLAY")
        #expect(StatusMapping.journeyModeLabel(.error, cached: true) == "UNAVAILABLE")
    }

    @Test("restoration cannot start contribution, but a later explicit grant or selection can")
    func explicitGrantReleasesRestorationGate() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "restoration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults, consentScope: "test")
        let services = LocomoteServices(railService: OfflineService(), cache: JourneyCache(directory: directory),
            passport: PassportRepository(directory: directory),
            contribution: ContributionService(scope: suite, consentDirectory: directory),
            mode: .production(baseURL: URL(string: "https://example.test")!),
            journeyAlerts: JourneyAlertService(api: nil, scope: suite, directory: directory),
            selectedJourney: SelectedJourneyStore(directory: directory, scope: suite, privacyDeletionPending: { false }))
        let restored = RootView.JourneyRequest(trainNumber: "12137", originDate: "2026-09-18", restored: true,
                                               contributionActivationRevision: services.contributionActivationRevision)
        #expect(!restored.allowsContribution(currentActivationRevision: services.contributionActivationRevision))
        #expect(!preferences.contributionsEnabled)
        #expect(services.contribution.state == .idle)
        try await services.grantContributionConsent(preferences: preferences)
        #expect(preferences.contributionsEnabled)
        #expect(restored.allowsContribution(currentActivationRevision: services.contributionActivationRevision))
        #expect(services.contribution.state == .idle, "Consent grant alone still does not start the location manager.")
        #expect(services.journeyAlerts.subscriptions.isEmpty)
        let selected = RootView.JourneyRequest(trainNumber: "12137", originDate: "2026-09-18")
        #expect(selected.allowsContribution(currentActivationRevision: 0))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }
    private func fixtureJourney() throws -> Journey {
        struct Envelope: Decodable { let journey: Journey }
        let file = try #require(Bundle(for: RestorationFixtureAnchor.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        return try JSONDecoder.locomote.decode(Envelope.self, from: Data(contentsOf: file)).journey
    }
    @MainActor private final class Latch { var pending = false }
    private struct OfflineService: RailServiceProtocol {
        func recordCommunityConsent(_ evidence: CommunityConsentEvidence) async throws {}
        func exportPrivacyData() async throws -> Data { Data("{}".utf8) }
        func deletePrivacyData() async throws {}
        func searchTrains(_ query: String) async throws -> [TrainSearchResult] { [] }
        func journey(trainNumber: String, originDate: String) async throws -> Journey { throw URLError(.notConnectedToInternet) }
        func operationalChain(trainNumber: String, originDate: String) async throws -> OperationalChainResponse { throw URLError(.notConnectedToInternet) }
        func networkTrains(bounds: NetworkBounds) async throws -> NetworkTrainsResponse { throw URLError(.notConnectedToInternet) }
        func trainHistory(trainNumber: String, limit: Int) async throws -> TrainHistoryResponse { throw URLError(.notConnectedToInternet) }
        func registerLiveActivityToken(runId: String, token: String, state: JourneyActivityAttributes.ContentState, revision: Int64) async throws {}
        func unregisterLiveActivity(runId: String, revision: Int64) async throws {}
        func uploadObservations(_ batch: [CompactObservation]) async throws -> [String] { [] }
    }
}
private final class RestorationFixtureAnchor: NSObject {}

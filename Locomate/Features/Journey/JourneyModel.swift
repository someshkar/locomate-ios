//
//  JourneyModel.swift
//  Locomate
//
//  Journey state: loads a run (production) or builds a historical replay
//  (preview), caches the last good result, and derives the honest mode.
//

import Foundation
import Observation

@MainActor
@Observable
public final class JourneyModel {
    public enum Phase {
        case idle
        case loading
        case loaded(Journey)
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var physicalChain: PhysicalChainResponse?
    public private(set) var operations: OperationalChainResponse?
    public private(set) var plan: JourneyPlan?
    public private(set) var cachedAt: Date?
    public private(set) var isCached = false
    public private(set) var isPreview = false
    public private(set) var planNotice: String?
    public private(set) var refreshError: String?
    public private(set) var evidenceNow = Date()

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var loadID: UUID?
    @ObservationIgnored private var selectionID = UUID()

    public var trainNumber: String
    public var originDate: String

    private let service: RailServiceProtocol?
    private let cache: JourneyCache
    private let physicalSightings: PhysicalSightingStore
    private let passport: PassportRepository
    private let liveActivity: LiveActivityService
    private var pendingSavedJourney: SavedJourney?
    private var planLoaded = false
    private var lastLoadedAt: Date?

    public init(
        trainNumber: String = "12137",
        originDate: String = IndiaDate.today(),
        service: RailServiceProtocol?,
        cache: JourneyCache,
        passport: PassportRepository,
        liveActivity: LiveActivityService = LiveActivityService(),
        physicalSightings: PhysicalSightingStore = PhysicalSightingStore(),
        savedJourney: SavedJourney? = nil
    ) {
        self.trainNumber = trainNumber
        self.originDate = originDate
        self.service = service
        self.cache = cache
        self.passport = passport
        self.liveActivity = liveActivity
        self.physicalSightings = physicalSightings
        self.pendingSavedJourney = savedJourney
    }

    public var journey: Journey? {
        if case .loaded(let journey) = phase { return journey }
        return nil
    }

    public var modeInput: JourneyModeInput? {
        guard let journey else { return nil }
        return JourneyMode.input(
            journey: journey,
            cached: isCached,
            preview: isPreview,
            historicalRoute: isPreview,
            originDate: originDate,
            error: {
                if case .failed = phase { return "failed" }
                return nil
            }(),
            now: evidenceNow
        )
    }

    public var statusKind: StatusKind {
        if case .failed = phase { return .error }
        guard let modeInput else { return .scheduled }
        return StatusMapping.statusForJourneyMode(modeInput)
    }

    // MARK: Loading

    public func load() async { await requestLoad(preserveVisible: false) }

    /// The existing card stays usable while its dated run is revalidated.
    public func refresh() async { await requestLoad(preserveVisible: true) }

    /// A caller owns this task for one active scene/selection. Cancelling it
    /// cancels the request as well as the delay; resuming starts with a refresh.
    func runActiveRefresh(refreshImmediately: Bool = true,
                          sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                          didRefresh: () async -> Void = {}) async {
        if refreshImmediately {
            await refresh()
            guard !Task.isCancelled else { return }
            await didRefresh()
        }
        while !Task.isCancelled {
            do { try await sleep(.seconds(60)) } catch { return }
            guard !Task.isCancelled else { return }
            await refresh()
            guard !Task.isCancelled else { return }
            await didRefresh()
        }
    }

    public var positionDisplay: JourneyPositionDisplay {
        guard let journey else { return .hidden }
        return JourneyPositionEvidence.display(journey: journey, cached: isCached,
                                                preview: isPreview, now: evidenceNow)
    }

    /// Independent from network completion, including while a request hangs.
    func refreshClock(now: Date = Date()) { evidenceNow = now }

    var nextEvidenceDeadline: Date? {
        guard let journey, !isPreview, journey.position.observedAt.isFinite,
              journey.position.observedAt > 0 else { return nil }
        let observed = Date(timeIntervalSince1970: journey.position.observedAt / 1_000)
        if observed > evidenceNow {
            // Bad provider clocks must not create an unbounded sleep duration.
            return observed.timeIntervalSince(evidenceNow) <= 60 ? observed : nil
        }
        switch positionDisplay {
        case .observed: return observed.addingTimeInterval(10 * 60 + 0.001)
        case .stale: return observed.addingTimeInterval(72 * 60 * 60 + 0.001)
        case .hidden, .preview: return nil
        }
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadID = nil
    }

    private func requestLoad(preserveVisible: Bool) async {
        guard !Task.isCancelled, !PrivacyDeletionLatch.isPending else { return }
        // A Retry tap and a lifecycle refresh share the current request.
        if let loadTask { await loadTask.value; return }
        let id = UUID()
        loadID = id
        let task = Task { await performLoad(preserveVisible: preserveVisible, id: id) }
        loadTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if loadID == id { loadTask = nil; loadID = nil }
    }

    private func performLoad(preserveVisible: Bool, id: UUID) async {
        let requestedTrainNumber = trainNumber
        let requestedOriginDate = originDate
        let previousJourney = journey
        let previousCachedAt = cachedAt ?? lastLoadedAt
        let restorePlan = !preserveVisible || !planLoaded
        func current() -> Bool {
            loadID == id && !Task.isCancelled && !PrivacyDeletionLatch.isPending
                && trainNumber == requestedTrainNumber && originDate == requestedOriginDate
        }
        guard current() else { return }
        let pack = RoutePackStore.pack(requestedTrainNumber)
        if let service {
            if !preserveVisible || previousJourney == nil { phase = .loading }
            do {
                let loaded = try await service.journey(trainNumber: requestedTrainNumber, originDate: requestedOriginDate)
                guard current() else { return }
                try JourneyIdentity.validate(loaded, trainNumber: requestedTrainNumber, originDate: requestedOriginDate)
                isPreview = false
                isCached = false
                cachedAt = nil
                refreshError = nil
                refreshClock()
                lastLoadedAt = evidenceNow
                phase = .loaded(loaded)
                await cache.saveJourney(loaded, originDate: requestedOriginDate)
                guard current() else { return }
                let loadedOperations = try? await service.operationalChain(
                    trainNumber: requestedTrainNumber, originDate: requestedOriginDate
                )
                guard current() else { return }
                operations = loadedOperations?.trainNumber == requestedTrainNumber && loadedOperations?.originDate == requestedOriginDate ? loadedOperations : nil
                let physical = try? await service.physicalChain(trainNumber: requestedTrainNumber, originDate: requestedOriginDate)
                guard current() else { return }
                physicalChain = physical?.runId == loaded.id ? physical : nil
                // Only sync a Live Activity the traveller previously started.
                if liveActivity.isRunning(for: loaded.id) {
                    await liveActivity.sync(
                        journey: loaded, registerToken: tokenRegistrar(for: loaded.id),
                        unregisterRun: tokenUnregisterer()
                    )
                } else {
                    await liveActivity.end(unregisterRun: tokenUnregisterer())
                }
            } catch {
                // Cancellation is lifecycle control, not an offline response.
                guard current() else { return }
                await liveActivity.end(unregisterRun: tokenUnregisterer())
                guard current() else { return }
                let cached = await cache.loadJourney(trainNumber: requestedTrainNumber, originDate: requestedOriginDate)
                guard current() else { return }
                refreshError = error.localizedDescription
                refreshClock()
                if let retained = cached?.journey ?? previousJourney {
                    isPreview = false
                    isCached = true
                    cachedAt = cached?.cachedAt ?? previousCachedAt
                    phase = .loaded(retained)
                } else {
                    isPreview = false
                    isCached = false
                    cachedAt = nil
                    operations = nil
                    phase = .failed(error.localizedDescription)
                }
            }
        } else if let pack {
            await liveActivity.end(unregisterRun: tokenUnregisterer())
            guard current() else { return }
            presentPreview(pack)
        } else {
            await liveActivity.end(unregisterRun: tokenUnregisterer())
            guard current() else { return }
            phase = .failed("No route pack is bundled for \(requestedTrainNumber).")
        }

        guard current() else { return }
        if let saved = pendingSavedJourney, let journey {
            pendingSavedJourney = nil
            if let resolved = PassportReopening.plan(for: saved, journey: journey, originDate: requestedOriginDate) {
                plan = resolved
                planNotice = nil
            } else {
                plan = JourneyPlanLogic.default(journey: journey, originDate: requestedOriginDate)
                planNotice = "The saved boarding and drop-off calls no longer match this timetable. Showing the full route; choose your stops in Edit."
            }
            planLoaded = true
            if let plan { await cache.savePlan(plan) }
            return
        }
        if restorePlan {
            let loadedPlan = await cache.loadPlan(trainNumber: requestedTrainNumber, originDate: requestedOriginDate)
            guard current() else { return }
            plan = loadedPlan
            planLoaded = true
        }
    }

    /// Registers a push-to-update token for gateway delivery when configured.
    private func tokenRegistrar(for runId: String) -> (@MainActor (String, JourneyActivityAttributes.ContentState, Int64) async throws -> Void)? {
        guard let service else { return nil }
        return { token, state, revision in
            // Best-effort: a failed registration must not break the journey.
            try await service.registerLiveActivityToken(runId: runId, token: token, state: state, revision: revision)
        }
    }

    private func tokenUnregisterer() -> (@MainActor (String, Int64) async throws -> Void)? {
        guard let service else { return nil }
        return { runId, revision in
            // A stopped card must disappear immediately even if the gateway is offline.
            try await service.unregisterLiveActivity(runId: runId, revision: revision)
        }
    }

    private func presentPreview(_ pack: OpenRoutePack) {
        isPreview = true
        isCached = false
        cachedAt = nil
        let journey = PreviewData.journey(from: pack, originDate: originDate)
        phase = .loaded(journey)
        operations = PreviewData.operations(from: pack, originDate: originDate)
    }

    public var liveActivityRegistrationMessage: String? { liveActivity.registrationMessage }

    // MARK: Actions

    public var pendingPhysicalReport: PhysicalSightingStore.Pending? { physicalSightings.pending(trainNumber: trainNumber, originDate: originDate) }
    public func discardPhysicalReport(_ id: String) throws { try physicalSightings.discard(id) }

    public var canReportPhysicalSightings: Bool {
        guard !isPreview, !isCached, !PrivacyDeletionLatch.isPending, let journey else { return false }
        return ContributionObservation.isWithinRunWindow(originDate: originDate, departureTime: journey.departureTime,
            durationMinutes: journey.scheduledDurationMinutes)
    }

    public func submitPhysicalSightings(_ request: PhysicalSightingRequest) async throws -> PhysicalSightingResponse {
        guard !isPreview, !isCached, !PrivacyDeletionLatch.isPending, let service, let journey else { throw URLError(.unsupportedURL) }
        guard canReportPhysicalSightings else { throw URLError(.unsupportedURL) }
        let requestedID = journey.id
        let selection = selectionID
        try physicalSightings.enqueue(trainNumber: trainNumber, originDate: originDate, request: request)
        guard let queued = physicalSightings.pending(trainNumber: trainNumber, originDate: originDate) else { throw CancellationError() }
        let result = try await physicalSightings.submit(queued, using: service)
        guard !PrivacyDeletionLatch.isPending, self.journey?.id == requestedID, selectionID == selection else { throw CancellationError() }
        let chain = try? await service.physicalChain(trainNumber: trainNumber, originDate: originDate)
        if self.journey?.id == requestedID, selectionID == selection, !PrivacyDeletionLatch.isPending, chain?.runId == requestedID { physicalChain = chain }
        return result
    }

    public func savePlan(_ plan: JourneyPlan) async {
        self.plan = plan
        planLoaded = true
        planNotice = nil
        await cache.savePlan(plan)
    }

    public func saveToPassport() async -> String {
        guard let journey else { return "Nothing to save yet." }
        let saved = Passport.makeSaved(journey: journey, originDate: originDate, plan: plan, preview: isPreview)
        var journeys = await passport.load()
        journeys.removeAll { $0.id == saved.id }
        journeys.append(saved)
        await passport.save(journeys)
        return "Journey saved privately on this device."
    }

    public func update(trainNumber: String, originDate: String, savedJourney: SavedJourney? = nil) async {
        cancelLoad()
        let selection = UUID()
        selectionID = selection
        let changedRun = self.trainNumber != trainNumber || self.originDate != originDate
        self.trainNumber = trainNumber
        self.originDate = originDate
        pendingSavedJourney = savedJourney
        planNotice = nil
        if changedRun {
            phase = .idle
            operations = nil
            physicalChain = nil
            plan = nil
            planLoaded = false
            refreshError = nil
            lastLoadedAt = nil
            await liveActivity.end(unregisterRun: tokenUnregisterer())
        }
        guard !Task.isCancelled, selectionID == selection else { return }
        await load()
    }

    public func isLiveActivityRunning(for runId: String) -> Bool {
        liveActivity.isRunning(for: runId)
    }

    /// Start a Lock Screen journey card only after an explicit tap.
    public func startLiveActivity() async -> Bool {
        guard !isPreview, !isCached, let journey else { return false }
        return await liveActivity.sync(
            journey: journey, registerToken: tokenRegistrar(for: journey.id),
            unregisterRun: tokenUnregisterer()
        )
    }

    /// End the Lock Screen journey card.
    public func endLiveActivity() async {
        await liveActivity.end(unregisterRun: tokenUnregisterer())
    }
}

/// Resolve the app's runtime data mode once.
public enum RailModeResolver {
    public static let mode: RailDataMode = RailDataMode.resolve()
}

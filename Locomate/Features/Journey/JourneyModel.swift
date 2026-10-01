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
    public private(set) var operations: OperationalChainResponse?
    public private(set) var plan: JourneyPlan?
    public private(set) var cachedAt: Date?
    public private(set) var isCached = false
    public private(set) var isPreview = false

    public var trainNumber: String
    public var originDate: String

    private let service: RailServiceProtocol?
    private let cache: JourneyCache
    private let passport: PassportRepository
    private let liveActivity = LiveActivityService()

    public init(
        trainNumber: String = "12137",
        originDate: String = IndiaDate.today(),
        service: RailServiceProtocol?,
        cache: JourneyCache,
        passport: PassportRepository
    ) {
        self.trainNumber = trainNumber
        self.originDate = originDate
        self.service = service
        self.cache = cache
        self.passport = passport
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
            }()
        )
    }

    public var statusKind: StatusKind {
        if case .failed = phase { return .error }
        guard let modeInput else { return .scheduled }
        return StatusMapping.statusForJourneyMode(modeInput)
    }

    // MARK: Loading

    public func load() async {
        let requestedTrainNumber = trainNumber
        let requestedOriginDate = originDate
        // Preview packs are always available, even offline.
        let pack = RoutePackStore.pack(requestedTrainNumber)

        if let service {
            phase = .loading
            do {
                let loaded = try await service.journey(trainNumber: requestedTrainNumber, originDate: requestedOriginDate)
                guard trainNumber == requestedTrainNumber, originDate == requestedOriginDate else { return }
                isPreview = false
                isCached = false
                cachedAt = nil
                phase = .loaded(loaded)
                await cache.saveJourney(loaded, originDate: requestedOriginDate)
                let loadedOperations = try? await service.operationalChain(
                    trainNumber: requestedTrainNumber, originDate: requestedOriginDate
                )
                guard trainNumber == requestedTrainNumber, originDate == requestedOriginDate else { return }
                operations = loadedOperations
                // Restore only a Live Activity that the traveller started for this run.
                if liveActivity.isRunning(for: loaded.id) {
                    await liveActivity.sync(journey: loaded, registerToken: tokenRegistrar(for: loaded.id))
                } else {
                    await liveActivity.end()
                }
            } catch {
                guard trainNumber == requestedTrainNumber, originDate == requestedOriginDate else { return }
                await liveActivity.end()
                guard trainNumber == requestedTrainNumber, originDate == requestedOriginDate else { return }
                // Retain the last good journey rather than falling through to fixtures.
                if let cached = await cache.loadJourney(trainNumber: requestedTrainNumber, originDate: requestedOriginDate) {
                    guard trainNumber == requestedTrainNumber, originDate == requestedOriginDate else { return }
                    isPreview = false
                    isCached = true
                    cachedAt = cached.cachedAt
                    phase = .loaded(cached.journey)
                } else {
                    isPreview = false
                    isCached = false
                    cachedAt = nil
                    operations = nil
                    phase = .failed(error.localizedDescription)
                }
            }
        } else if let pack {
            await liveActivity.end()
            guard trainNumber == requestedTrainNumber, originDate == requestedOriginDate else { return }
            presentPreview(pack)
        } else {
            await liveActivity.end()
            guard trainNumber == requestedTrainNumber, originDate == requestedOriginDate else { return }
            phase = .failed("No route pack is bundled for \(requestedTrainNumber).")
        }

        let loadedPlan = await cache.loadPlan(trainNumber: requestedTrainNumber, originDate: requestedOriginDate)
        guard trainNumber == requestedTrainNumber, originDate == requestedOriginDate else { return }
        plan = loadedPlan
    }

    /// Registers a push-to-update token for gateway delivery when configured.
    private func tokenRegistrar(for runId: String) -> ((String) async -> Void)? {
        guard let service else { return nil }
        return { token in
            // Best-effort: a failed registration must not break the journey.
            _ = try? await service.registerLiveActivityToken(runId: runId, token: token)
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

    // MARK: Actions

    public func savePlan(_ plan: JourneyPlan) async {
        self.plan = plan
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

    public func update(trainNumber: String, originDate: String) async {
        let changedRun = self.trainNumber != trainNumber || self.originDate != originDate
        self.trainNumber = trainNumber
        self.originDate = originDate
        if changedRun {
            await liveActivity.end()
        }
        await load()
    }

    public func isLiveActivityRunning(for runId: String) -> Bool {
        liveActivity.isRunning(for: runId)
    }

    /// Start a Lock Screen journey card only after an explicit tap.
    public func startLiveActivity() async -> Bool {
        guard !isPreview, !isCached, let journey else { return false }
        return await liveActivity.sync(journey: journey, registerToken: tokenRegistrar(for: journey.id))
    }

    /// End the Lock Screen journey card.
    public func endLiveActivity() async {
        await liveActivity.end()
    }
}

/// Resolve the app's runtime data mode once.
public enum RailModeResolver {
    public static let mode: RailDataMode = RailDataMode.resolve()
}

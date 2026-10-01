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
        // Preview packs are always available, even offline.
        let pack = RoutePackStore.pack(trainNumber)

        if let service {
            phase = .loading
            do {
                let loaded = try await service.journey(trainNumber: trainNumber, originDate: originDate)
                isPreview = false
                isCached = false
                cachedAt = nil
                phase = .loaded(loaded)
                await cache.saveJourney(loaded, originDate: originDate)
                operations = try? await service.operationalChain(trainNumber: trainNumber, originDate: originDate)
                // Keep the Live Activity / Dynamic Island in step with the run.
                await liveActivity.sync(journey: loaded, registerToken: tokenRegistrar)
            } catch {
                // Retain the last good journey rather than falling through to fixtures.
                if let cached = await cache.loadJourney(trainNumber: trainNumber, originDate: originDate) {
                    isPreview = false
                    isCached = true
                    cachedAt = cached.cachedAt
                    phase = .loaded(cached.journey)
                } else {
                    isPreview = false
                    isCached = false
                    cachedAt = nil
                    operations = nil
                    await liveActivity.end()
                    phase = .failed(error.localizedDescription)
                }
            }
        } else if let pack {
            presentPreview(pack)
        } else {
            phase = .failed("No route pack is bundled for \(trainNumber).")
        }

        plan = await cache.loadPlan(trainNumber: trainNumber, originDate: originDate)
    }

    /// Registers a push-to-update token with the gateway for server-driven ETA.
    private var tokenRegistrar: ((String) async -> Void)? {
        guard let service else { return nil }
        return { token in
            // Best-effort: a failed registration must not break the journey.
            _ = try? await (service as? RailService)?.registerLiveActivityToken(
                runId: self.trainNumber, token: token
            )
        }
    }

    private func presentPreview(_ pack: OpenRoutePack) {
        isPreview = true
        // Preview is never live, so any existing activity must end.
        Task { await liveActivity.end() }
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
        self.trainNumber = trainNumber
        self.originDate = originDate
        await load()
    }

    /// End the Live Activity (e.g. when alerts are turned off).
    public func endLiveActivity() async {
        await liveActivity.end()
    }
}

/// Resolve the app's runtime data mode once.
public enum RailModeResolver {
    public static let mode: RailDataMode = RailDataMode.resolve()
}

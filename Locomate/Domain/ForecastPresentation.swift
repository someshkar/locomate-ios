//
//  ForecastPresentation.swift
//  Locomate
//
//  Forecast explanation labels, source labels and station callouts — ported
//  from SmartRail `src/domain/types.ts` (formatRailTime, forecastEvidence,
//  stationCallout, stopDelayChange, featureFreshness).
//

import Foundation

public enum ForecastPresentation {
    static let evidence: [StopForecastExplanationCode: String] = [
        .actualEventObserved: "Actual station event observed",
        .releasedEmpiricalResidual: "Released empirical evidence applied",
        .currentDelayBaseline: "Current delay applied to the schedule",
        .currentDelayUnknown: "Current delay is unknown",
        .insufficientGroupSupport: "Too few comparable journeys for the released model",
        .noReleasedEmpiricalGroup: "No released empirical model covers this stop",
        .continuityConfirmed: "Train-set continuity confirmed",
        .continuityUnverified: "Train-set continuity is unverified",
        .transitionAfterDepartureIgnored: "Transition evidence arrived after departure and was ignored",
        .physicalTransitionBinding: "Physical transition sets the earliest feasible time",
        .serviceReadinessBinding: "Service readiness sets the earliest feasible time",
        .rakeReadinessBinding: "Train-set readiness sets the earliest feasible time",
        .locoReadinessBinding: "Locomotive readiness sets the earliest feasible time",
        .swapRiskApplied: "Train-set swap risk is included",
    ]

    public static func explanationLabel(_ code: StopForecastExplanationCode) -> String {
        evidence[code] ?? code.rawValue
    }

    public static func evidence(_ forecast: StopForecast) -> [String] {
        forecast.explanationCodes.map(explanationLabel)
    }

    public static func sourceLabel(_ forecast: StopForecast) -> String {
        switch forecast {
        case .unavailable:
            return "Forecast unavailable"
        case .available(let value):
            switch value.source {
            case .observed:
                return "Observed fact"
            case .empirical:
                let release = value.modelReleaseId.map { " · release \($0)" } ?? " · release ID unavailable"
                return "Released empirical model · \(value.modelName) \(value.modelVersion)\(release)"
            case .baseline:
                return "Baseline fallback · \(value.modelName) \(value.modelVersion)"
            default:
                return value.explanationCodes.contains(.physicalTransitionBinding)
                    ? "Physical-transition model · \(value.modelName) \(value.modelVersion)"
                    : "Forecast model · \(value.modelName) \(value.modelVersion)"
            }
        }
    }

    public static func fallbackLabel(_ reason: StopForecastFallbackReason?) -> String? {
        switch reason {
        case .insufficientGroupSupport: return "Fallback: too few comparable journeys"
        case .noReleasedEmpiricalGroup: return "Fallback: no released empirical model"
        case .currentDelayUnknown: return "Current delay unknown"
        case nil: return nil
        }
    }

    /// Human age of a feature timestamp ("12s old", "3 min old", "2 hr old").
    public static func featureFreshness(_ featureAsOf: String, now: Date = Date()) -> String {
        guard let date = ISO8601DateFormatter.locomote.date(from: featureAsOf) else { return "unknown age" }
        let ageSeconds = max(0, Int(now.timeIntervalSince(date)))
        if ageSeconds < 60 { return "\(ageSeconds)s old" }
        if ageSeconds < 3_600 { return "\(ageSeconds / 60) min old" }
        return "\(ageSeconds / 3_600) hr old"
    }

    /// "Gained N min delay at this stop" / "Recovered N min at this stop".
    public static func delayChange(_ stop: StationStop) -> String? {
        guard let arrival = stop.arrivalDelayMinutes, let departure = stop.departureDelayMinutes else { return nil }
        let change = departure - arrival
        if change > 0 { return "Gained \(change) min delay at this stop" }
        if change < 0 { return "Recovered \(abs(change)) min at this stop" }
        return "Delay unchanged at this stop"
    }
}

public struct StationCallout: Sendable {
    public let facts: [String]
    public let forecast: [String]
    public let evidence: String?
}

extension StationStop {
    /// A structured callout used by the station detail sheet.
    public func callout(now: Date = Date()) -> StationCallout {
        var facts: [String] = [
            "Scheduled arrival \(RailTime.format(scheduledArrival))",
        ]
        if let actualArrival { facts.append("Actual arrival \(RailTime.format(actualArrival))") }
        if let actualDeparture { facts.append("Actual departure \(RailTime.format(actualDeparture))") }
        if let change = ForecastPresentation.delayChange(self) { facts.append(change) }

        if state == .passed {
            return StationCallout(facts: facts, forecast: [], evidence: nil)
        }

        guard let forecast else {
            return StationCallout(facts: facts, forecast: ["Forecast unavailable"], evidence: nil)
        }

        if case .unavailable = forecast {
            return StationCallout(
                facts: facts,
                forecast: ["Forecast unavailable · current delay unknown"],
                evidence: ForecastPresentation.evidence(forecast).joined(separator: " · ")
            )
        }

        guard case .available(let value) = forecast else {
            return StationCallout(facts: facts, forecast: [], evidence: nil)
        }
        var lines: [String] = [
            "P10 \(RailTime.format(value.p10)) · P50 \(RailTime.format(value.p50)) · P90 \(RailTime.format(value.p90))",
            ForecastPresentation.sourceLabel(forecast),
            "Features \(ForecastPresentation.featureFreshness(value.featureAsOf, now: now))",
        ]
        if let fallback = ForecastPresentation.fallbackLabel(value.fallbackReason) { lines.append(fallback) }

        return StationCallout(
            facts: facts,
            forecast: lines,
            evidence: ForecastPresentation.evidence(forecast).joined(separator: " · ")
        )
    }
}

// MARK: - Journey mode derivation

public enum JourneyPositionDisplay: Sendable, Equatable {
    case hidden, observed, stale, preview
}

public enum JourneyPositionEvidence {
    /// A route-progress estimate is not evidence of a train's live location.
    public static func display(
        journey: Journey,
        cached: Bool,
        preview: Bool,
        now: Date = Date()
    ) -> JourneyPositionDisplay {
        if preview { return .preview }
        guard !IndiaDate.isFuture(journey.travelDate),
              journey.position.progress.isFinite,
              (0...1).contains(journey.position.progress),
              Set<DataSource>([.official, .community, .device]).contains(journey.position.source),
              journey.position.observedAt.isFinite,
              journey.position.observedAt > 0 else { return .hidden }
        let age = now.timeIntervalSince1970 * 1_000 - journey.position.observedAt
        guard age >= 0 else { return .hidden }
        let freshness = journey.provenance?.freshness
        if cached || freshness == "stale" {
            return age <= 72 * 60 * 60 * 1_000 ? .stale : .hidden
        }
        if (freshness == "live" || freshness == nil), age <= 10 * 60 * 1_000 {
            return .observed
        }
        return .hidden
    }
}

public enum JourneyMode {
    /// Derive the mode inputs from a loaded journey state. Kept in the domain so
    /// the "never look live unless live" rules live in one tested place.
    public static func input(
        journey: Journey,
        cached: Bool,
        preview: Bool,
        historicalRoute: Bool,
        originDate: String,
        error: String?,
        now: Date = Date()
    ) -> JourneyModeInput {
        let future = IndiaDate.isFuture(originDate) || journey.stops.allSatisfy { $0.delayStatus == .scheduled }
        let live = !cached && !preview && !historicalRoute && !future
            && JourneyPositionEvidence.display(journey: journey, cached: cached, preview: preview, now: now) == .observed
        return JourneyModeInput(
            preview: preview,
            historicalRoute: historicalRoute,
            future: future,
            live: live,
            error: error != nil && !cached
        )
    }
}

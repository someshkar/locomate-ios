//
//  StatusKind.swift
//  Locomate
//
//  Status mapping — ported from SmartRail `src/theme/statusMapping.ts`.
//
//  This is the ONE place where data provenance becomes visual status.
//  Locomate's core product rule is that operational confidence is always
//  visible. Every pill, dot, banner, timeline node, map marker and Live
//  Activity derives its color family from these functions. Views must never
//  decide "live vs replay" presentation on their own.
//

import Foundation

public enum StatusKind: String, Sendable, CaseIterable {
    case onTime
    case delayed
    case stale
    case error
    case preview
    case scheduled
}

/// Inputs describing why a journey is in a given mode.
public struct JourneyModeInput: Sendable {
    public var preview: Bool
    public var historicalRoute: Bool
    /// Journey origin date is in the future.
    public var future: Bool
    /// True only for a fresh, substantiated live position.
    public var live: Bool
    public var error: Bool

    public init(
        preview: Bool = false,
        historicalRoute: Bool = false,
        future: Bool = false,
        live: Bool = false,
        error: Bool = false
    ) {
        self.preview = preview
        self.historicalRoute = historicalRoute
        self.future = future
        self.live = live
        self.error = error
    }
}

public enum StatusMapping {
    /// Map a delay value + its provenance to a semantic status.
    /// `estimated` keeps the delay color (current model estimate);
    /// `stale` always degrades to the stale family; unavailable reads neutral.
    public static func statusForDelay(
        delayMinutes: Int?,
        delayStatus: DelayStatus?
    ) -> StatusKind {
        if delayStatus == .stale { return .stale }
        if delayMinutes == nil || delayStatus == .unavailable { return .scheduled }
        if let delay = delayMinutes, delay > 0 { return .delayed }
        return .onTime
    }

    /// Map the overall journey mode to a status family.
    /// Order matters: errors and preview/replay outrank everything so they can
    /// never be mistaken for live.
    public static func statusForJourneyMode(_ input: JourneyModeInput) -> StatusKind {
        if input.error { return .error }
        if input.preview || input.historicalRoute { return .preview }
        if input.future { return .scheduled }
        if input.live { return .onTime }
        return .stale
    }

    /// Whether the breathing "live" pulse may render. Preview is never live.
    public static func isLivePulseAllowed(_ mode: JourneyModeInput) -> Bool {
        statusForJourneyMode(mode) == .onTime && !mode.preview && !mode.historicalRoute
    }

    /// Short label for a journey-mode status pill.
    public static func journeyModeLabel(_ status: StatusKind) -> String {
        switch status {
        case .onTime: return "LIVE JOURNEY"
        case .preview: return "ROUTE REPLAY"
        case .scheduled: return "UPCOMING JOURNEY"
        case .stale: return "PREDICTED JOURNEY"
        case .delayed: return "DELAYED"
        case .error: return "UNAVAILABLE"
        }
    }

    /// Delay label copy, provenance-qualified (e.g. "+12 MIN", "ON TIME · EST.").
    public static func delayStatusLabel(
        delayMinutes: Int?,
        delayStatus: DelayStatus?,
        predictionSource: DataSource? = nil
    ) -> String {
        guard let delay = delayMinutes, delayStatus != .unavailable else {
            return "DELAY UNAVAILABLE"
        }
        let qualifier: String
        if delayStatus == .stale {
            qualifier = " · STALE"
        } else if delayStatus == .estimated || predictionSource == .predicted {
            qualifier = " · EST."
        } else {
            qualifier = ""
        }
        if delay > 0 { return "+\(delay) MIN\(qualifier)" }
        if delay < 0 { return "\(abs(delay)) MIN EARLY\(qualifier)" }
        let base = (delayStatus == .scheduled || delayStatus == nil) ? "SCHEDULED" : "ON TIME"
        return "\(base)\(qualifier)"
    }
}

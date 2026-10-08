import Foundation

/// Every displayed arrival belongs to the reported next station, never to the destination by accident.
enum LiveActivityProjection {
    static func state(journey: Journey, now: Date = Date()) -> JourneyActivityAttributes.ContentState? {
        guard journey.prediction.delayMinutes?.isFinite == true,
              journey.prediction.updatedSecondsAgo.isFinite,
              (0...600).contains(journey.prediction.updatedSecondsAgo),
              ![DelayStatus.unavailable, .stale, .estimated].contains(journey.prediction.delayStatus),
              JourneyPositionEvidence.display(journey: journey, cached: false, preview: false, now: now) == .observed else { return nil }
        let matches = journey.stops.filter { $0.code == journey.position.nextStation }
        guard matches.count == 1, let stop = matches.first, stop.state != .passed,
              stop.actualDeparture == nil else { return nil }
        let clock = JourneyStopProjection.summaryClock(stop: stop, departure: false, preview: false, cached: false)
        return .init(nextStation: stop.code, eta: clock.time ?? "—",
                     delayMinutes: journey.prediction.delayMinutes,
                     delayLabel: StatusMapping.delayStatusLabel(delayMinutes: journey.prediction.delayMinutes,
                        delayStatus: journey.prediction.delayStatus, predictionSource: journey.prediction.source),
                     distanceToNextKm: journey.position.distanceToNextKm.isFinite ? max(0, journey.position.distanceToNextKm) : 0,
                     confidence: journey.prediction.confidence.rawValue.uppercased(),
                     updatedAt: min(Date(timeIntervalSince1970: journey.position.observedAt / 1_000), now.addingTimeInterval(-journey.prediction.updatedSecondsAgo)),
                     etaLabel: clock.time == nil ? "Arrival unavailable" : clock.label)
    }
}

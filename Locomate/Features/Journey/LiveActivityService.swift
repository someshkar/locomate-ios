//
//  LiveActivityService.swift
//  Locomate
//
//  Manages the journey Live Activity / Dynamic Island — ported behaviour from
//  SmartRail `src/services/liveActivity.ios.ts`:
//  - Only starts for a known delay (never for unavailable/stale/estimated).
//  - Ends immediately when the delay becomes unknown.
//  - Registers the push-to-update token so the server can refresh the ETA
//    instead of polling.
//

import Foundation
// ActivityKit's `Activity` is not Sendable; the service confines all use to
// the main actor, so the pre-concurrency import is accurate here.
@preconcurrency import ActivityKit

@MainActor
public final class LiveActivityService {
    private var activity: Activity<JourneyActivityAttributes>?
    private var tokenTask: Task<Void, Never>?

    public init() {}

    public var isRunning: Bool { activity != nil }

    /// Sync the Live Activity to the current journey state.
    /// Returns false when no activity should be running.
    @discardableResult
    public func sync(journey: Journey, registerToken: ((String) async -> Void)? = nil) async -> Bool {
        // The product rule: a Live Activity requires a known, non-stale delay.
        let delayStatus = journey.prediction.delayStatus
        guard journey.prediction.delayMinutes != nil,
              delayStatus != .unavailable,
              delayStatus != .stale,
              delayStatus != .estimated else {
            await end()
            return false
        }

        let state = JourneyActivityAttributes.ContentState(
            nextStation: journey.position.nextStation,
            eta: RailTime.format(journey.prediction.expectedTime ?? journey.scheduledArrival),
            delayMinutes: journey.prediction.delayMinutes,
            delayLabel: StatusMapping.delayStatusLabel(
                delayMinutes: journey.prediction.delayMinutes,
                delayStatus: delayStatus,
                predictionSource: journey.prediction.source
            ),
            distanceToNextKm: journey.position.distanceToNextKm,
            confidence: journey.prediction.confidence.rawValue.uppercased()
        )

        if let activity {
            await activity.update(ActivityContent(state: state, staleDate: nil))
            return true
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let attributes = JourneyActivityAttributes(
            trainNumber: journey.trainNumber,
            trainName: journey.trainName,
            destinationCode: journey.destinationCode
        )
        do {
            let created = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: registerToken == nil ? nil : .token
            )
            activity = created
            if let registerToken {
                observePushToken(created, register: registerToken)
            }
            return true
        } catch {
            return false
        }
    }

    public func end() async {
        tokenTask?.cancel()
        tokenTask = nil
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    /// Observe the push-to-update token and forward it to the gateway.
    private func observePushToken(
        _ activity: Activity<JourneyActivityAttributes>,
        register: @escaping (String) async -> Void
    ) {
        let updates = activity.pushTokenUpdates
        tokenTask = Task { [register] in
            for await token in updates {
                let hex = token.map { String(format: "%02x", $0) }.joined()
                await register(hex)
            }
        }
    }
}

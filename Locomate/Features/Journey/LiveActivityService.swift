//
//  LiveActivityService.swift
//  Locomate
//
//  Manages the journey Live Activity / Dynamic Island — ported behaviour from
//  SmartRail `src/services/liveActivity.ios.ts`:
//  - Only starts for a known delay (never for unavailable/stale/estimated).
//  - Ends immediately when the delay becomes unknown.
//  - Registers the push-to-update token for gateway delivery when configured.
//

import Foundation
// ActivityKit's `Activity` is not Sendable; the service confines all use to
// the main actor, so the pre-concurrency import is accurate here.
@preconcurrency import ActivityKit

@MainActor
public final class LiveActivityService {
    private var tokenTask: Task<Void, Never>?
    private var tokenActivityId: String?
    private var revision = 0

    public init() {}

    public func isRunning(for runId: String) -> Bool {
        Activity<JourneyActivityAttributes>.activities.contains { $0.attributes.runId == runId }
    }

    /// Sync the Live Activity to the current journey state.
    /// Returns false when no activity should be running.
    @discardableResult
    public func sync(journey: Journey, registerToken: ((String) async -> Void)? = nil) async -> Bool {
        revision += 1
        let syncRevision = revision
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
        let content = ActivityContent(state: state, staleDate: state.updatedAt.addingTimeInterval(10 * 60))

        let active = Activity<JourneyActivityAttributes>.activities
        let matching = active.first { $0.attributes.runId == journey.id }
        if tokenActivityId != matching?.id {
            tokenTask?.cancel()
            tokenTask = nil
            tokenActivityId = nil
        }
        for existing in active where existing.attributes.runId != journey.id {
            await existing.end(nil, dismissalPolicy: .immediate)
            guard revision == syncRevision else { return false }
        }
        for duplicate in active where duplicate.attributes.runId == journey.id && duplicate.id != matching?.id {
            await duplicate.end(nil, dismissalPolicy: .immediate)
            guard revision == syncRevision else { return false }
        }
        if let matching {
            await matching.update(content)
            guard revision == syncRevision else { return false }
            if let registerToken, tokenTask == nil {
                observePushToken(matching, register: registerToken)
            }
            return true
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let attributes = JourneyActivityAttributes(
            trainNumber: journey.trainNumber,
            trainName: journey.trainName,
            destinationCode: journey.destinationCode,
            runId: journey.id
        )
        do {
            let created = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: registerToken == nil ? nil : .token
            )
            if let registerToken {
                observePushToken(created, register: registerToken)
            }
            return true
        } catch {
            return false
        }
    }

    public func end() async {
        revision += 1
        tokenTask?.cancel()
        tokenTask = nil
        tokenActivityId = nil
        for existing in Activity<JourneyActivityAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Observe the push-to-update token and forward it to the gateway.
    private func observePushToken(
        _ activity: Activity<JourneyActivityAttributes>,
        register: @escaping (String) async -> Void
    ) {
        tokenTask?.cancel()
        tokenActivityId = activity.id
        let updates = activity.pushTokenUpdates
        tokenTask = Task { [register] in
            if let token = activity.pushToken {
                await register(token.map { String(format: "%02x", $0) }.joined())
            }
            for await token in updates {
                let hex = token.map { String(format: "%02x", $0) }.joined()
                await register(hex)
            }
        }
    }
}

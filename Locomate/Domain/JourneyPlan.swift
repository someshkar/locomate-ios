//
//  JourneyPlan.swift
//  Locomate
//
//  Personal boarding/alighting selection — ported from
//  SmartRail `src/domain/journeyPlan.ts`.
//

import Foundation

public struct JourneyPlanStop: Codable, Sendable, Equatable {
    public let index: Int
    public let code: String
    public let name: String
}

public struct JourneyPlan: Codable, Sendable, Equatable {
    public let trainNumber: String
    public let originDate: String
    public let boarding: JourneyPlanStop
    public let alighting: JourneyPlanStop
    public let updatedAt: String
}

public enum JourneyPlanLogic {
    public static func create(
        journey: Journey,
        originDate: String,
        boardingIndex: Int,
        alightingIndex: Int,
        updatedAt: String = ISO8601DateFormatter.locomote.string(from: Date())
    ) throws -> JourneyPlan {
        guard boardingIndex >= 0,
              alightingIndex < journey.stops.count,
              boardingIndex < alightingIndex else {
            throw JourneyPlanError.invalidSelection
        }
        let boarding = journey.stops[boardingIndex]
        let alighting = journey.stops[alightingIndex]
        return JourneyPlan(
            trainNumber: journey.trainNumber,
            originDate: originDate,
            boarding: JourneyPlanStop(index: boardingIndex, code: boarding.code, name: boarding.name),
            alighting: JourneyPlanStop(index: alightingIndex, code: alighting.code, name: alighting.name),
            updatedAt: updatedAt
        )
    }

    public static func `default`(journey: Journey, originDate: String) -> JourneyPlan {
        // `stops` is guaranteed non-empty by the gateway contract.
        try! create(journey: journey, originDate: originDate,
                    boardingIndex: 0, alightingIndex: journey.stops.count - 1)
    }

    /// Resolve a stored plan against a possibly-changed stop list. Returns nil
    /// when the plan no longer describes a valid segment of this journey.
    public static func resolve(journey: Journey, plan: JourneyPlan?) -> JourneyPlan? {
        guard let plan, plan.trainNumber == journey.trainNumber else { return nil }

        var boardingIndex = journey.stops.indices.contains(plan.boarding.index)
            && journey.stops[plan.boarding.index].code == plan.boarding.code
            ? plan.boarding.index
            : journey.stops.firstIndex { $0.code == plan.boarding.code } ?? -1

        let alightingIndex = journey.stops.indices.contains(plan.alighting.index)
            && journey.stops[plan.alighting.index].code == plan.alighting.code
            ? plan.alighting.index
            : (journey.stops.enumerated().first { $1.code == plan.alighting.code && $0 > boardingIndex }?.offset ?? -1)

        guard boardingIndex >= 0, alightingIndex > boardingIndex else { return nil }
        // Recompute indices defensively in case the resolved code moved.
        if journey.stops[boardingIndex].code != plan.boarding.code {
            boardingIndex = journey.stops.firstIndex { $0.code == plan.boarding.code } ?? -1
        }
        if boardingIndex < 0 || alightingIndex <= boardingIndex { return nil }
        return try? create(
            journey: journey,
            originDate: plan.originDate,
            boardingIndex: boardingIndex,
            alightingIndex: alightingIndex,
            updatedAt: plan.updatedAt
        )
    }

    /// The stops within the personal segment, inclusive of both ends.
    public static func stops(journey: Journey, plan: JourneyPlan) -> [StationStop] {
        guard plan.boarding.index >= 0,
              plan.alighting.index < journey.stops.count,
              plan.boarding.index <= plan.alighting.index else { return journey.stops }
        return Array(journey.stops[plan.boarding.index...plan.alighting.index])
    }

    public enum JourneyPlanError: Error, LocalizedError {
        case invalidSelection
        public var errorDescription: String? {
            "Choose a boarding stop before the drop-off stop"
        }
    }
}

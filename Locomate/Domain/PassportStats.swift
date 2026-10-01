//
//  PassportStats.swift
//  Locomate
//
//  Private travel-history statistics — ported from SmartRail
//  `src/domain/passport.ts`.
//

import Foundation

public struct SavedJourneyStation: Codable, Sendable, Equatable {
    public let code: String
    public let name: String
}

public struct SavedJourney: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let trainNumber: String
    public let trainName: String
    public let originCode: String
    public let originName: String
    public let destinationCode: String
    public let destinationName: String
    public let originDate: String
    public let departureTime: String
    public let scheduledArrival: String
    public let predictedArrival: String
    public let distanceKm: Double
    public let minutes: Int
    public let delayMinutes: Int?
    public let stations: [SavedJourneyStation]
    public let routeCoordinates: [RailCoordinate]?
    public let savedAt: String
    public let completedAt: String?
    /// Nil denotes a legacy saved entry whose mode was not recorded.
    public var preview: Bool? = nil
}

public struct PassportRouteFrequency: Sendable, Equatable, Identifiable {
    public var id: String { "\(originCode)->\(destinationCode)" }
    public let originCode: String
    public let destinationCode: String
    public let trips: Int
}

public struct PassportStats: Sendable, Equatable {
    public let trips: Int
    public let distanceKm: Double
    public let minutes: Int
    public let delayMinutes: Int
    public let uniqueStations: Int
    public let uniqueRoutes: Int
    public let uniqueTrains: Int
    public let onTimePercentage: Int?
    public let routeFrequency: [PassportRouteFrequency]
}

public enum Passport {
    private static func nonNegative(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    public static func summarize(_ journeys: [SavedJourney]) -> PassportStats {
        // A saved historical route is not evidence that anyone travelled it.
        // Legacy entries with unknown mode are excluded for the same reason.
        let recorded = journeys.filter { $0.preview == false }
        var stations = Set<String>()
        var trains = Set<String>()
        var routes: [String: PassportRouteFrequency] = [:]
        var distanceKm = 0.0
        var minutes = 0
        var delayMinutes = 0
        var onTimeTrips = 0
        var timedTrips = 0

        for journey in recorded {
            distanceKm += nonNegative(journey.distanceKm)
            minutes += Int(nonNegative(Double(journey.minutes)))
            if let delay = journey.delayMinutes { delayMinutes += Int(nonNegative(Double(delay))) }

            if !journey.trainNumber.isEmpty { trains.insert(journey.trainNumber) }
            for station in journey.stations where !station.code.isEmpty { stations.insert(station.code) }

            if !journey.originCode.isEmpty, !journey.destinationCode.isEmpty {
                stations.insert(journey.originCode)
                stations.insert(journey.destinationCode)
                let key = "\(journey.originCode)\u{0}\(journey.destinationCode)"
                if var existing = routes[key] {
                    existing = PassportRouteFrequency(originCode: existing.originCode,
                                                      destinationCode: existing.destinationCode,
                                                      trips: existing.trips + 1)
                    routes[key] = existing
                } else {
                    routes[key] = PassportRouteFrequency(originCode: journey.originCode,
                                                         destinationCode: journey.destinationCode,
                                                         trips: 1)
                }
            }

            if let delay = journey.delayMinutes {
                timedTrips += 1
                if delay <= 5 { onTimeTrips += 1 }
            }
        }

        let frequency = routes.values.sorted { left, right in
            if left.trips != right.trips { return left.trips > right.trips }
            if left.originCode != right.originCode { return left.originCode < right.originCode }
            return left.destinationCode < right.destinationCode
        }

        return PassportStats(
            trips: recorded.count,
            distanceKm: distanceKm,
            minutes: minutes,
            delayMinutes: delayMinutes,
            uniqueStations: stations.count,
            uniqueRoutes: routes.count,
            uniqueTrains: trains.count,
            onTimePercentage: timedTrips == 0 ? nil : Int((Double(onTimeTrips) / Double(timedTrips) * 100).rounded()),
            routeFrequency: frequency
        )
    }

    /// Build a saved journey from a live journey + personal plan. Coach and seat
    /// are intentionally EXCLUDED from saved history (product rule).
    public static func makeSaved(
        journey: Journey,
        originDate: String,
        plan: JourneyPlan?,
        preview: Bool = false
    ) -> SavedJourney {
        let activePlan = JourneyPlanLogic.resolve(journey: journey, plan: plan)
            ?? JourneyPlanLogic.default(journey: journey, originDate: originDate)
        let segment = JourneyPlanLogic.stops(journey: journey, plan: activePlan)
        let boarding = segment.first
        let alighting = segment.last

        // Walk the timetable chronologically so overnight runs roll past midnight
        // (a 19:40 departure to a 05:40 arrival is ~10h, not a negative span).
        let boardingStop = journey.stops[activePlan.boarding.index]
        let alightingStop = journey.stops[activePlan.alighting.index]
        let start = try? IndiaDate.instant(
            originDate: originDate,
            time: boardingStop.scheduledDeparture ?? boardingStop.scheduledArrival
        )
        var end = try? IndiaDate.instant(
            originDate: originDate,
            time: alightingStop.scheduledArrival
        )
        if let start, let endDate = end, endDate <= start {
            // Arrival is on the next service day.
            end = endDate.addingTimeInterval(86_400)
        }
        let minutes: Int
        if let start, let end {
            minutes = max(0, Int(end.timeIntervalSince(start) / 60))
        } else {
            minutes = journey.scheduledDurationMinutes ?? 0
        }

        let distance = (alighting?.distanceKm ?? journey.distanceKm) - (boarding?.distanceKm ?? 0)

        return SavedJourney(
            id: "\(journey.trainNumber)-\(originDate)",
            trainNumber: journey.trainNumber,
            trainName: journey.trainName,
            originCode: boarding?.code ?? journey.originCode,
            originName: boarding?.name ?? journey.originName,
            destinationCode: alighting?.code ?? journey.destinationCode,
            destinationName: alighting?.name ?? journey.destinationName,
            originDate: originDate,
            departureTime: journey.departureTime,
            scheduledArrival: journey.scheduledArrival,
            predictedArrival: journey.predictedArrival,
            distanceKm: max(0, distance),
            minutes: minutes,
            // A current forecast is not the actual outcome of this run.
            delayMinutes: nil,
            stations: segment.map { SavedJourneyStation(code: $0.code, name: $0.name) },
            routeCoordinates: journey.routeCoordinates,
            savedAt: ISO8601DateFormatter.locomote.string(from: Date()),
            completedAt: nil,
            preview: preview
        )
    }
}

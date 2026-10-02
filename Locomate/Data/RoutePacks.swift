//
//  RoutePacks.swift
//  Locomate
//
//  Bundled historical route packs (generated from SmartRail's
//  `routePacks.generated.ts`). Used for preview mode and the historical replay,
//  exactly as the source app did — preview data is NEVER presented as live.
//

import Foundation

public struct OpenRoutePack: Decodable, Sendable {
    public struct Call: Decodable, Sendable {
        public let sequence: Int
        public let code: String
        public let name: String
        public let day: Int
        public let arrival: String?
        public let departure: String?
        public let dwellMinutes: Int
        public let lat: Double
        public let lon: Double
    }

    public let trainNumber: String
    public let name: String
    public let returnTrain: String?
    public let originCode: String
    public let originName: String
    public let destinationCode: String
    public let destinationName: String
    public let departure: String
    public let arrival: String
    public let durationMinutes: Int
    public let distanceKm: Double
    /// [latitude, longitude] pairs, compact on disk.
    public let geometry: [[Double]]
    public let calls: [Call]

    public var coordinates: [RailCoordinate] {
        geometry.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return RailCoordinate(latitude: pair[0], longitude: pair[1])
        }
    }
}

public enum RoutePackStore {
    public static let packs: [OpenRoutePack] = {
        guard let url = Bundle.main.url(forResource: "route-packs", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let packs = try? JSONDecoder().decode([OpenRoutePack].self, from: data) else {
            return []
        }
        return packs
    }()

    public static func pack(_ trainNumber: String) -> OpenRoutePack? {
        packs.first { $0.trainNumber == trainNumber }
    }

    public static var trainNumbers: [String] { packs.map(\.trainNumber) }
}

// MARK: - Preview journey construction (mirrors openRoutePacks.ts)

public enum PreviewData {
    static func clock(_ value: String?, fallback: String) -> String {
        guard let value else { return fallback }
        return String(value.prefix(5))
    }

    public static func journey(from pack: OpenRoutePack, originDate: String, progress: Double = 0.46) -> Journey {
        let denominator = max(1, pack.geometry.count - 1)
        let activeIndex = min(pack.calls.count - 2, max(0, Int(Double(progress) * Double(pack.calls.count - 1))))

        let stops: [StationStop] = pack.calls.enumerated().map { index, call in
            let arrival = clock(call.arrival, fallback: clock(call.departure, fallback: "--:--"))
            return StationStop(
                code: call.code,
                name: call.name,
                distanceKm: (pack.distanceKm * Double(call.sequence) / Double(denominator)).rounded(),
                scheduledArrival: arrival,
                scheduledDeparture: call.departure.map { String($0.prefix(5)) },
                predictedArrival: arrival,
                actualArrival: nil,
                actualDeparture: nil,
                platform: nil,
                delayMinutes: nil,
                arrivalDelayMinutes: nil,
                departureDelayMinutes: nil,
                delayStatus: .unavailable,
                timingSource: .scheduled,
                observedAt: nil,
                state: index < activeIndex ? .passed : (index == activeIndex ? .current : .upcoming),
                progress: Double(call.sequence) / Double(denominator),
                forecast: nil
            )
        }

        let previous = stops[min(activeIndex, stops.count - 1)]
        let next = stops[min(activeIndex + 1, stops.count - 1)]
        let remainingKm = max(0, next.distanceKm - progress * pack.distanceKm)

        return Journey(
            id: "preview-\(pack.trainNumber)-historical-route",
            trainNumber: pack.trainNumber,
            trainName: pack.name,
            originCode: pack.originCode,
            originName: pack.originName,
            destinationCode: pack.destinationCode,
            destinationName: pack.destinationName,
            departureTime: String(pack.departure.prefix(5)),
            scheduledArrival: String(pack.arrival.prefix(5)),
            predictedArrival: String(pack.arrival.prefix(5)),
            coach: "",
            seat: "",
            travelDate: originDate,
            distanceKm: pack.distanceKm,
            scheduledDurationMinutes: pack.durationMinutes,
            completion: progress,
            stops: stops,
            prediction: Prediction(
                expectedTime: nil, lowerBound: nil, upperBound: nil,
                delayMinutes: nil, delayStatus: .unavailable,
                confidence: .low, confidenceScore: 20,
                modelVersion: "historical-route-replay-v1",
                leadMinutes: 0,
                reasons: [
                    "No live delay is available because this is a historical route replay",
                ],
                source: .scheduled,
                updatedSecondsAgo: 0
            ),
            position: TrainPosition(
                progress: progress,
                speedKph: 82,
                phase: .running,
                previousStation: previous.code,
                nextStation: next.code,
                distanceToNextKm: remainingKm,
                observedAt: Date().timeIntervalSince1970 * 1000,
                source: .scheduled,
                confidence: .low
            ),
            nearbyTrains: [],
            routeCoordinates: pack.coordinates,
            provenance: nil
        )
    }

    public static func operations(from pack: OpenRoutePack, originDate: String) -> OperationalChainResponse {
        let forward = pack.coordinates
        let reverse = forward.reversed().map { RailCoordinate(latitude: $0.latitude, longitude: $0.longitude) }
        let departure = (try? IndiaDate.instant(originDate: originDate, time: String(pack.departure.prefix(8)))) ?? Date()
        let arrival = departure.addingTimeInterval(TimeInterval(pack.durationMinutes * 60))
        let iso = ISO8601DateFormatter.locomote
        let reciprocal = pack.returnTrain ?? "UNKNOWN"

        func run(_ id: String, role: String, trainNumber: String, name: String,
                 origin: String, destination: String, geometry: [RailCoordinate],
                 position: Double?) -> OperationalRun {
            OperationalRun(
                id: id, role: role, trainNumber: trainNumber, trainName: name,
                originCode: origin, destinationCode: destination,
                scheduledDeparture: iso.string(from: departure),
                scheduledArrival: iso.string(from: arrival),
                actualDeparture: nil, actualArrival: nil, predictedArrival: nil,
                geometry: RoutePolyline(coordinates: geometry, source: "preview"),
                position: position.map { progress in
                    OperationalPosition(
                        coordinate: geometry.isEmpty ? RailCoordinate(latitude: 0, longitude: 0)
                            : geometry[min(geometry.count - 1, Int(Double(geometry.count) * progress))],
                        progress: progress,
                        observedAt: iso.string(from: departure),
                        source: .scheduled
                    )
                }
            )
        }

        return OperationalChainResponse(
            trainNumber: pack.trainNumber,
            originDate: originDate,
            availability: "partial",
            mode: "preview",
            disclaimer: "Historical reciprocal-service metadata does not prove that the same physical rake operated either service. No live delay evidence is available.",
            previous: run("preview-\(reciprocal)-previous", role: "previous", trainNumber: reciprocal,
                          name: "Reciprocal service", origin: pack.destinationCode, destination: pack.originCode,
                          geometry: reverse, position: 0.92),
            current: run("preview-\(pack.trainNumber)-historical-route", role: "current", trainNumber: pack.trainNumber,
                         name: pack.name, origin: pack.originCode, destination: pack.destinationCode,
                         geometry: forward, position: 0.46),
            next: run("preview-\(reciprocal)-next", role: "next", trainNumber: reciprocal,
                      name: "Reciprocal service", origin: pack.destinationCode, destination: pack.originCode,
                      geometry: reverse, position: nil),
            linkage: LinkageClaim(
                claim: "possible-same-rake", confidence: .low, method: "schedule-continuity",
                caveats: ["The dataset identifies a reciprocal train number, not a physical rake assignment."]
            ),
            delayAssessment: nil,
            propagatedDelay: nil,
            turnaroundRisk: nil,
            updatedAt: iso.string(from: departure)
        )
    }
}

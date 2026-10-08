//
//  MapMatcher.swift
//  Locomate
//
//  Location filtering and map-matching — ported from SmartRail
//  `src/location/mapMatcher.ts` and `src/location/observation.ts`.
//
//  Product rules preserved: impossible movement, stale fixes, poor accuracy and
//  road-speed values are rejected before anything is queued; accepted samples
//  are projected onto the known railway geometry; preview runs are never
//  contributed.
//

import Foundation

public struct LocationSample: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var timestamp: TimeInterval
    public var accuracyM: Double
    public var speedKph: Double

    public init(latitude: Double, longitude: Double, timestamp: TimeInterval,
                accuracyM: Double, speedKph: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.accuracyM = accuracyM
        self.speedKph = speedKph
    }
}

public struct LocationFilterOptions: Sendable {
    public var maxAgeMs: TimeInterval = 30_000
    public var maxAccuracyM: Double = 100
    public var minSpeedKph: Double = 3
    public var maxSpeedKph: Double = 350
    public init() {}
}

public struct MapMatch: Sendable, Equatable {
    public let coordinate: RailCoordinate
    public let segmentIndex: Int
    public let distanceM: Double
    public let progress: Double
    public let confidence: Double
}

public enum MapMatcher {
    static let earthRadiusM: Double = 6_371_000

    static func radians(_ value: Double) -> Double { value * .pi / 180 }

    /// Metres between two coordinates.
    public static func haversine(_ a: RailCoordinate, _ b: RailCoordinate) -> Double {
        let latitudeDelta = radians(b.latitude - a.latitude)
        let longitudeDelta = radians(b.longitude - a.longitude)
        let startLatitude = radians(a.latitude)
        let endLatitude = radians(b.latitude)
        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(startLatitude) * cos(endLatitude) * pow(sin(longitudeDelta / 2), 2)
        return 2 * earthRadiusM * asin(min(1, sqrt(haversine)))
    }

    /// Reject fixes that are out of range, stale, too inaccurate, or moving at
    /// a speed that cannot be a train on this corridor.
    public static func isUsable(
        _ sample: LocationSample,
        now: TimeInterval = Date().timeIntervalSince1970 * 1000,
        options: LocationFilterOptions = LocationFilterOptions()
    ) -> Bool {
        sample.latitude.isFinite && sample.latitude >= -90 && sample.latitude <= 90
            && sample.longitude.isFinite && sample.longitude >= -180 && sample.longitude <= 180
            && sample.timestamp.isFinite
            && sample.timestamp <= now + 5_000
            && now - sample.timestamp <= options.maxAgeMs
            && sample.accuracyM.isFinite && sample.accuracyM >= 0 && sample.accuracyM <= options.maxAccuracyM
            && sample.speedKph.isFinite
            && sample.speedKph >= options.minSpeedKph && sample.speedKph <= options.maxSpeedKph
    }

    /// Project a point onto a segment in an equirectangular approximation.
    static func project(
        _ point: RailCoordinate,
        start: RailCoordinate,
        end: RailCoordinate
    ) -> (coordinate: RailCoordinate, fraction: Double) {
        let referenceLatitude = radians((start.latitude + end.latitude + point.latitude) / 3)
        let scaleX = cos(referenceLatitude)
        let ax = start.longitude * scaleX, ay = start.latitude
        let bx = end.longitude * scaleX, by = end.latitude
        let px = point.longitude * scaleX, py = point.latitude
        let dx = bx - ax, dy = by - ay
        let denominator = dx * dx + dy * dy
        let fraction = denominator == 0
            ? 0
            : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / denominator))
        return (
            RailCoordinate(
                latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                longitude: start.longitude + (end.longitude - start.longitude) * fraction
            ),
            fraction
        )
    }

    /// Nearest point on the route, with a confidence that falls off with the
    /// match distance relative to the fix accuracy.
    public static func match(
        _ point: RailCoordinate,
        route: [RailCoordinate],
        accuracyM: Double = 0
    ) -> MapMatch? {
        guard route.count >= 2 else { return nil }
        let lengths = (1..<route.count).map { haversine(route[$0 - 1], route[$0]) }
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 0 else { return nil }

        var traversed = 0.0
        var nearest: MapMatch?
        for index in 0..<lengths.count {
            let projection = project(point, start: route[index], end: route[index + 1])
            let distanceM = haversine(point, projection.coordinate)
            if nearest == nil || distanceM < (nearest?.distanceM ?? .greatestFiniteMagnitude) {
                let uncertaintyM = max(25, accuracyM)
                nearest = MapMatch(
                    coordinate: projection.coordinate,
                    segmentIndex: index,
                    distanceM: distanceM,
                    progress: (traversed + lengths[index] * projection.fraction) / totalLength,
                    confidence: max(0, min(1, 1 - distanceM / (uncertaintyM * 3)))
                )
            }
            traversed += lengths[index]
        }
        return nearest
    }
}

// MARK: - Observation compaction

/// Delta-friendly observation payload. Contains no passenger identity: no name,
/// phone, PNR, coach or seat, matching the API contract.
public struct CompactObservation: Codable, Sendable, Equatable {
    public let runId: String
    public let timestamp: Int
    public let latE5: Int
    public let lonE5: Int
    public let speedKph: Double
    public let accuracyM: Double
    public let routeProgress: Double
    public let matchDistanceM: Double
    public let consentVersion: Int
}

public struct ContributionContext: Sendable {
    public let runId: String
    public let route: [RailCoordinate]
    public init(runId: String, route: [RailCoordinate]) {
        self.runId = runId
        self.route = route
    }
}

/// A device fix, decoupled from CoreLocation so it is testable.
public struct DeviceLocation: Sendable {
    public let timestamp: TimeInterval
    public let mocked: Bool
    public let latitude: Double
    public let longitude: Double
    public let accuracy: Double?
    /// Metres per second, as CoreLocation reports it.
    public let speed: Double?

    public init(timestamp: TimeInterval, mocked: Bool = false,
                latitude: Double, longitude: Double,
                accuracy: Double?, speed: Double?) {
        self.timestamp = timestamp
        self.mocked = mocked
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.speed = speed
    }
}

public enum ContributionObservation {
    /// Match the gateway's active-run window before requesting device location.
    public static func isWithinRunWindow(originDate: String, departureTime: String,
                                         durationMinutes: Double?, now: Date = Date()) -> Bool {
        guard let departure = try? IndiaDate.instant(originDate: originDate, time: departureTime),
              let end = runWindowEnd(originDate: originDate, departureTime: departureTime,
                                     durationMinutes: durationMinutes) else { return false }
        return now >= departure.addingTimeInterval(-6 * 60 * 60)
            && now <= end
    }

    public static func runWindowEnd(originDate: String, departureTime: String,
                                    durationMinutes: Double?) -> Date? {
        guard let durationMinutes, durationMinutes.isFinite, durationMinutes > 0, durationMinutes <= 7 * 24 * 60,
              let departure = try? IndiaDate.instant(originDate: originDate, time: departureTime)
        else { return nil }
        return departure.addingTimeInterval(TimeInterval(durationMinutes + 24 * 60) * 60)
    }

    /// Preview/demo runs must never be contributed as real observations.
    public static func isPreviewRunId(_ runId: String) -> Bool {
        let trimmed = runId.trimmingCharacters(in: .whitespaces)
        guard let range = trimmed.range(of: "^(preview|demo)(?:$|[-:/_])",
                                        options: [.regularExpression, .caseInsensitive]) else {
            return false
        }
        return range.lowerBound == trimmed.startIndex
    }

    public static func compact(
        location: DeviceLocation,
        context: ContributionContext,
        consentVersion: Int,
        now: TimeInterval = Date().timeIntervalSince1970 * 1000,
        options: LocationFilterOptions = LocationFilterOptions()
    ) -> CompactObservation? {
        guard !context.runId.trimmingCharacters(in: .whitespaces).isEmpty,
              !isPreviewRunId(context.runId),
              !location.mocked else { return nil }

        let accuracyM = location.accuracy ?? .infinity
        let speedKph = (location.speed ?? -1) * 3.6
        let sample = LocationSample(
            latitude: location.latitude,
            longitude: location.longitude,
            timestamp: location.timestamp,
            accuracyM: accuracyM,
            speedKph: speedKph
        )
        guard MapMatcher.isUsable(sample, now: now, options: options) else { return nil }
        let point = RailCoordinate(latitude: sample.latitude, longitude: sample.longitude)
        guard let match = MapMatcher.match(point, route: context.route, accuracyM: accuracyM),
              match.confidence > 0 else { return nil }

        return CompactObservation(
            runId: context.runId,
            timestamp: Int(location.timestamp.rounded()),
            latE5: Int((match.coordinate.latitude * 100_000).rounded()),
            lonE5: Int((match.coordinate.longitude * 100_000).rounded()),
            speedKph: (speedKph * 10).rounded() / 10,
            accuracyM: (accuracyM * 10).rounded() / 10,
            routeProgress: (match.progress * 1_000_000).rounded() / 1_000_000,
            matchDistanceM: (match.distanceM * 10).rounded() / 10,
            consentVersion: consentVersion
        )
    }
}

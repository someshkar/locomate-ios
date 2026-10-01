//
//  RouteGeometry.swift
//  Locomate
//
//  Route sampling & distance interpolation — ported from
//  SmartRail `src/domain/routeGeometry.ts`.
//

import Foundation

public enum RouteGeometry {
    public static let earthRadiusKm: Double = 6_371

    /// Great-circle distance in km.
    public static func haversine(_ start: RailCoordinate, _ end: RailCoordinate) -> Double {
        func toRadians(_ degrees: Double) -> Double { degrees * .pi / 180 }
        let latitudeDelta = toRadians(end.latitude - start.latitude)
        let longitudeDelta = toRadians(end.longitude - start.longitude)
        let startLatitude = toRadians(start.latitude)
        let endLatitude = toRadians(end.latitude)
        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(startLatitude) * cos(endLatitude) * pow(sin(longitudeDelta / 2), 2)
        return 2 * earthRadiusKm * asin(sqrt(min(1, haversine)))
    }

    /// Interpolate a coordinate at `progress` (0…1) along the polyline by
    /// cumulative great-circle distance.
    public static func coordinate(along route: [RailCoordinate], progress: Double) throws -> RailCoordinate {
        guard let first = route.first else { throw RouteError.empty }
        guard route.count > 1 else { return first }

        let clamped = min(1, max(0, progress))
        let segmentDistances = (1..<route.count).map { haversine(route[$0 - 1], route[$0]) }
        let totalDistance = segmentDistances.reduce(0, +)
        guard totalDistance > 0 else { return first }

        let targetDistance = clamped * totalDistance
        var distanceBeforeSegment = 0.0
        var index = 0
        while index < segmentDistances.count - 1
            && distanceBeforeSegment + segmentDistances[index] < targetDistance {
            distanceBeforeSegment += segmentDistances[index]
            index += 1
        }

        let start = route[index]
        let end = route[index + 1]
        let fraction = segmentDistances[index] == 0
            ? 0
            : (targetDistance - distanceBeforeSegment) / segmentDistances[index]

        return RailCoordinate(
            latitude: start.latitude + (end.latitude - start.latitude) * fraction,
            longitude: start.longitude + (end.longitude - start.longitude) * fraction
        )
    }

    /// Sample `points` coordinates ending at `endProgress`. Mirrors `routeSample`.
    public static func sample(_ route: [RailCoordinate], endProgress: Double, points: Int = 72) -> [RailCoordinate] {
        guard route.count >= 2, endProgress > 0 else { return [] }
        let end = min(1, max(0, endProgress))
        return (0..<points).compactMap { index in
            try? coordinate(along: route, progress: end * Double(index) / Double(points - 1))
        }
    }

    public enum RouteError: Error { case empty }
}

//
//  MapDaylight.swift
//  Locomate
//
//  Solar elevation → map day/twilight/night blend — ported from
//  SmartRail `src/domain/mapDaylight.ts`.
//
//  Approximates the sun's position using NOAA fractional-year equations:
//  https://gml.noaa.gov/grad/solcalc/solareqns.PDF
//
//  This is a visual map treatment, not a sunrise forecast. UTC arithmetic keeps
//  it tied to the mapped place rather than the phone's timezone. The blend
//  begins at +3° and completes at civil twilight's −6° boundary.
//

import Foundation

public struct MapDaylight: Sendable, Equatable {
    /// Geometric solar elevation in degrees; negative values are below horizon.
    public let solarElevation: Double
    /// Continuous blend from daylight (0) to the night map (1).
    public let nightAmount: Double
    public let label: Label

    public enum Label: String, Sendable {
        case day = "Day"
        case twilight = "Twilight"
        case night = "Night"
    }
}

public enum MapDaylightEngine {
    static let indiaCenter = RailCoordinate(latitude: 22.6, longitude: 79.5)
    static let radians = Double.pi / 180
    static let daySeconds: Double = 86_400

    public static func compute(at coordinate: RailCoordinate, now: Date) -> MapDaylight {
        let timestamp = now.timeIntervalSince1970 * 1000

        let validCoordinate = coordinate.latitude.isFinite
            && abs(coordinate.latitude) <= 90
            && coordinate.longitude.isFinite
        let place = validCoordinate ? coordinate : indiaCenter

        // Map cameras may return longitudes outside ±180° after crossing the dateline.
        let rawLongitude = (place.longitude + 180).truncatingRemainder(dividingBy: 360)
        let longitude = (rawLongitude + 360).truncatingRemainder(dividingBy: 360) - 180
        let latitude = place.latitude * radians

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let year = utc.component(.year, from: now)
        let yearStart = utc.date(from: DateComponents(year: year, month: 1, day: 1))!
            .timeIntervalSince1970 * 1000
        let nextYearStart = utc.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            .timeIntervalSince1970 * 1000
        let daysInYear = (nextYearStart - yearStart) / daySeconds
        let fractionalDay = (timestamp - yearStart) / daySeconds
        let gamma = 2 * Double.pi / daysInYear * (fractionalDay - 0.5)

        let equationOfTime = 229.18 * (
            0.000075 + 0.001868 * cos(gamma) - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma) - 0.040849 * sin(2 * gamma)
        )
        let declination = 0.006918 - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma) - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma) - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)

        let components = utc.dateComponents([.hour, .minute, .second, .nanosecond], from: now)
        let utcMinutes = Double(components.hour ?? 0) * 60
            + Double(components.minute ?? 0)
            + Double(components.second ?? 0) / 60
            + Double(components.nanosecond ?? 0) / 60_000 / 1000

        let solarMinutes = utcMinutes + equationOfTime + 4 * longitude
        let hourAngle = (solarMinutes / 4 - 180) * radians
        let sinElevation = sin(latitude) * sin(declination)
            + cos(latitude) * cos(declination) * cos(hourAngle)
        let solarElevation = asin(min(1, max(-1, sinElevation))) / radians

        let twilightProgress = min(1, max(0, (3 - solarElevation) / 9))
        // Zero slope at either end avoids a visible snap into the palettes.
        let nightAmount = twilightProgress * twilightProgress * (3 - 2 * twilightProgress)

        let label: MapDaylight.Label = solarElevation >= 3
            ? .day
            : (solarElevation <= -6 ? .night : .twilight)

        return MapDaylight(solarElevation: solarElevation, nightAmount: nightAmount, label: label)
    }
}

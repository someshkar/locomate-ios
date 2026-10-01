//
//  Routes.swift
//  Locomate
//
//  Deep-link routing — ported from SmartRail `src/navigation/routes.ts`.
//  Scheme is `locomate://journeys/{trainNumber}?date=yyyy-MM-dd`.
//

import Foundation

public enum Routes {
    public static let scheme = "locomate"

    public struct JourneyDestination: Sendable, Equatable {
        public let trainNumber: String
        public let date: String
    }

    private static let trainPattern = try! NSRegularExpression(pattern: "^\\d{4,6}$")
    private static let datePattern = try! NSRegularExpression(
        pattern: "^(\\d{4})-(\\d{2})-(\\d{2})$"
    )

    public static func isValidTrainNumber(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return trainPattern.firstMatch(in: value, range: range) != nil
    }

    public static func isValidCalendarDate(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        guard let match = datePattern.firstMatch(in: value, range: range),
              let year = Int((value as NSString).substring(with: match.range(at: 1))),
              let month = Int((value as NSString).substring(with: match.range(at: 2))),
              let day = Int((value as NSString).substring(with: match.range(at: 3))),
              year > 0, (1...12).contains(month), day >= 1 else { return false }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    public static func journeyURL(trainNumber: String, date: String) throws -> URL {
        guard isValidTrainNumber(trainNumber) else { throw RouteError.invalidTrainNumber }
        guard isValidCalendarDate(date) else { throw RouteError.invalidDate }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "journeys"
        components.path = "/\(trainNumber)"
        components.queryItems = [URLQueryItem(name: "date", value: date)]
        guard let url = components.url else { throw RouteError.invalidDate }
        return url
    }

    public static func parse(_ url: URL) -> JourneyDestination? {
        guard url.scheme == scheme, url.host == "journeys" else { return nil }
        let trainNumber = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let date = components.queryItems?.first(where: { $0.name == "date" })?.value,
              isValidTrainNumber(trainNumber), isValidCalendarDate(date) else { return nil }
        return JourneyDestination(trainNumber: trainNumber, date: date)
    }

    public enum RouteError: Error, LocalizedError {
        case invalidTrainNumber
        case invalidDate
        public var errorDescription: String? {
            switch self {
            case .invalidTrainNumber: return "Train number must contain four to six digits."
            case .invalidDate: return "Date must be a valid YYYY-MM-DD calendar date."
            }
        }
    }
}

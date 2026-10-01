//
//  IndiaDate.swift
//  Locomate
//
//  India origin-date math — ported from SmartRail `src/domain/date.ts`.
//  The origin date is the run's India service date, not UTC today.
//

import Foundation

public enum IndiaDate {
    public static let timeZone = TimeZone(identifier: "Asia/Kolkata")!
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }()

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let originDatePattern = try! NSRegularExpression(pattern: "^\\d{4}-\\d{2}-\\d{2}$")

    /// Today's India origin date as `yyyy-MM-dd`.
    public static func today(_ date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    public static func isValid(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        guard originDatePattern.firstMatch(in: value, range: range) != nil else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        let (year, month, day) = (parts[0], parts[1], parts[2])
        guard year > 0, (1...12).contains(month), day >= 1 else { return false }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components) else { return false }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        return resolved.year == year && resolved.month == month && resolved.day == day
    }

    public static func addDays(_ originDate: String, _ days: Int) throws -> String {
        guard isValid(originDate), days != 0 || true else { throw DateError.invalid }
        var components = DateComponents()
        components.year = Int(originDate.prefix(4))
        components.month = Int(originDate.dropFirst(5).prefix(2))
        components.day = Int(originDate.suffix(2))
        guard let date = calendar.date(from: components),
              let shifted = calendar.date(byAdding: .day, value: days, to: date) else {
            throw DateError.invalid
        }
        return formatter.string(from: shifted)
    }

    public static func isFuture(_ originDate: String, today: String = IndiaDate.today()) -> Bool {
        isValid(originDate) && originDate > today
    }

    /// Parse `originDate` + `HH:mm[:ss]` as an India calendar instant.
    public static func instant(originDate: String, time: String) throws -> Date {
        guard isValid(originDate) else { throw DateError.invalid }
        let timeMatch = time.split(separator: ":")
        guard timeMatch.count == 2 || timeMatch.count == 3,
              let hour = Int(timeMatch[0]), let minute = Int(timeMatch[1]),
              (0...23).contains(hour), (0...59).contains(minute) else {
            throw DateError.invalid
        }
        let second = timeMatch.count == 3 ? Int(timeMatch[2]) ?? 0 : 0
        guard (0...59).contains(second) else { throw DateError.invalid }
        let combined = "\(originDate)T\(String(format: "%02d:%02d:%02d", hour, minute, second))"
        let parser = DateFormatter()
        parser.calendar = calendar
        parser.timeZone = timeZone
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = parser.date(from: combined) else { throw DateError.invalid }
        return date
    }

    public enum DateError: Error { case invalid }
}

/// Format an ISO 8601 instant (or a plain `HH:mm` clock string) for display in
/// India Standard Time. Mirrors `formatRailTime` from `types.ts`.
public enum RailTime {
    private static let display: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = IndiaDate.calendar
        formatter.timeZone = IndiaDate.timeZone
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    public static func format(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "Unavailable" }
        if !value.contains("T") { return value }
        guard let date = ISO8601DateFormatter.locomote.date(from: value) else { return value }
        return display.string(from: date)
    }
}

public extension ISO8601DateFormatter {
    // Configured once at launch and only read afterwards; safe to share.
    nonisolated(unsafe) static let locomote: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

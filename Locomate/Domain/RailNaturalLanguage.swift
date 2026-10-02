import Foundation

/// Human time copy shared by the Journey card and its provenance-aware delay label.
enum RailNaturalLanguage {
    static func delay(minutes: Int?, status: DelayStatus?, source: DataSource? = nil) -> String {
        guard let minutes, status != .unavailable else { return "Delay unavailable" }
        let qualifier: String
        if status == .stale { qualifier = " · stale" }
        else if status == .estimated || source == .predicted { qualifier = " · estimated" }
        else { qualifier = "" }
        if minutes > 0 { return "\(unit(minutes.magnitude, "minute")) late\(qualifier)" }
        if minutes < 0 { return "\(unit(minutes.magnitude, "minute")) early\(qualifier)" }
        return "\(status == .scheduled || status == nil ? "Scheduled" : "On time")\(qualifier)"
    }

    /// A timetable countdown is never a live ETA or a claim that the train has departed.
    static func departureCountdown(journey: Journey, plan: JourneyPlan, preview: Bool,
                                   now: Date = Date()) -> String? {
        guard !preview, let resolved = JourneyPlanLogic.resolve(journey: journey, plan: plan),
              journey.stops[resolved.boarding.index].state != .passed,
              journey.stops[resolved.boarding.index].actualDeparture == nil,
              let departure = scheduledBoarding(journey: journey, plan: resolved), departure > now else { return nil }
        return "\(duration(departure.timeIntervalSince(now))) until scheduled departure"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 60 else { return "Less than 1 minute" }
        // Clock strings are minute-granular. Round up so the display never says
        // zero minutes while a scheduled departure remains in the future.
        let minutes = UInt(min(ceil(seconds / 60), Double(UInt.max / 2)))
        if minutes >= 1_440 {
            return joined(unit(minutes / 1_440, "day"), remainder: minutes % 1_440 / 60, noun: "hour")
        }
        if minutes >= 60 { return joined(unit(minutes / 60, "hour"), remainder: minutes % 60, noun: "minute") }
        return unit(minutes, "minute")
    }

    /// Walk all preceding scheduled calls so a personal boarding after midnight
    /// stays on the run's next day. Missing timing never falls back to the origin.
    static func scheduledBoarding(journey: Journey, plan: JourneyPlan) -> Date? {
        guard Routes.isValidCalendarDate(plan.originDate),
              let resolved = JourneyPlanLogic.resolve(journey: journey, plan: plan) else { return nil }
        return scheduledEvent(journey: journey, originDate: plan.originDate,
                              index: resolved.boarding.index, departure: true)
    }

    /// Read every intervening call: comparing only endpoint clocks loses whole
    /// days on long runs and can confuse an arrival with the boarding departure.
    static func scheduledSegmentDuration(journey: Journey, plan: JourneyPlan) -> Int? {
        guard Routes.isValidCalendarDate(plan.originDate),
              let resolved = JourneyPlanLogic.resolve(journey: journey, plan: plan),
              let start = scheduledEvent(journey: journey, originDate: plan.originDate,
                                         index: resolved.boarding.index, departure: true),
              let end = scheduledEvent(journey: journey, originDate: plan.originDate,
                                       index: resolved.alighting.index, departure: false),
              end >= start else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }

    static func scheduledAlighting(journey: Journey, plan: JourneyPlan) -> Date? {
        guard let resolved = JourneyPlanLogic.resolve(journey: journey, plan: plan) else { return nil }
        return scheduledEvent(journey: journey, originDate: plan.originDate,
                              index: resolved.alighting.index, departure: false)
    }

    private static func scheduledEvent(journey: Journey, originDate: String,
                                       index target: Int, departure: Bool) -> Date? {
        guard journey.stops.indices.contains(target),
              let origin = journey.stops.first,
              var cursor = scheduled(origin.scheduledDeparture ?? journey.departureTime,
                                     originDate: originDate, after: nil) else { return nil }
        if target == 0 { return departure ? cursor : scheduled(origin.scheduledArrival, originDate: originDate, after: nil) }
        for index in 1...target {
            let stop = journey.stops[index]
            guard let arrival = scheduled(stop.scheduledArrival, originDate: originDate, after: cursor) else { return nil }
            if index == target && !departure { return arrival }
            cursor = arrival
            if let clock = stop.scheduledDeparture {
                guard let departure = scheduled(clock, originDate: originDate, after: cursor) else { return nil }
                cursor = departure
            } else if index == target {
                return nil
            }
        }
        return cursor
    }

    private static func scheduled(_ value: String, originDate: String, after previous: Date?) -> Date? {
        if value.contains("T") {
            guard let instant = ISO8601DateFormatter.locomote.date(from: value) ?? ISO8601DateFormatter().date(from: value),
                  previous.map({ instant >= $0 }) ?? (IndiaDate.today(instant) == originDate) else { return nil }
            return instant
        }
        guard value.range(of: #"\A(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?\z"#,
                          options: .regularExpression) != nil,
              var instant = try? IndiaDate.instant(originDate: originDate, time: value) else { return nil }
        if let previous {
            while instant < previous { instant = instant.addingTimeInterval(86_400) }
        }
        return instant
    }

    private static func unit(_ value: UInt, _ noun: String) -> String { "\(value) \(noun)\(value == 1 ? "" : "s")" }
    private static func joined(_ first: String, remainder: UInt, noun: String) -> String {
        remainder == 0 ? first : "\(first) \(unit(remainder, noun))"
    }
}

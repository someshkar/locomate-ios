import Foundation

/// Every value in the station card belongs to one resolved call in the personal
/// segment. Journey-level destination predictions are deliberately not inputs.
struct JourneyStopProjection {
    let heading: String
    let code: String
    let name: String
    let timeLabel: String
    let time: String?
    let detail: String
    let delayLabel: String
    let delayKind: StatusKind
    let distanceKm: Double?
    let platform: String?
    let platformLabel: String

    static func make(journey: Journey, plan: JourneyPlan?, originDate: String,
                     cached: Bool, preview: Bool, now: Date = Date()) -> Self? {
        let personal = plan?.originDate == originDate
            ? JourneyPlanLogic.resolve(journey: journey, plan: plan) : nil
        guard let resolved = personal ?? (try? JourneyPlanLogic.create(
            journey: journey, originDate: originDate, boardingIndex: 0,
            alightingIndex: journey.stops.count - 1)) else { return nil }
        let boarding = journey.stops[resolved.boarding.index]
        let alighting = journey.stops[resolved.alighting.index]
        let future = IndiaDate.isFuture(originDate, today: IndiaDate.today(now))
            || RailNaturalLanguage.departureCountdown(journey: journey, plan: resolved,
                                                      preview: false, now: now) != nil
        let position = JourneyPositionEvidence.display(journey: journey, cached: cached,
                                                        preview: preview, now: now)
        // A repeated station code is ambiguous without a call index in the position contract.
        let matching = journey.stops.indices.filter { journey.stops[$0].code == journey.position.nextStation }
        let next = matching.count == 1 ? matching[0] : nil
        let usablePosition = !preview && !future && (position == .observed || position == .stale)
        let boarded = boarding.state == .passed || validTime(boarding.actualDeparture) != nil
        let ended = alighting.state == .passed || validTime(alighting.actualArrival) != nil
        let index: Int
        let departure: Bool
        let heading: String
        if !preview && !future && ended {
            index = resolved.alighting.index
            departure = false
            heading = validTime(alighting.actualArrival) == nil ? "Your destination" : "Recorded arrival at"
        } else if usablePosition, let next, next > resolved.boarding.index,
                  next <= resolved.alighting.index, journey.stops[next].state != .passed,
                  validTime(journey.stops[next].actualDeparture) == nil {
            index = next
            departure = false
            heading = position == .stale ? "Last reported next stop" : "Next stop"
        } else if !preview && !future && (boarded || (usablePosition && next.map { $0 > resolved.alighting.index } == true)) {
            index = resolved.alighting.index
            departure = false
            heading = cached ? "Saved destination" : "Your destination"
        } else {
            index = resolved.boarding.index
            departure = true
            heading = preview ? "Preview boarding" : cached ? "Saved boarding stop" : "Boarding at"
        }

        let stop = journey.stops[index]
        let stale = cached || stop.delayStatus == .stale || journey.provenance?.freshness == "stale"
        let schedule = departure
            ? validTime(stop.scheduledDeparture) ?? (index == 0 ? validTime(journey.departureTime) : nil)
            : validTime(stop.scheduledArrival)
        let actual = preview ? nil : validTime(departure ? stop.actualDeparture : stop.actualArrival)
        let forecast: AvailableStopForecast? = {
            guard !departure, !preview, !stale, let stopForecast = stop.forecast,
                  case .available(let value) = stopForecast,
                  value.source != .unavailable, validTime(value.p50) != nil else { return nil }
            return value
        }()
        let time: String?
        let label: String
        let detail: String
        if let actual {
            time = actual
            label = departure ? "Actual departure" : "Actual arrival"
            detail = cached ? "Saved report · recorded station event"
                : stale ? "Stale report · recorded station event" : "Recorded station event"
        } else if let forecast {
            time = validTime(forecast.p50)
            label = forecast.source == .observed ? "Observed arrival" : "Estimated arrival"
            detail = "\(ForecastPresentation.sourceLabel(.available(forecast))) · Features \(ForecastPresentation.featureFreshness(forecast.featureAsOf, now: now))"
        } else {
            time = schedule
            label = departure ? "Scheduled departure" : "Scheduled arrival"
            detail = preview ? "Preview timetable · not live"
                : cached ? "Saved timetable · current timing unavailable"
                : stale ? "Stale report · showing timetable"
                : departure ? "Timetable · departure estimate unavailable" : "Timetable · arrival forecast unavailable"
        }

        // Arrival forecasts cannot supply a departure delay. Actual event delays
        // likewise come from that event, rather than a journey-wide estimate.
        let delay: Int? = {
            guard !preview else { return nil }
            if departure { return actual == nil ? nil : stop.departureDelayMinutes }
            if actual != nil { return stop.arrivalDelayMinutes }
            return forecast != nil || stale ? stop.delayMinutes : nil
        }()
        let delayStatus: DelayStatus = stale ? .stale : actual != nil ? .observed
            : forecast?.source == .observed ? .observed : forecast != nil ? .estimated : .unavailable
        let distance = position == .observed && !cached && !preview && !future && !ended && next == index
            && journey.position.distanceToNextKm.isFinite && journey.position.distanceToNextKm >= 0
            ? journey.position.distanceToNextKm : nil
        return Self(heading: heading, code: stop.code, name: stop.name, timeLabel: label, time: time,
                    detail: detail,
                    delayLabel: preview ? "Timetable only" : RailNaturalLanguage.delay(minutes: delay, status: delayStatus),
                    delayKind: StatusMapping.statusForDelay(delayMinutes: delay, delayStatus: delayStatus),
                    distanceKm: distance, platform: preview ? nil : stop.knownPlatform,
                    platformLabel: stale ? "Last known platform" : "Platform")
    }

    private static func validTime(_ value: String?) -> String? {
        guard let value else { return nil }
        if value.contains("T") {
            guard let date = ISO8601DateFormatter.locomote.date(from: value) ?? ISO8601DateFormatter().date(from: value) else { return nil }
            return RailTime.format(ISO8601DateFormatter.locomote.string(from: date))
        }
        guard value.range(of: #"\A(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?\z"#,
                          options: .regularExpression) != nil else { return nil }
        return String(value.prefix(5))
    }

    /// Summary clocks use the selected call, never a destination-wide compatibility value.
    static func summaryClock(stop: StationStop, departure: Bool, preview: Bool, cached: Bool,
                             originDeparture: String? = nil, stale: Bool = false) -> JourneySummaryClock {
        let event = departure ? "departure" : "arrival"
        if !preview, let actual = validTime(departure ? stop.actualDeparture : stop.actualArrival) {
            return .init(time: actual, label: "\(cached ? "Saved actual" : "Actual") \(event)", evidence: .recorded)
        }
        if !departure, !preview, !cached, !stale, stop.delayStatus != .stale,
           case .available(let forecast) = stop.forecast,
           forecast.source != .unavailable, let time = validTime(forecast.p50) {
            return .init(time: time, label: forecast.source == .observed ? "Observed arrival" : "Estimated arrival",
                         evidence: forecast.source == .observed ? .recorded : .estimated)
        }
        let time = departure ? validTime(stop.scheduledDeparture) ?? validTime(originDeparture)
            : validTime(stop.scheduledArrival)
        return .init(time: time, label: "\(cached ? "Saved scheduled" : "Scheduled") \(event)", evidence: .scheduled)
    }
}

struct JourneySummaryClock {
    enum Evidence { case scheduled, estimated, recorded }
    let time: String?
    let label: String
    let evidence: Evidence
}

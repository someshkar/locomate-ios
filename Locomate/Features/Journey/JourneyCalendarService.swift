//
//  JourneyCalendarService.swift
//  Locomate
//
//  Adds a journey to the system calendar using the event composer, so no
//  calendar READ permission is required — ported from SmartRail
//  `src/services/journeyCalendar.native.ts` + `src/domain/journeyDates.ts`.
//

import Foundation
import EventKitUI
import EventKit
import UIKit

public enum JourneyCalendarResult: Sendable {
    case saved
    case cancelled
    case unavailable
}

@MainActor
public enum JourneyCalendarService {
    public static func add(
        journey: Journey,
        originDate: String,
        plan: JourneyPlan?
    ) -> JourneyCalendarResult {
        guard let details = CalendarDetails.build(journey: journey, originDate: originDate, plan: plan) else {
            return .unavailable
        }
        guard EKEventStore.authorizationStatus(for: .event) != .denied else { return .cancelled }

        let eventStore = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = eventStore

        let event = EKEvent(eventStore: eventStore)
        event.title = details.title
        event.startDate = details.startDate
        event.endDate = details.endDate
        event.location = details.location
        event.notes = details.notes
        event.url = details.url
        event.calendar = eventStore.defaultCalendarForNewEvents
        controller.event = event

        guard let presenter = topViewController() else { return .unavailable }
        controller.editViewDelegate = CalendarComposerDelegate.shared
        presenter.present(controller, animated: true)
        return .saved
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
}

/// Delegate holder — the composer requires an object to dismiss it.
@MainActor
final class CalendarComposerDelegate: NSObject, @preconcurrency EKEventEditViewDelegate {
    static let shared = CalendarComposerDelegate()

    func eventEditViewController(
        _ controller: EKEventEditViewController,
        didCompleteWith action: EKEventEditViewAction
    ) {
        controller.dismiss(animated: true)
    }
}

/// Calendar event details — ported from `buildJourneyCalendarDetails`.
public enum CalendarDetails {
    public struct Details: Sendable {
        public let title: String
        public let location: String
        public let notes: String
        public let url: URL?
        public let startDate: Date
        public let endDate: Date
    }

    public static func build(journey: Journey, originDate: String, plan: JourneyPlan?) -> Details? {
        guard var startDate = try? IndiaDate.instant(originDate: originDate, time: journey.departureTime) else {
            return nil
        }
        var endDate: Date
        if let duration = journey.scheduledDurationMinutes {
            endDate = startDate.addingTimeInterval(TimeInterval(duration * 60))
        } else if let scheduled = try? IndiaDate.instant(originDate: originDate, time: journey.scheduledArrival) {
            endDate = scheduled
            if scheduled <= startDate {
                endDate = scheduled.addingTimeInterval(86_400)
            }
        } else {
            return nil
        }

        var route = "\(journey.originName) (\(journey.originCode)) to \(journey.destinationName) (\(journey.destinationCode))"

        // When the personal segment differs from the full run, use its times.
        if let plan, let resolved = JourneyPlanLogic.resolve(journey: journey, plan: plan),
           resolved.boarding.index != 0 || resolved.alighting.index != journey.stops.count - 1 {
            if let boarded = advanceTimes(journey: journey, originDate: originDate, plan: resolved) {
                startDate = boarded.start
                endDate = boarded.end
            }
            route = "\(resolved.boarding.name) (\(resolved.boarding.code)) to \(resolved.alighting.name) (\(resolved.alighting.code))"
        }

        let url = try? Routes.journeyURL(trainNumber: journey.trainNumber, date: originDate)
        return Details(
            title: "\(journey.trainNumber) \(journey.trainName)",
            location: route,
            notes: "Route: \(route)\nOpen journey: \(url?.absoluteString ?? "")",
            url: url,
            startDate: startDate,
            endDate: endDate
        )
    }

    /// Walk the timetable chronologically across midnight to derive the personal
    /// segment's start and end instants.
    private static func advanceTimes(
        journey: Journey,
        originDate: String,
        plan: JourneyPlan
    ) -> (start: Date, end: Date)? {
        guard let departure = try? IndiaDate.instant(originDate: originDate, time: journey.departureTime) else {
            return nil
        }
        var cursor = departure
        var start = departure
        var end: Date?

        for index in 0...plan.alighting.index {
            guard journey.stops.indices.contains(index) else { return nil }
            let stop = journey.stops[index]
            if index > 0, let arrival = try? IndiaDate.instant(originDate: originDate, time: stop.scheduledArrival) {
                var next = arrival
                while next < cursor { next = next.addingTimeInterval(86_400) }
                cursor = next
            }
            if index == plan.alighting.index {
                end = cursor
                break
            }
            let clock = stop.scheduledDeparture ?? stop.scheduledArrival
            if let leaving = try? IndiaDate.instant(originDate: originDate, time: clock) {
                var next = leaving
                while next < cursor { next = next.addingTimeInterval(86_400) }
                cursor = next
            }
            if index == plan.boarding.index { start = cursor }
        }
        guard let end else { return nil }
        return (start, end)
    }
}

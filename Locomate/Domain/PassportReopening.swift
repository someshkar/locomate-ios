import Foundation

enum PassportReopening {
    static func destination(for saved: SavedJourney, production: Bool) -> Routes.JourneyDestination? {
        guard saved.preview == !production,
              Routes.isValidTrainNumber(saved.trainNumber),
              Routes.isValidCalendarDate(saved.originDate) else { return nil }
        return .init(trainNumber: saved.trainNumber, date: saved.originDate)
    }

    /// Resolve the saved calls, not a subsequently edited working plan. Legacy
    /// rows can reopen a segment only when its saved call sequence is unique.
    static func plan(for saved: SavedJourney, journey: Journey, originDate: String) -> JourneyPlan? {
        guard saved.trainNumber == journey.trainNumber, saved.originDate == originDate, journey.travelDate == originDate,
              Routes.isValidCalendarDate(originDate) else { return nil }
        let codes = saved.stations.map(\.code)
        guard codes.count >= 2, codes.first == saved.originCode,
              codes.last == saved.destinationCode, codes.allSatisfy({ !$0.isEmpty }),
              codes.count <= journey.stops.count else { return nil }

        func matches(_ start: Int) -> Bool {
            start >= 0 && start <= journey.stops.count - codes.count
                && Array(journey.stops[start..<(start + codes.count)].map(\.code)) == codes
        }
        if let stored = saved.personalPlan {
            guard stored.trainNumber == saved.trainNumber, stored.originDate == saved.originDate,
                  stored.boarding.code == saved.originCode, stored.alighting.code == saved.destinationCode else { return nil }
            if stored.boarding.index >= 0, stored.alighting.index < journey.stops.count,
               stored.alighting.index >= stored.boarding.index,
               stored.alighting.index - stored.boarding.index == codes.count - 1,
               matches(stored.boarding.index) {
                return try? JourneyPlanLogic.create(journey: journey, originDate: originDate,
                    boardingIndex: stored.boarding.index, alightingIndex: stored.alighting.index)
            }
        }
        let starts = (0...(journey.stops.count - codes.count)).filter(matches)
        guard starts.count == 1, let start = starts.first else { return nil }
        return try? JourneyPlanLogic.create(journey: journey, originDate: originDate,
            boardingIndex: start, alightingIndex: start + codes.count - 1)
    }
}

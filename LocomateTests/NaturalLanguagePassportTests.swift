import Foundation
import Testing
@testable import Locomate

@Suite("Natural journey language")
struct NaturalLanguageTests {
    @Test("countdown uses full words with singular and boundary handling")
    func durationWords() {
        #expect(RailNaturalLanguage.duration(28 * 3_600) == "1 day 4 hours")
        #expect(RailNaturalLanguage.duration(3_660) == "1 hour 1 minute")
        #expect(RailNaturalLanguage.duration(86_400) == "1 day")
        #expect(RailNaturalLanguage.duration(60) == "1 minute")
        #expect(RailNaturalLanguage.duration(59) == "Less than 1 minute")
    }

    @Test("natural delay copy preserves unknown, estimated, and stale evidence")
    func delayEvidence() {
        #expect(RailNaturalLanguage.delay(minutes: 1, status: .observed) == "1 minute late")
        #expect(RailNaturalLanguage.delay(minutes: -1, status: .observed) == "1 minute early")
        #expect(RailNaturalLanguage.delay(minutes: 18, status: .estimated) == "18 minutes late · estimated")
        #expect(RailNaturalLanguage.delay(minutes: -5, status: .stale) == "5 minutes early · stale")
        #expect(RailNaturalLanguage.delay(minutes: 0, status: .observed, source: .predicted) == "On time · estimated")
        #expect(RailNaturalLanguage.delay(minutes: nil, status: .stale) == "Delay unavailable")
        #expect(RailNaturalLanguage.delay(minutes: 12, status: .unavailable) == "Delay unavailable")
        #expect(RailNaturalLanguage.delay(minutes: 0, status: .scheduled) == "Scheduled")
        #expect(RailNaturalLanguage.delay(minutes: Int.min, status: .stale).hasSuffix("minutes early · stale"))
    }

    @Test("personal boarding walks the origin timetable across midnight")
    func overnightBoarding() throws {
        let journey = try fixture()
        let plan = try JourneyPlanLogic.create(journey: journey, originDate: "2026-10-01", boardingIndex: 1, alightingIndex: 2)
        let boarding = try #require(RailNaturalLanguage.scheduledBoarding(journey: journey, plan: plan))
        #expect(boarding == (try IndiaDate.instant(originDate: "2026-10-02", time: "01:20")))
        let now = boarding.addingTimeInterval(-28 * 3_600)
        #expect(RailNaturalLanguage.departureCountdown(journey: journey, plan: plan, preview: false, now: now)
                == "1 day 4 hours until scheduled departure")
        #expect(RailNaturalLanguage.departureCountdown(journey: journey, plan: plan, preview: false, now: boarding) == nil)
    }

    @Test("missing or invalid boarding times never count down to an origin fallback")
    func rejectsMissingSchedule() throws {
        for departure in [NSNull(), "25:01", "01:20:xx"] as [Any] {
            let journey = try fixture(boardingDeparture: departure)
            let plan = try JourneyPlanLogic.create(journey: journey, originDate: "2026-10-01", boardingIndex: 1, alightingIndex: 2)
            #expect(RailNaturalLanguage.scheduledBoarding(journey: journey, plan: plan) == nil)
        }
    }

    @Test("preview and already departed stops never acquire a countdown")
    func excludesPreviewAndDeparted() throws {
        let futureNow = try IndiaDate.instant(originDate: "2026-09-30", time: "12:00")
        for journey in [try fixture(boardingState: "passed"), try fixture(actualDeparture: "01:21")] {
            let plan = try JourneyPlanLogic.create(journey: journey, originDate: "2026-10-01", boardingIndex: 1, alightingIndex: 2)
            #expect(RailNaturalLanguage.departureCountdown(journey: journey, plan: plan, preview: false, now: futureNow) == nil)
        }
        let journey = try fixture()
        let plan = JourneyPlanLogic.default(journey: journey, originDate: "2026-10-01")
        #expect(RailNaturalLanguage.departureCountdown(journey: journey, plan: plan, preview: true, now: futureNow) == nil)
    }

    private func fixture(boardingDeparture: Any = "01:20", boardingState: String = "upcoming",
                         actualDeparture: String? = nil) throws -> Journey {
        let pack = try #require(RoutePackStore.pack("12137"))
        let sample = PreviewData.journey(from: pack, originDate: "2026-10-01")
        var raw = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        var stops = try #require(raw["stops"] as? [[String: Any]])
        stops = Array(stops.prefix(3))
        for index in stops.indices { stops[index]["state"] = "upcoming" }
        raw["departureTime"] = "23:30"
        stops[0]["scheduledArrival"] = "23:30"
        stops[0]["scheduledDeparture"] = "23:30"
        stops[1]["scheduledArrival"] = "01:10"
        stops[1]["scheduledDeparture"] = boardingDeparture
        stops[1]["state"] = boardingState
        stops[1]["actualDeparture"] = actualDeparture.map { $0 as Any } ?? NSNull()
        stops[2]["scheduledArrival"] = "03:00"
        raw["stops"] = stops
        return try JSONDecoder().decode(Journey.self, from: JSONSerialization.data(withJSONObject: raw))
    }
}

@Suite("Passport origin-year periods")
struct PassportPeriodTests {
    @Test("years follow real run origin dates, not save time or preview dates")
    func realYearsOnly() {
        let journeys = [saved("new", date: "2026-01-01", distance: 30),
                        saved("old", date: "2025-12-31", distance: 20),
                        saved("preview", date: "2027-01-01", distance: 999, preview: true),
                        saved("legacy", date: "2028-01-01", distance: 999, preview: nil),
                        saved("undated", date: "2026-02-30", distance: 5)]
        #expect(PassportPeriod.years(in: journeys) == [2026, 2025])
        #expect(PassportPeriod.year(2025).filter(journeys).map(\.id) == ["old"])
        #expect(PassportPeriod.year(2026).filter(journeys).map(\.id) == ["new"])
        #expect(PassportPeriod.allTime.filter(journeys).count == 5)
    }

    @Test("year totals aggregate only the saved personal segments selected")
    func segmentTotals() {
        let journeys = [saved("a", date: "2026-03-01", distance: 30),
                        saved("b", date: "2026-12-31", distance: 15),
                        saved("c", date: "2025-03-01", distance: 200),
                        saved("preview", date: "2026-03-01", distance: 999, preview: true)]
        let year = Passport.summarize(PassportPeriod.year(2026).filter(journeys))
        #expect(year.trips == 2)
        #expect(year.distanceKm == 45)
        #expect(Passport.summarize(PassportPeriod.allTime.filter(journeys)).distanceKm == 245)
        #expect(PassportPeriod.year(2024).filter(journeys).isEmpty)
    }

    private func saved(_ id: String, date: String, distance: Double, preview: Bool? = false) -> SavedJourney {
        SavedJourney(id: id, trainNumber: "12137", trainName: "Test segment", originCode: "A", originName: "A",
                     destinationCode: "B", destinationName: "B", originDate: date, departureTime: "23:00",
                     scheduledArrival: "01:00", predictedArrival: "01:00", distanceKm: distance, minutes: 120,
                     delayMinutes: nil, stations: [], routeCoordinates: nil, savedAt: "2026-10-01T10:00:00Z",
                     completedAt: nil, preview: preview)
    }
}

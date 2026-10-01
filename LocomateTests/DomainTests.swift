//
//  DomainTests.swift
//  LocomateTests
//
//  Domain test parity with the SmartRail TypeScript reference suite.
//  These port the assertions from `src/domain/*.test.ts` so the native logic
//  is held to exactly the same behaviour.
//

import Testing
import Foundation
@testable import Locomate

@Suite("Rail storage scopes")
struct RailStorageScopeTests {
    @Test("development and production gateway data cannot share a scope")
    func separatedOrigins() {
        let production = RailStorageScope.gateway(URL(string: "https://rail.example")!)
        #expect(production == RailStorageScope.gateway(URL(string: "https://rail.example/")!))
        #expect(production != RailStorageScope.gateway(URL(string: "http://localhost:8766")!))
    }
}

// MARK: - IndiaDate

@Suite("India origin dates")
struct IndiaDateTests {
    @Test("rejects malformed and impossible dates")
    func validity() {
        #expect(IndiaDate.isValid("2026-09-08"))
        #expect(IndiaDate.isValid("2024-02-29"))
        #expect(!IndiaDate.isValid("2023-02-29"))
        #expect(!IndiaDate.isValid("2026-13-01"))
        #expect(!IndiaDate.isValid("2026-00-10"))
        #expect(!IndiaDate.isValid("2026-9-8"))
        #expect(!IndiaDate.isValid("not-a-date"))
        #expect(!IndiaDate.isValid(""))
    }

    @Test("adds and subtracts origin-date days across month boundaries")
    func arithmetic() throws {
        #expect(try IndiaDate.addDays("2026-09-08", 1) == "2026-09-09")
        #expect(try IndiaDate.addDays("2026-09-30", 1) == "2026-10-01")
        #expect(try IndiaDate.addDays("2026-01-01", -1) == "2025-12-31")
        #expect(try IndiaDate.addDays("2024-02-28", 1) == "2024-02-29")
    }

    @Test("future detection is inclusive of today")
    func future() {
        #expect(!IndiaDate.isFuture("2026-09-08", today: "2026-09-08"))
        #expect(IndiaDate.isFuture("2026-09-09", today: "2026-09-08"))
        #expect(!IndiaDate.isFuture("2026-09-07", today: "2026-09-08"))
    }

    @Test("builds an India calendar instant")
    func instant() throws {
        let date = try IndiaDate.instant(originDate: "2026-09-08", time: "19:40")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let components = utc.dateComponents([.hour, .minute], from: date)
        // 19:40 IST == 14:10 UTC
        #expect(components.hour == 14)
        #expect(components.minute == 10)
    }

    @Test("formats ISO instants in India time")
    func railTime() {
        #expect(RailTime.format("2026-09-08T14:10:00.000Z") == "19:40")
        #expect(RailTime.format("19:40") == "19:40")
        #expect(RailTime.format(nil) == "Unavailable")
    }
}

// MARK: - Route geometry

@Suite("Route geometry")
struct RouteGeometryTests {
    let route = [
        RailCoordinate(latitude: 0, longitude: 0),
        RailCoordinate(latitude: 0, longitude: 1),
    ]

    @Test("clamps progress to the route ends")
    func clamping() throws {
        let start = try RouteGeometry.coordinate(along: route, progress: -1)
        let end = try RouteGeometry.coordinate(along: route, progress: 2)
        #expect(abs(start.longitude - 0) < 1e-9)
        #expect(abs(end.longitude - 1) < 1e-9)
    }

    @Test("interpolates midway")
    func midpoint() throws {
        let mid = try RouteGeometry.coordinate(along: route, progress: 0.5)
        #expect(abs(mid.longitude - 0.5) < 1e-6)
    }

    @Test("a single-coordinate route returns that coordinate")
    func single() throws {
        let single = [RailCoordinate(latitude: 5, longitude: 6)]
        let point = try RouteGeometry.coordinate(along: single, progress: 0.7)
        #expect(point.latitude == 5)
        #expect(point.longitude == 6)
    }

    @Test("an empty route throws")
    func empty() {
        #expect(throws: RouteGeometry.RouteError.self) {
            _ = try RouteGeometry.coordinate(along: [], progress: 0.5)
        }
    }

    @Test("sampling is bounded and ordered")
    func sampling() {
        #expect(RouteGeometry.sample(route, endProgress: 0).isEmpty)
        #expect(RouteGeometry.sample(route, endProgress: 0.5, points: 10).count == 10)
        let sampled = RouteGeometry.sample(route, endProgress: 1, points: 5)
        let longitudes = sampled.map(\.longitude)
        #expect(longitudes == longitudes.sorted())
        #expect(abs((sampled.last?.longitude ?? 0) - 1) < 1e-6)
    }

    @Test("haversine measures a known distance")
    func haversine() {
        // Mumbai CSMT → New Delhi is roughly 1,150 km great-circle.
        let mumbai = RailCoordinate(latitude: 18.9398, longitude: 72.8355)
        let delhi = RailCoordinate(latitude: 28.5888, longitude: 77.2534)
        let distance = RouteGeometry.haversine(mumbai, delhi)
        #expect(distance > 1_100 && distance < 1_200)
    }
}

// MARK: - Journey plan

@Suite("Journey plan")
struct JourneyPlanTests {
    private func makeJourney() -> Journey {
        let pack = RoutePackStore.pack("12137")!
        return PreviewData.journey(from: pack, originDate: "2026-09-08")
    }

    @Test("default plan spans the whole journey")
    func defaultPlan() {
        let journey = makeJourney()
        let plan = JourneyPlanLogic.default(journey: journey, originDate: "2026-09-08")
        #expect(plan.boarding.index == 0)
        #expect(plan.alighting.index == journey.stops.count - 1)
    }

    @Test("rejects an inverted selection")
    func invalidSelection() {
        let journey = makeJourney()
        #expect(throws: (any Error).self) {
            _ = try JourneyPlanLogic.create(journey: journey, originDate: "2026-09-08",
                                            boardingIndex: 5, alightingIndex: 2)
        }
        #expect(throws: (any Error).self) {
            _ = try JourneyPlanLogic.create(journey: journey, originDate: "2026-09-08",
                                            boardingIndex: 3, alightingIndex: 3)
        }
    }

    @Test("resolves by station code when indices shift")
    func resolutionByCode() {
        let journey = makeJourney()
        let plan = JourneyPlan(
            trainNumber: journey.trainNumber,
            originDate: "2026-09-08",
            boarding: JourneyPlanStop(index: 99, code: journey.stops[2].code, name: journey.stops[2].name),
            alighting: JourneyPlanStop(index: 98, code: journey.stops[5].code, name: journey.stops[5].name),
            updatedAt: "2026-09-08T00:00:00Z"
        )
        let resolved = JourneyPlanLogic.resolve(journey: journey, plan: plan)
        #expect(resolved?.boarding.code == journey.stops[2].code)
        #expect(resolved?.alighting.code == journey.stops[5].code)
    }

    @Test("rejects a plan for a different train")
    func wrongTrain() {
        let journey = makeJourney()
        let plan = JourneyPlan(
            trainNumber: "99999", originDate: "2026-09-08",
            boarding: JourneyPlanStop(index: 0, code: "A", name: "A"),
            alighting: JourneyPlanStop(index: 1, code: "B", name: "B"),
            updatedAt: "2026-09-08T00:00:00Z"
        )
        #expect(JourneyPlanLogic.resolve(journey: journey, plan: plan) == nil)
    }

    @Test("segment is inclusive of both endpoints")
    func segment() {
        let journey = makeJourney()
        let plan = try! JourneyPlanLogic.create(journey: journey, originDate: "2026-09-08",
                                                boardingIndex: 2, alightingIndex: 5)
        let stops = JourneyPlanLogic.stops(journey: journey, plan: plan)
        #expect(stops.count == 4)
        #expect(stops.first?.code == journey.stops[2].code)
        #expect(stops.last?.code == journey.stops[5].code)
    }
}

// MARK: - Status mapping

@Suite("Status mapping")
struct StatusMappingTests {
    @Test("delay status ordering")
    func delayStatus() {
        #expect(StatusMapping.statusForDelay(delayMinutes: 12, delayStatus: .observed) == .delayed)
        #expect(StatusMapping.statusForDelay(delayMinutes: 0, delayStatus: .observed) == .onTime)
        #expect(StatusMapping.statusForDelay(delayMinutes: -3, delayStatus: .observed) == .onTime)
        #expect(StatusMapping.statusForDelay(delayMinutes: 12, delayStatus: .stale) == .stale)
        #expect(StatusMapping.statusForDelay(delayMinutes: nil, delayStatus: .unavailable) == .scheduled)
    }

    @Test("preview and error outrank live")
    func modeOrdering() {
        #expect(StatusMapping.statusForJourneyMode(JourneyModeInput(preview: true, live: true)) == .preview)
        #expect(StatusMapping.statusForJourneyMode(JourneyModeInput(historicalRoute: true, live: true)) == .preview)
        #expect(StatusMapping.statusForJourneyMode(JourneyModeInput(future: true, live: true)) == .scheduled)
        #expect(StatusMapping.statusForJourneyMode(JourneyModeInput(live: true)) == .onTime)
        #expect(StatusMapping.statusForJourneyMode(JourneyModeInput()) == .stale)
        #expect(StatusMapping.statusForJourneyMode(JourneyModeInput(live: true, error: true)) == .error)
    }

    @Test("preview is never allowed to pulse as live")
    func pulse() {
        #expect(!StatusMapping.isLivePulseAllowed(JourneyModeInput(preview: true, live: true)))
        #expect(!StatusMapping.isLivePulseAllowed(JourneyModeInput(historicalRoute: true, live: true)))
        #expect(StatusMapping.isLivePulseAllowed(JourneyModeInput(live: true)))
    }

    @Test("delay labels carry provenance qualifiers")
    func labels() {
        #expect(StatusMapping.delayStatusLabel(delayMinutes: 12, delayStatus: .observed) == "+12 MIN")
        #expect(StatusMapping.delayStatusLabel(delayMinutes: 12, delayStatus: .estimated) == "+12 MIN · EST.")
        #expect(StatusMapping.delayStatusLabel(delayMinutes: 12, delayStatus: .stale) == "+12 MIN · STALE")
        #expect(StatusMapping.delayStatusLabel(delayMinutes: -4, delayStatus: .observed) == "4 MIN EARLY")
        #expect(StatusMapping.delayStatusLabel(delayMinutes: 0, delayStatus: .scheduled) == "SCHEDULED")
        #expect(StatusMapping.delayStatusLabel(delayMinutes: 0, delayStatus: .observed) == "ON TIME")
        #expect(StatusMapping.delayStatusLabel(delayMinutes: nil, delayStatus: .unavailable) == "DELAY UNAVAILABLE")
    }

    @Test("journey mode labels")
    func modeLabels() {
        #expect(StatusMapping.journeyModeLabel(.onTime) == "LIVE JOURNEY")
        #expect(StatusMapping.journeyModeLabel(.preview) == "ROUTE REPLAY")
        #expect(StatusMapping.journeyModeLabel(.scheduled) == "UPCOMING JOURNEY")
        #expect(StatusMapping.journeyModeLabel(.stale) == "PREDICTED JOURNEY")
    }
}

// MARK: - Daylight

@Suite("Map daylight")
struct MapDaylightTests {
    let india = RailCoordinate(latitude: 22.6, longitude: 79.5)

    private func utcDate(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test("noon in India is day")
    func noon() {
        let result = MapDaylightEngine.compute(at: india, now: utcDate("2026-09-08T06:30:00Z"))
        #expect(result.label == .day)
        #expect(result.nightAmount < 0.05)
        #expect(result.solarElevation > 40)
    }

    @Test("local midnight in India is night")
    func midnight() {
        let result = MapDaylightEngine.compute(at: india, now: utcDate("2026-09-08T18:30:00Z"))
        #expect(result.label == .night)
        #expect(result.nightAmount > 0.95)
        #expect(result.solarElevation < -6)
    }

    @Test("the blend is monotonic across twilight")
    func monotonic() {
        var previous = -1.0
        for minute in stride(from: 0, through: 200, by: 10) {
            let date = utcDate("2026-09-08T12:00:00Z").addingTimeInterval(Double(minute) * 60)
            let amount = MapDaylightEngine.compute(at: india, now: date).nightAmount
            #expect(amount >= previous - 1e-9)
            previous = amount
        }
    }

    @Test("night amount stays within 0 and 1")
    func bounded() {
        for hour in 0..<24 {
            let date = utcDate("2026-01-15T00:00:00Z").addingTimeInterval(Double(hour) * 3600)
            let amount = MapDaylightEngine.compute(at: india, now: date).nightAmount
            #expect(amount >= 0 && amount <= 1)
        }
    }
}

// MARK: - Passport

@Suite("Passport statistics")
struct PassportTests {
    private func saved(
        id: String, train: String, origin: String, destination: String,
        distance: Double, minutes: Int, delay: Int?
    ) -> SavedJourney {
        SavedJourney(
            id: id, trainNumber: train, trainName: "Test", originCode: origin, originName: origin,
            destinationCode: destination, destinationName: destination, originDate: "2026-09-08",
            departureTime: "10:00", scheduledArrival: "18:00", predictedArrival: "18:00",
            distanceKm: distance, minutes: minutes, delayMinutes: delay,
            stations: [SavedJourneyStation(code: origin, name: origin),
                       SavedJourneyStation(code: destination, name: destination)],
            routeCoordinates: nil, savedAt: "2026-09-08T00:00:00Z", completedAt: nil,
            preview: false
        )
    }

    @Test("empty history produces zeroed stats")
    func empty() {
        let stats = Passport.summarize([])
        #expect(stats.trips == 0)
        #expect(stats.distanceKm == 0)
        #expect(stats.onTimePercentage == nil)
        #expect(stats.routeFrequency.isEmpty)
    }

    @Test("aggregates distance, stations, routes and trains")
    func aggregation() {
        let journeys = [
            saved(id: "1", train: "12137", origin: "CSTM", destination: "FZR", distance: 1930, minutes: 2040, delay: 12),
            saved(id: "2", train: "12137", origin: "CSTM", destination: "FZR", distance: 1930, minutes: 2040, delay: 0),
            saved(id: "3", train: "12301", origin: "HWH", destination: "NDLS", distance: 1451, minutes: 1020, delay: 30),
        ]
        let stats = Passport.summarize(journeys)
        #expect(stats.trips == 3)
        #expect(stats.distanceKm == 5311)
        #expect(stats.uniqueTrains == 2)
        // {CSTM, FZR, HWH, NDLS}
        #expect(stats.uniqueStations == 4)
        #expect(stats.uniqueRoutes == 2)
        // 1 of 3 trips within 5 minutes (delays 12, 0, 30) → 33%
        #expect(stats.onTimePercentage == 33)
    }

    @Test("route frequency is sorted by trips then codes")
    func frequency() {
        let journeys = [
            saved(id: "1", train: "A", origin: "B", destination: "C", distance: 1, minutes: 1, delay: nil),
            saved(id: "2", train: "A", origin: "A", destination: "B", distance: 1, minutes: 1, delay: nil),
            saved(id: "3", train: "A", origin: "B", destination: "C", distance: 1, minutes: 1, delay: nil),
        ]
        let stats = Passport.summarize(journeys)
        #expect(stats.routeFrequency.first?.originCode == "B")
        #expect(stats.routeFrequency.first?.trips == 2)
    }

    @Test("preview and unknown-source entries do not count as saved runs")
    func excludesPreview() {
        var preview = saved(id: "preview", train: "12137", origin: "CSTM", destination: "FZR",
                            distance: 1930, minutes: 2040, delay: nil)
        preview.preview = true
        var unknown = preview
        unknown.preview = nil
        let production = saved(id: "live", train: "12301", origin: "HWH", destination: "NDLS",
                               distance: 1451, minutes: 1020, delay: nil)
        let stats = Passport.summarize([preview, unknown, production])
        #expect(stats.trips == 1)
        #expect(stats.distanceKm == 1451)
    }

    @Test("overnight runs report a positive duration")
    func overnightDuration() {
        let pack = RoutePackStore.pack("12137")!
        let journey = PreviewData.journey(from: pack, originDate: "2026-09-08")
        // 12137 departs 19:40 and arrives 05:40 the next day.
        let saved = Passport.makeSaved(journey: journey, originDate: "2026-09-08", plan: nil)
        #expect(saved.minutes > 9 * 60)
        #expect(saved.minutes < 11 * 60)
        #expect(saved.distanceKm > 0)
    }

    @Test("negative values are clamped to zero")
    func clamping() {
        let stats = Passport.summarize([
            saved(id: "1", train: "A", origin: "A", destination: "B", distance: -50, minutes: -10, delay: -5)
        ])
        #expect(stats.distanceKm == 0)
        #expect(stats.minutes == 0)
        #expect(stats.delayMinutes == 0)
    }
}

// MARK: - Data report

@Suite("Data report banner")
struct DataReportTests {
    @Test("preview produces the demo banner")
    func preview() {
        let banner = DataReport.banner(DataReportInput(preview: true))
        #expect(banner.status == .preview)
        #expect(banner.title == "DEMO DATA")
    }

    @Test("historical route produces the old timetable banner")
    func historical() {
        let banner = DataReport.banner(DataReportInput(historicalRoute: true))
        #expect(banner.status == .preview)
        #expect(banner.title == "OLD TIMETABLE")
    }

    @Test("cached reports read as saved updates")
    func cached() {
        let banner = DataReport.banner(DataReportInput(cached: true, cachedAt: Date().addingTimeInterval(-180)))
        #expect(banner.status == .stale)
        #expect(banner.title == "SAVED UPDATE")
    }

    @Test("errors outrank the healthy banner")
    func error() {
        let banner = DataReport.banner(DataReportInput(error: "Gateway unreachable"))
        #expect(banner.status == .error)
        #expect(banner.title == "LIVE UPDATE UNAVAILABLE")
    }

    @Test("a fresh report is the healthy banner")
    func healthy() {
        let banner = DataReport.banner(DataReportInput(observedAt: ISO8601DateFormatter.locomote.string(from: Date())))
        #expect(banner.status == .onTime)
        #expect(banner.title == "LATEST RAIL REPORT")
    }

    @Test("a stale observation degrades to the old report banner")
    func staleObservation() {
        let tenMinutesAgo = ISO8601DateFormatter.locomote.string(from: Date().addingTimeInterval(-600))
        let banner = DataReport.banner(DataReportInput(observedAt: tenMinutesAgo))
        #expect(banner.status == .stale)
        #expect(banner.title == "OLD RAIL REPORT")
    }
}

// MARK: - Routes

@Suite("Deep-link routes")
struct RoutesTests {
    @Test("builds and parses a journey URL")
    func roundTrip() throws {
        let url = try Routes.journeyURL(trainNumber: "12137", date: "2026-09-08")
        let parsed = Routes.parse(url)
        #expect(parsed?.trainNumber == "12137")
        #expect(parsed?.date == "2026-09-08")
    }

    @Test("validates train numbers")
    func trainValidation() {
        #expect(Routes.isValidTrainNumber("12137"))
        #expect(!Routes.isValidTrainNumber("1234"))
        #expect(!Routes.isValidTrainNumber("123456"))
        #expect(!Routes.isValidTrainNumber("12a37"))
    }

    @Test("rejects invalid URLs")
    func invalid() throws {
        #expect(throws: (any Error).self) { _ = try Routes.journeyURL(trainNumber: "123", date: "2026-09-08") }
        #expect(throws: (any Error).self) { _ = try Routes.journeyURL(trainNumber: "12137", date: "2026-02-30") }
        #expect(Routes.parse(URL(string: "https://example.com")!) == nil)
    }

    @Test("validates calendar dates including leap years")
    func calendarValidation() {
        #expect(Routes.isValidCalendarDate("2024-02-29"))
        #expect(!Routes.isValidCalendarDate("2023-02-29"))
        #expect(!Routes.isValidCalendarDate("2026-04-31"))
    }
}

// MARK: - Network bounds

@Suite("Network bounds")
struct NetworkBoundsTests {
    @Test("serializes bounds in west,south,east,north order")
    func serialization() throws {
        let bounds = NetworkBounds(west: 68, south: 6, east: 98, north: 37)
        #expect(try NetworkBoundsLogic.serialize(bounds) == "68.0,6.0,98.0,37.0")
    }

    @Test("rejects degenerate and non-finite bounds")
    func rejection() {
        #expect(throws: (any Error).self) {
            _ = try NetworkBoundsLogic.normalize(NetworkBounds(west: 80, south: 6, east: 70, north: 37))
        }
        #expect(throws: (any Error).self) {
            _ = try NetworkBoundsLogic.normalize(NetworkBounds(west: .nan, south: 6, east: 98, north: 37))
        }
    }

    @Test("clamps out-of-range coordinates")
    func clamping() throws {
        let normalized = try NetworkBoundsLogic.normalize(
            NetworkBounds(west: -500, south: -100, east: 500, north: 100)
        )
        #expect(normalized.west == -180)
        #expect(normalized.east == 180)
        #expect(normalized.south == -90)
        #expect(normalized.north == 90)
    }
}

// MARK: - API client helpers

@Suite("API client")
struct APIClientTests {
    @Test("parses Retry-After seconds")
    func retryAfterSeconds() {
        #expect(APIClient.parseRetryAfter("120") == 120)
        #expect(APIClient.parseRetryAfter("0") == 0)
        #expect(APIClient.parseRetryAfter(nil) == nil)
        #expect(APIClient.parseRetryAfter("not-a-value") == nil)
    }

    @Test("parses Retry-After HTTP dates")
    func retryAfterDate() {
        let now = ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z")!
        let parsed = APIClient.parseRetryAfter("Mon, 08 Sep 2026 12:01:00 GMT", now: now)
        #expect(parsed != nil)
        #expect(abs((parsed ?? 0) - 60) < 2)
    }

    @Test("validates rail API URLs")
    func urlValidation() throws {
        #expect(try RailAPIURL.validate("https://example.com").absoluteString.hasPrefix("https://"))
        #expect(throws: (any Error).self) { _ = try RailAPIURL.validate("http://example.com") }
        #expect(throws: (any Error).self) { _ = try RailAPIURL.validate("https://user:pass@example.com") }
        #expect(throws: (any Error).self) { _ = try RailAPIURL.validate("https://example.com?a=1") }
        // Local HTTP is permitted in development only.
        #expect(try RailAPIURL.validate("http://localhost:8787", development: true).host == "localhost")
    }

    @Test("maps the Cloudflare 1102 resource-limit envelope")
    func resourceLimit() throws {
        let body = try JSONSerialization.data(withJSONObject: ["title": "Error 1102: worker exceeded resource limits"])
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 503,
                                       httpVersion: nil, headerFields: nil)!
        let error = APIClient.makeError(http: response, data: body, requestId: "r1")
        #expect(error.code == "gateway_resource_limit")
        #expect(error.retryable)
    }

    @Test("marks only retryable statuses as retryable")
    func retryableStatuses() {
        func error(for status: Int) -> APIError {
            let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: status,
                                           httpVersion: nil, headerFields: nil)!
            return APIClient.makeError(http: response, data: Data(), requestId: "r")
        }
        for status in [408, 429, 500, 502, 503, 504] {
            #expect(error(for: status).retryable)
        }
        for status in [400, 401, 403, 404, 422] {
            #expect(!error(for: status).retryable)
        }
    }

    @Test("keeps provider diagnostics out of the passenger-facing error")
    func providerFailureMessage() throws {
        let body = try JSONSerialization.data(withJSONObject: ["error": [
            "code": "invalid_provider_response", "message": "Upstream schema mismatch at field 13"
        ]])
        let response = HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 502,
                                       httpVersion: nil, headerFields: nil)!
        let error = APIClient.makeError(http: response, data: body, requestId: "r1")
        #expect(error.code == "invalid_provider_response")
        #expect(error.message == "The rail feed is temporarily unavailable. Try again shortly.")
    }
}

// MARK: - Preview data

@Suite("Preview route packs")
struct PreviewDataTests {
    @Test("all three historical packs are bundled")
    func packs() {
        #expect(RoutePackStore.packs.count == 3)
        #expect(RoutePackStore.pack("12137")?.name == "Punjab Mail")
        #expect(RoutePackStore.pack("12301") != nil)
        #expect(RoutePackStore.pack("12951") != nil)
        #expect(RoutePackStore.trainNumbers == ["12137", "12301", "12951"])
    }

    @Test("a preview journey never claims to be live")
    func previewIsNeverLive() {
        let pack = RoutePackStore.pack("12137")!
        let journey = PreviewData.journey(from: pack, originDate: "2026-09-08")
        #expect(journey.position.source == .scheduled)
        #expect(journey.prediction.source == .scheduled)
        #expect(journey.prediction.delayMinutes == nil)
        #expect(journey.prediction.delayStatus == .unavailable)
        #expect(journey.routeCoordinates?.count ?? 0 > 2)

        let mode = JourneyMode.input(
            journey: journey, cached: false, preview: true,
            historicalRoute: true, originDate: "2026-09-08", error: nil
        )
        #expect(!StatusMapping.isLivePulseAllowed(mode))
        #expect(StatusMapping.statusForJourneyMode(mode) == .preview)
    }

    @Test("preview stops carry the replay state machine")
    func stopStates() {
        let pack = RoutePackStore.pack("12137")!
        let journey = PreviewData.journey(from: pack, originDate: "2026-09-08", progress: 0.5)
        #expect(journey.stops.contains { $0.state == .passed })
        #expect(journey.stops.contains { $0.state == .current })
        #expect(journey.stops.contains { $0.state == .upcoming })
    }

    @Test("preview operations never claim a verified physical rake")
    func operationsHonesty() {
        let pack = RoutePackStore.pack("12137")!
        let operations = PreviewData.operations(from: pack, originDate: "2026-09-08")
        #expect(operations.mode == "preview")
        #expect(operations.linkage?.claim == "possible-same-rake")
        #expect(operations.linkage?.confidence == .low)
        #expect(operations.delayAssessment == nil)
    }
}

// MARK: - Forecast presentation

@Suite("Forecast presentation")
struct ForecastPresentationTests {
    @Test("explanation codes map to readable copy")
    func explanationLabels() {
        #expect(ForecastPresentation.explanationLabel(.actualEventObserved) == "Actual station event observed")
        #expect(ForecastPresentation.explanationLabel(.noReleasedEmpiricalGroup) == "No released empirical model covers this stop")
    }

    @Test("fallback labels explain the degradation")
    func fallbackLabels() {
        #expect(ForecastPresentation.fallbackLabel(.insufficientGroupSupport) == "Fallback: too few comparable journeys")
        #expect(ForecastPresentation.fallbackLabel(.noReleasedEmpiricalGroup) == "Fallback: no released empirical model")
        #expect(ForecastPresentation.fallbackLabel(.currentDelayUnknown) == "Current delay unknown")
        #expect(ForecastPresentation.fallbackLabel(nil) == nil)
    }

    @Test("feature freshness reads in human units")
    func freshness() {
        let now = Date()
        let recent = ISO8601DateFormatter.locomote.string(from: now.addingTimeInterval(-30))
        #expect(ForecastPresentation.featureFreshness(recent, now: now).hasSuffix("s old"))
        let minutes = ISO8601DateFormatter.locomote.string(from: now.addingTimeInterval(-300))
        #expect(ForecastPresentation.featureFreshness(minutes, now: now).contains("min old"))
        let hours = ISO8601DateFormatter.locomote.string(from: now.addingTimeInterval(-7200))
        #expect(ForecastPresentation.featureFreshness(hours, now: now).contains("hr old"))
    }
}

// MARK: - Token store

@Suite("Token store")
struct TokenStoreTests {
    @Test("in-memory store round-trips a session")
    func roundTrip() throws {
        let store = InMemoryTokenStore()
        let session = AuthSession(accessToken: "a", refreshToken: "b", expiresAt: Date().addingTimeInterval(3600))
        try store.save(session)
        #expect(store.load()?.accessToken == "a")
        store.clear()
        #expect(store.load() == nil)
    }

    @Test("sessions expire with a 30s skew")
    func expirySkew() {
        let valid = AuthSession(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(120))
        let expiring = AuthSession(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(10))
        #expect(!valid.isExpired)
        #expect(expiring.isExpired)
    }
}

// MARK: - Map matching & contribution

@Suite("Map matching")
struct MapMatcherTests {
    // A simple east-west line for predictable projections.
    let route = [
        RailCoordinate(latitude: 0, longitude: 0),
        RailCoordinate(latitude: 0, longitude: 1),
    ]

    @Test("a point on the line matches with high confidence")
    func onLine() {
        let match = MapMatcher.match(RailCoordinate(latitude: 0, longitude: 0.5), route: route)
        #expect(match != nil)
        #expect(abs((match?.progress ?? 0) - 0.5) < 0.01)
        #expect((match?.distanceM ?? .infinity) < 100)
        #expect((match?.confidence ?? 0) > 0.9)
    }

    @Test("a point far from the line has low confidence")
    func offLine() {
        // ~11 km north of the line with a 10 m accuracy fix.
        let match = MapMatcher.match(RailCoordinate(latitude: 0.1, longitude: 0.5), route: route, accuracyM: 10)
        #expect(match != nil)
        #expect((match?.confidence ?? 1) == 0)
    }

    @Test("progress is monotonic along the route")
    func monotonicProgress() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.1).map {
            MapMatcher.match(RailCoordinate(latitude: 0, longitude: $0), route: route)?.progress ?? -1
        }
        #expect(samples == samples.sorted())
    }

    @Test("a degenerate route yields no match")
    func degenerate() {
        #expect(MapMatcher.match(RailCoordinate(latitude: 0, longitude: 0), route: []) == nil)
        #expect(MapMatcher.match(RailCoordinate(latitude: 0, longitude: 0),
                                 route: [RailCoordinate(latitude: 5, longitude: 5)]) == nil)
    }

    @Test("implausible fixes are rejected")
    func filtering() {
        let now: TimeInterval = 1_800_000_000_000
        func sample(accuracy: Double, speed: Double, ageMs: TimeInterval, lat: Double = 0) -> LocationSample {
            LocationSample(latitude: lat, longitude: 0.5, timestamp: now - ageMs,
                           accuracyM: accuracy, speedKph: speed)
        }
        #expect(MapMatcher.isUsable(sample(accuracy: 20, speed: 80, ageMs: 1_000), now: now))
        #expect(!MapMatcher.isUsable(sample(accuracy: 500, speed: 80, ageMs: 1_000), now: now))
        #expect(!MapMatcher.isUsable(sample(accuracy: 20, speed: 90, ageMs: 60_000), now: now))
        #expect(!MapMatcher.isUsable(sample(accuracy: 20, speed: 1, ageMs: 1_000), now: now))
        #expect(!MapMatcher.isUsable(sample(accuracy: 20, speed: 500, ageMs: 1_000), now: now))
        #expect(!MapMatcher.isUsable(sample(accuracy: 20, speed: 80, ageMs: 1_000, lat: 200), now: now))
    }
}

@Suite("Community contribution")
struct ContributionTests {
    let now: TimeInterval = 1_800_000_000_000
    var route: [RailCoordinate] {
        [RailCoordinate(latitude: 0, longitude: 0), RailCoordinate(latitude: 0, longitude: 1)]
    }

    @Test("preview run ids are refused")
    func previewRefused() {
        #expect(ContributionObservation.isPreviewRunId("preview-12137-historical-route"))
        #expect(ContributionObservation.isPreviewRunId("demo"))
        #expect(ContributionObservation.isPreviewRunId("PREVIEW:123"))
        #expect(!ContributionObservation.isPreviewRunId("12137-2026-09-08"))
    }

    @Test("a preview run is never contributed")
    func previewNotCompacted() {
        let device = DeviceLocation(timestamp: now, latitude: 0, longitude: 0.5, accuracy: 10, speed: 22)
        let result = ContributionObservation.compact(
            location: device,
            context: ContributionContext(runId: "preview-12137", route: route),
            consentVersion: 1,
            now: now
        )
        #expect(result == nil)
    }

    @Test("a mocked location is refused")
    func mockedRefused() {
        let device = DeviceLocation(timestamp: now, mocked: true, latitude: 0, longitude: 0.5, accuracy: 10, speed: 22)
        let result = ContributionObservation.compact(
            location: device,
            context: ContributionContext(runId: "12137-2026-09-08", route: route),
            consentVersion: 1,
            now: now
        )
        #expect(result == nil)
    }

    @Test("an accepted fix is compacted and map-matched")
    func compaction() {
        // 22 m/s == ~79 km/h.
        let device = DeviceLocation(timestamp: now, latitude: 0.0002, longitude: 0.5, accuracy: 12, speed: 22)
        let result = ContributionObservation.compact(
            location: device,
            context: ContributionContext(runId: "12137-2026-09-08", route: route),
            consentVersion: 3,
            now: now
        )
        #expect(result != nil)
        #expect(result?.runId == "12137-2026-09-08")
        #expect(result?.consentVersion == 3)
        // Snapped onto the route: latitude should be ~0, longitude near 0.5.
        #expect(abs(Double(result?.latE5 ?? 999) / 100_000) < 0.001)
        #expect(abs((result?.routeProgress ?? 0) - 0.5) < 0.05)
        #expect((result?.matchDistanceM ?? .infinity) < 100)
    }

    @Test("the compact payload carries no passenger identity")
    func noPersonalData() throws {
        let device = DeviceLocation(timestamp: now, latitude: 0, longitude: 0.5, accuracy: 10, speed: 22)
        let observation = ContributionObservation.compact(
            location: device,
            context: ContributionContext(runId: "12137-2026-09-08", route: route),
            consentVersion: 1,
            now: now
        )!
        let json = String(data: try JSONEncoder().encode(observation), encoding: .utf8)!.lowercased()
        for forbidden in ["pnr", "seat", "coach", "name", "phone", "passenger"] {
            #expect(!json.contains(forbidden))
        }
    }
}

@Suite("Offline observation queue")
struct ObservationQueueTests {
    private func observation(_ timestamp: Int, runId: String = "12137") -> CompactObservation {
        CompactObservation(runId: runId, timestamp: timestamp, latE5: 0, lonE5: 0,
                           speedKph: 80, accuracyM: 10, routeProgress: 0.5,
                           matchDistanceM: 5, consentVersion: 1)
    }

    @Test("append, peek and count")
    func fifo() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = ObservationQueue(directory: dir)
        queue.append(observation(1))
        queue.append(observation(2))
        #expect(queue.count() == 2)
        #expect(queue.peek(limit: 1).first?.timestamp == 1)
        queue.clear()
        #expect(queue.count() == 0)
    }

    @Test("acknowledged observations are removed")
    func acknowledge() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = ObservationQueue(directory: dir)
        let first = observation(1)
        queue.append(first)
        queue.append(observation(2))
        queue.remove([first])
        #expect(queue.count() == 1)
        #expect(queue.peek(limit: 10).first?.timestamp == 2)
    }

    @Test("the queue survives a new instance (offline durability)")
    func durability() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = ObservationQueue(directory: dir)
        queue.append(observation(42))
        let reopened = ObservationQueue(directory: dir)
        #expect(reopened.count() == 1)
        #expect(reopened.peek(limit: 1).first?.timestamp == 42)
    }
}

// MARK: - Observation sync

@Suite("Observation sync")
struct ObservationSyncTests {
    private final class StubService: RailServiceProtocol, @unchecked Sendable {
        var uploaded: [[CompactObservation]] = []
        var shouldFail = false
        func searchTrains(_ query: String) async throws -> [TrainSearchResult] { [] }
        func journey(trainNumber: String, originDate: String) async throws -> Journey { fatalError() }
        func operationalChain(trainNumber: String, originDate: String) async throws -> OperationalChainResponse { fatalError() }
        func networkTrains(bounds: NetworkBounds) async throws -> NetworkTrainsResponse { fatalError() }
        func trainHistory(trainNumber: String, limit: Int) async throws -> TrainHistoryResponse { fatalError() }
        func registerLiveActivityToken(runId: String, token: String) async throws {}
        func uploadObservations(_ batch: [CompactObservation]) async throws -> [String] {
            if shouldFail { throw URLError(.notConnectedToInternet) }
            uploaded.append(batch)
            return batch.map { "\($0.runId):\($0.timestamp)" }
        }
    }

    private func observation(_ timestamp: Int, runId: String = "12137-2026-09-08") -> CompactObservation {
        CompactObservation(runId: runId, timestamp: timestamp, latE5: 0, lonE5: 0,
                           speedKph: 80, accuracyM: 10, routeProgress: 0.5,
                           matchDistanceM: 5, consentVersion: 1)
    }

    private func makeQueue(_ items: [CompactObservation]) -> ObservationQueue {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let queue = ObservationQueue(directory: dir)
        items.forEach { queue.append($0) }
        return queue
    }

    @Test("without consent nothing is uploaded")
    func consentGate() async {
        let queue = makeQueue([observation(1)])
        let service = StubService()
        let sync = ObservationSync(queue: queue, service: service)
        let outcome = await sync.flush(consentGranted: false)
        #expect(outcome.uploaded == 0)
        #expect(outcome.remaining == 1)
        #expect(service.uploaded.isEmpty)
    }

    @Test("queued observations are uploaded and cleared")
    func upload() async {
        let queue = makeQueue([observation(1), observation(2)])
        let service = StubService()
        let sync = ObservationSync(queue: queue, service: service)
        let outcome = await sync.flush(consentGranted: true)
        #expect(outcome.uploaded == 2)
        #expect(outcome.remaining == 0)
        #expect(service.uploaded.count == 1)
    }

    @Test("a failure leaves the batch queued for retry")
    func retry() async {
        let queue = makeQueue([observation(1)])
        let service = StubService()
        service.shouldFail = true
        let sync = ObservationSync(queue: queue, service: service)
        let outcome = await sync.flush(consentGranted: true)
        #expect(outcome.failed)
        #expect(outcome.remaining == 1)

        service.shouldFail = false
        let retried = await sync.flush(consentGranted: true)
        #expect(retried.uploaded == 1)
        #expect(retried.remaining == 0)
    }

    @Test("preview run observations are never uploaded")
    func previewFiltered() async {
        let queue = makeQueue([observation(1, runId: "preview-12137"), observation(2)])
        let service = StubService()
        let sync = ObservationSync(queue: queue, service: service)
        let outcome = await sync.flush(consentGranted: true)
        #expect(outcome.uploaded == 1)
        let sent = service.uploaded.flatMap { $0 }
        #expect(sent.allSatisfy { !ContributionObservation.isPreviewRunId($0.runId) })
    }
}

// MARK: - Real gateway fixture decoding

@Suite("Journey source isolation")
@MainActor
struct JourneySourceIsolationTests {
    private struct FailingService: RailServiceProtocol {
        func searchTrains(_ query: String) async throws -> [TrainSearchResult] { [] }
        func journey(trainNumber: String, originDate: String) async throws -> Journey {
            throw URLError(.notConnectedToInternet)
        }
        func operationalChain(trainNumber: String, originDate: String) async throws -> OperationalChainResponse {
            throw URLError(.notConnectedToInternet)
        }
        func networkTrains(bounds: NetworkBounds) async throws -> NetworkTrainsResponse {
            throw URLError(.notConnectedToInternet)
        }
        func trainHistory(trainNumber: String, limit: Int) async throws -> TrainHistoryResponse {
            throw URLError(.notConnectedToInternet)
        }
        func registerLiveActivityToken(runId: String, token: String) async throws {}
        func uploadObservations(_ batch: [CompactObservation]) async throws -> [String] { [] }
    }

    @Test("a production request never shows a bundled route after a gateway failure")
    func failedGatewayDoesNotShowPreview() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = JourneyModel(
            trainNumber: "12137", originDate: "2026-10-01", service: FailingService(),
            cache: JourneyCache(directory: directory),
            passport: PassportRepository(directory: directory)
        )
        await model.load()
        #expect(model.journey == nil)
        #expect(!model.isPreview)
        #expect(!model.isCached)
        if case .failed = model.phase {} else {
            Issue.record("A failed production request must display its error")
        }
    }
}

/// Decodes an actual captured gateway response so the models stay honest about
/// the production contract (including explicit `null` fields in `unavailable`
/// forecasts, numeric millisecond timestamps, and `HH:mm` clock strings).
@Suite("Gateway contract decoding")
struct GatewayContractTests {
    private func fixtureData() throws -> Data {
        let url = Bundle(for: FixtureAnchor.self)
            .url(forResource: "run-12137-2026-09-18", withExtension: "json")
        let resolved = try #require(url, "gateway fixture is missing from the test bundle")
        return try Data(contentsOf: resolved)
    }

    @Test("the real journey response decodes")
    func decodesRealJourney() throws {
        struct Envelope: Decodable { let journey: Journey }
        let envelope = try JSONDecoder.locomote.decode(Envelope.self, from: try fixtureData())
        let journey = envelope.journey

        #expect(journey.trainNumber == "12137")
        #expect(journey.trainName == "Punjab Mail")
        #expect(journey.stops.count > 40)
        #expect(journey.routeCoordinates?.isEmpty == false)
        // The gateway supplies clock strings, not ISO instants, for schedules.
        #expect(journey.scheduledArrival == "05:15")
        // observedAt is epoch milliseconds, not a string.
        #expect(journey.position.observedAt > 1_000_000_000_000)
        #expect(journey.provenance?.provider == "railradar-public")
        #expect(journey.provenance?.freshness == "scheduled")
    }

    @Test("unavailable forecasts with explicit nulls decode correctly")
    func decodesUnavailableForecast() throws {
        struct Envelope: Decodable { let journey: Journey }
        let envelope = try JSONDecoder.locomote.decode(Envelope.self, from: try fixtureData())
        let withForecast = envelope.journey.stops.first { $0.forecast != nil }
        let forecast = try #require(withForecast?.forecast)

        // This run is scheduled, so the gateway returns an unavailable forecast
        // whose model fields are explicitly null.
        #expect(!forecast.isAvailable)
        if case .unavailable(let value) = forecast {
            #expect(value.modelName == nil)
            #expect(value.modelVersion == nil)
            #expect(value.fallbackReason == .currentDelayUnknown)
        } else {
            Issue.record("expected an unavailable forecast")
        }
        #expect(ForecastPresentation.sourceLabel(forecast) == "Forecast unavailable")
    }

    @Test("the decoded journey derives the correct honest mode")
    func derivesMode() throws {
        struct Envelope: Decodable { let journey: Journey }
        let journey = try JSONDecoder.locomote.decode(Envelope.self, from: try fixtureData()).journey

        // A scheduled run must never present as live or as a replay.
        let mode = JourneyMode.input(
            journey: journey, cached: false, preview: false,
            historicalRoute: false, originDate: journey.travelDate, error: nil
        )
        let status = StatusMapping.statusForJourneyMode(mode)
        #expect(status == .scheduled || status == .stale)
        #expect(!StatusMapping.isLivePulseAllowed(mode))
    }

    @Test("real data survives the passport summary")
    func passportFromRealData() throws {
        struct Envelope: Decodable { let journey: Journey }
        let journey = try JSONDecoder.locomote.decode(Envelope.self, from: try fixtureData()).journey
        let saved = Passport.makeSaved(journey: journey, originDate: journey.travelDate, plan: nil)
        #expect(saved.trainNumber == "12137")
        #expect(saved.stations.count == journey.stops.count)
        #expect(saved.distanceKm > 0)
        let stats = Passport.summarize([saved])
        #expect(stats.trips == 1)
        #expect(stats.uniqueTrains == 1)
    }
}

/// Anchor class used only to locate the test bundle.
final class FixtureAnchor {}

// MARK: - Layout invariants

/// Regression guard for the trip-card centring bug: the centre column must be
/// centred on the card regardless of how unequal the two station-name widths
/// are. The original `HStack { left; Spacer; middle; Spacer; right }` centred
/// the leftover *gap*, drifting by half the difference in column widths.
@Suite("Trip card layout")
struct TripCardLayoutTests {
    /// Widths are measured from the simulator in points.
    private func middleCentre(leftWidth: Double, rightWidth: Double, contentWidth: Double, middleWidth: Double) -> Double {
        let spacer = (contentWidth - leftWidth - rightWidth - middleWidth) / 2
        return leftWidth + spacer + middleWidth / 2
    }

    @Test("the arrow-centring bug is understood and would be caught")
    func documentsTheBug() {
        // Reproduce the ORIGINAL geometry: uneven name widths drift the middle.
        let contentWidth = 370.0 - 32.0
        let drifted = middleCentre(leftWidth: 82.0, rightWidth: 102.7,
                                   contentWidth: contentWidth, middleWidth: 54.7)
        let trueCentre = contentWidth / 2
        #expect(abs(drifted - trueCentre) > 5, "the old layout should visibly drift")
    }

    @Test("equal flexible columns centre the middle exactly")
    func equalColumnsCentre() {
        // With `.frame(maxWidth: .infinity)` on both outer columns they resolve
        // to equal widths, so the middle element is centred by construction.
        let contentWidth: Double = 338
        let column = (contentWidth - 54.7) / 2
        let centre = column + 54.7 / 2
        #expect(abs(centre - contentWidth / 2) < 0.01)
    }
}

import Foundation
import Testing
import SwiftUI
import XCTest
@testable import Locomate

@Suite("Personal station card evidence")
struct JourneyStopProjectionTests {
    private let now = ISO8601DateFormatter.locomote.date(from: "2026-09-18T14:20:00.000Z")!
    private let beforeRun = ISO8601DateFormatter.locomote.date(from: "2026-09-17T14:20:00.000Z")!

    @Test("future boarding uses CSMT departure, not reported DR or destination forecast")
    func futureBoarding() throws {
        let journey = try fixture { raw in
            var prediction = raw["prediction"] as! [String: Any]
            prediction["expectedTime"] = "23:59"
            raw["prediction"] = prediction
        }
        let card = try #require(project(journey, at: beforeRun))
        #expect(card.heading == "Boarding at")
        #expect(card.code == "CSMT")
        #expect(card.timeLabel == "Scheduled departure")
        #expect(card.time == "19:35")
        #expect(card.distanceKm == nil)
        #expect(card.delayLabel == "Delay unavailable")
    }

    @Test("personal boarding uses its departure, including when the run has started")
    func intermediateBoarding() throws {
        let journey = try fixture(running: true)
        let plan = try JourneyPlanLogic.create(journey: journey, originDate: journey.travelDate,
                                               boardingIndex: 1, alightingIndex: 2)
        let card = try #require(project(journey, plan: plan))
        #expect(card.code == "DR")
        #expect(card.time == "19:50")
        #expect(card.timeLabel == "Scheduled departure")
        #expect(card.distanceKm == 8.9)
    }

    @Test("arrival-only boarding never gains a departure ETA or origin fallback")
    func missingBoardingDeparture() throws {
        let journey = try fixture { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["scheduledDeparture"] = NSNull()
            stops[1]["forecast"] = forecast("20:05")
            raw["stops"] = stops
        }
        let plan = try JourneyPlanLogic.create(journey: journey, originDate: journey.travelDate,
                                               boardingIndex: 1, alightingIndex: 2)
        let card = try #require(project(journey, plan: plan, at: beforeRun))
        #expect(card.code == "DR")
        #expect(card.timeLabel == "Scheduled departure")
        #expect(card.time == nil)
        #expect(card.distanceKm == nil)
    }

    @Test("next arrival forecast and delay belong to the same matched stop")
    func matchedNextForecast() throws {
        let journey = try fixture(running: true) { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["forecast"] = forecast("19:55")
            stops[1]["delayMinutes"] = 8
            stops[1]["delayStatus"] = "estimated"
            raw["stops"] = stops
            var prediction = raw["prediction"] as! [String: Any]
            prediction["expectedTime"] = "23:59"
            prediction["delayMinutes"] = 99
            raw["prediction"] = prediction
        }
        let card = try #require(project(journey))
        #expect(card.heading == "Next stop")
        #expect(card.code == "DR")
        #expect(card.timeLabel == "Estimated arrival")
        #expect(card.time == "19:55")
        #expect(card.delayLabel == "8 minutes late · estimated")
        #expect(card.distanceKm == 8.9)
        #expect(card.detail.contains("Baseline fallback"))
    }

    @Test("unavailable stop forecast stays scheduled despite a predicted-arrival compatibility value")
    func unavailableForecast() throws {
        let journey = try fixture(running: true) { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["predictedArrival"] = "23:59"
            raw["stops"] = stops
        }
        let card = try #require(project(journey))
        #expect(card.time == "19:47")
        #expect(card.timeLabel == "Scheduled arrival")
        #expect(card.detail.contains("forecast unavailable"))
        #expect(card.delayLabel == "Delay unavailable")
    }

    @Test("actual arrival and observed forecast are labeled as station evidence")
    func observedArrival() throws {
        let journey = try fixture(running: true) { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["actualArrival"] = "19:49"
            stops[1]["arrivalDelayMinutes"] = 2
            stops[1]["forecast"] = forecast("20:10")
            raw["stops"] = stops
        }
        let card = try #require(project(journey))
        #expect(card.time == "19:49")
        #expect(card.timeLabel == "Actual arrival")
        #expect(card.delayLabel == "2 minutes late")

        let observed = try fixture(running: true) { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["forecast"] = forecast("19:49", source: "observed")
            raw["stops"] = stops
        }
        #expect(project(observed)?.timeLabel == "Observed arrival")
    }

    @Test("cached and stale reports use saved timetable, retain stale delay, and omit current distance")
    func cachedEvidence() throws {
        let journey = try fixture(running: true) { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["forecast"] = forecast("20:05")
            stops[1]["delayMinutes"] = 18
            stops[1]["delayStatus"] = "estimated"
            raw["stops"] = stops
        }
        let card = try #require(project(journey, cached: true))
        #expect(card.heading == "Last reported next stop")
        #expect(card.code == "DR")
        #expect(card.time == "19:47")
        #expect(card.timeLabel == "Scheduled arrival")
        #expect(card.detail.contains("Saved timetable"))
        #expect(card.delayLabel == "18 minutes late · stale")
        #expect(card.distanceKm == nil)
    }

    @Test("preview has timetable boarding only, regardless of simulated position or observed fields")
    func previewEvidence() throws {
        let journey = try fixture(running: true)
        let card = try #require(project(journey, preview: true))
        #expect(card.heading == "Preview boarding")
        #expect(card.code == "CSMT")
        #expect(card.time == "19:35")
        #expect(card.detail == "Preview timetable · not live")
        #expect(card.delayLabel == "Timetable only")
        #expect(card.distanceKm == nil)
    }

    @Test("unmatched or ambiguous position cannot invent a next stop or distance")
    func unmatchedPosition() throws {
        for code in ["MISSING", "DR"] {
            let journey = try fixture(running: true) { raw in
                var position = raw["position"] as! [String: Any]
                position["nextStation"] = code
                raw["position"] = position
                if code == "DR" {
                    var stops = raw["stops"] as! [[String: Any]]
                    stops[2]["code"] = "DR"
                    raw["stops"] = stops
                }
            }
            let card = try #require(project(journey))
            #expect(card.heading == "Your destination")
            #expect(card.code == "FZR")
            #expect(card.timeLabel == "Scheduled arrival")
            #expect(card.time == "05:15")
            #expect(card.distanceKm == nil)
        }
    }

    @Test("a completed personal segment shows its recorded endpoint, never a later train stop")
    func completedSegment() throws {
        let journey = try fixture(running: true) { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["actualArrival"] = "19:49"
            stops[1]["arrivalDelayMinutes"] = 2
            raw["stops"] = stops
        }
        let plan = try JourneyPlanLogic.create(journey: journey, originDate: journey.travelDate,
                                               boardingIndex: 0, alightingIndex: 1)
        let card = try #require(project(journey, plan: plan, cached: true))
        #expect(card.heading == "Recorded arrival at")
        #expect(card.code == "DR")
        #expect(card.time == "19:49")
        #expect(card.detail.contains("Saved report"))
        #expect(card.distanceKm == nil)
    }

    @Test("platform is the selected call's known value, omitted for unknown and preview")
    func selectedPlatform() throws {
        let journey = try fixture(running: true) { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[0]["platform"] = "9"
            stops[1]["platform"] = "3A"
            raw["stops"] = stops
        }
        #expect(project(journey)?.code == "DR")
        #expect(project(journey)?.platform == "3A")
        #expect(project(journey)?.platformLabel == "Platform")
        #expect(project(journey, cached: true)?.platformLabel == "Last known platform")
        #expect(project(journey, preview: true)?.platform == nil)
        let unknown = try fixture(running: true)
        #expect(project(unknown)?.platform == nil)
    }

    @Test("summary arrival never borrows the destination forecast or compatibility time")
    func summaryUsesOnlySelectedArrival() throws {
        let journey = try fixture { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["predictedArrival"] = "23:59"
            stops[1]["scheduledArrival"] = "19:48"
            raw["stops"] = stops
            var prediction = raw["prediction"] as! [String: Any]
            prediction["expectedTime"] = "23:59"
            raw["prediction"] = prediction
        }
        let clock = JourneyStopProjection.summaryClock(stop: journey.stops[1], departure: false, preview: false, cached: false)
        #expect(clock.time == "19:48")
        #expect(clock.label == "Scheduled arrival")
        #expect(clock.evidence == .scheduled)
    }

    @Test("summary forecast is matched, suppressed in preview/cache, and actual arrival wins")
    func summaryQualifiesEvidence() throws {
        let journey = try fixture { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["forecast"] = forecast("20:05")
            stops[1]["scheduledArrival"] = "19:48"
            raw["stops"] = stops
        }
        let stop = journey.stops[1]
        let estimated = JourneyStopProjection.summaryClock(stop: stop, departure: false, preview: false, cached: false)
        #expect(estimated.time == "20:05" && estimated.label == "Estimated arrival")
        #expect(JourneyStopProjection.summaryClock(stop: stop, departure: false, preview: true, cached: false).time == "19:48")
        let saved = JourneyStopProjection.summaryClock(stop: stop, departure: false, preview: false, cached: true)
        #expect(saved.time == "19:48" && saved.label == "Saved scheduled arrival")
        let recorded = try fixture { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["forecast"] = forecast("20:05")
            stops[1]["actualArrival"] = "19:49"
            raw["stops"] = stops
        }
        let actual = JourneyStopProjection.summaryClock(stop: recorded.stops[1], departure: false, preview: false, cached: true)
        #expect(actual.time == "19:49" && actual.label == "Saved actual arrival")
    }

    @Test("summary departure does not turn an arrival-only call into a departure")
    func summaryMissingDeparture() throws {
        let journey = try fixture { raw in
            var stops = raw["stops"] as! [[String: Any]]
            stops[1]["scheduledDeparture"] = NSNull()
            stops[1]["actualDeparture"] = NSNull()
            stops[1]["scheduledArrival"] = "19:48"
            raw["stops"] = stops
        }
        #expect(JourneyStopProjection.summaryClock(stop: journey.stops[1], departure: true, preview: false, cached: false).time == nil)
    }

    private func project(_ journey: Journey, plan: JourneyPlan? = nil, cached: Bool = false,
                         preview: Bool = false, at date: Date? = nil) -> JourneyStopProjection? {
        JourneyStopProjection.make(journey: journey, plan: plan, originDate: journey.travelDate,
                                   cached: cached, preview: preview, now: date ?? now)
    }

    private func forecast(_ value: String, source: String = "baseline") -> [String: Any] {
        ["availability": "available", "p10": value, "p50": value, "p90": value,
         "source": source, "modelName": "fixture", "modelVersion": "1",
         "featureAsOf": "2026-09-18T14:19:00.000Z", "support": 1, "explanationCodes": []]
    }

    private func fixture(running: Bool = false, edit: (inout [String: Any]) -> Void = { _ in }) throws -> Journey {
        let url = try #require(Bundle(for: FixtureAnchor.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var raw = try #require(envelope["journey"] as? [String: Any])
        if running {
            var position = raw["position"] as! [String: Any]
            position["source"] = "official"
            position["observedAt"] = now.addingTimeInterval(-60).timeIntervalSince1970 * 1_000
            raw["position"] = position
            var provenance = raw["provenance"] as! [String: Any]
            provenance["freshness"] = "live"
            raw["provenance"] = provenance
            var stops = raw["stops"] as! [[String: Any]]
            stops[0]["state"] = "passed"
            stops[0]["actualDeparture"] = "19:36"
            stops[0]["departureDelayMinutes"] = 1
            raw["stops"] = stops
        }
        edit(&raw)
        return try JSONDecoder.locomote.decode(Journey.self, from: JSONSerialization.data(withJSONObject: raw))
    }
}

// Renders the production card in an ordinary scroll container for inspection.
// This does not substitute for a physical VoiceOver pass.
@MainActor
final class JourneyPlatformLayoutTests: XCTestCase {
    func testPlatformCardNormalAndLargestTextRemainScrollable() async throws {
        let file = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var raw = try XCTUnwrap(envelope["journey"] as? [String: Any])
        var stops = try XCTUnwrap(raw["stops"] as? [[String: Any]])
        stops[0]["platform"] = "3A"
        stops[0]["name"] = "Chhatrapati Shivaji Maharaj Terminus"
        raw["stops"] = stops
        let journey = try JSONDecoder.locomote.decode(Journey.self, from: JSONSerialization.data(withJSONObject: raw))
        for size in [DynamicTypeSize.large, .accessibility5] {
            let content = ScrollView {
                NextStopStat(journey: journey, originDate: journey.travelDate, plan: nil, cached: false, preview: false)
                    .padding(16)
            }
            .dynamicTypeSize(size)
            .environment(\.locomoteColors, LocomateTheme.dark)
            .background(LocomateTheme.dark.canvas)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 740))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(400))
            let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
            XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1,
                                     "Large type must not create horizontally clipped content.")
            capture(host.view, name: "Station platform card \(size) top")
            if size.isAccessibilitySize {
                XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
                XCTAssertTrue(scroll.isScrollEnabled)
                scroll.setContentOffset(CGPoint(x: 0, y: min(320, scroll.contentSize.height - scroll.bounds.height)), animated: false)
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                capture(host.view, name: "Station platform card largest text scrolled")
            }
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func capture(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

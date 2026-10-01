import Foundation
import Testing
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

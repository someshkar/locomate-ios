import Foundation
import Testing
@testable import Locomate

private final class ActivityFixtureAnchor: NSObject {}
@Suite("Station-specific Live Activity timing")
struct LiveActivityProjectionTests {
    private let now = ISO8601DateFormatter().date(from: "2026-08-24T18:45:00Z")!
    private func journey(change: ([String: Any]) -> [String: Any] = { $0 }) throws -> Journey {
        let bundle = Bundle(for: ActivityFixtureAnchor.self)
        let url = try #require(bundle.url(forResource: "journey-valid", withExtension: "json"))
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var journey = try #require(envelope["journey"] as? [String: Any])
        var prediction = try #require(journey["prediction"] as? [String: Any])
        prediction["delayStatus"] = "observed"
        journey["prediction"] = prediction
        return try JSONDecoder.locomote.decode(Journey.self, from: JSONSerialization.data(withJSONObject: change(journey)))
    }
    @Test("next call scheduled arrival never borrows the destination prediction")
    func scheduled() throws {
        let state = try #require(LiveActivityProjection.state(journey: journey(), now: now))
        #expect(state.nextStation == "BBB")
        #expect(state.eta == "00:10")
        #expect(state.etaLabel == "Scheduled arrival")
        #expect(state.updatedAt == now.addingTimeInterval(-30))
    }
    @Test("a station forecast retains its own estimated source and fractional delay")
    func estimated() throws {
        let value = try journey { source in
            var result = source
            var prediction = result["prediction"] as! [String: Any]
            prediction["delayMinutes"] = 2.5
            result["prediction"] = prediction
            var stops = result["stops"] as! [[String: Any]]
            stops[1]["forecast"] = ["availability": "available", "p10": "00:15", "p50": "00:20", "p90": "00:25", "source": "baseline", "modelName": "current-delay", "modelVersion": "1", "featureAsOf": "2026-08-24T18:45:00Z", "support": 1, "explanationCodes": []]
            result["stops"] = stops
            return result
        }
        let state = try #require(LiveActivityProjection.state(journey: value, now: now))
        #expect(state.eta == "00:20" && state.etaLabel == "Estimated arrival")
        #expect(state.delayMinutes == 2.5)
        #expect(state.delayLabel == "2.5 minutes late")
    }
    @Test("ambiguous next calls and expired evidence cannot create a misleading card")
    func unavailable() throws {
        let duplicated = try journey { source in
            var result = source
            var stops = result["stops"] as! [[String: Any]]
            stops.append(stops[1]); result["stops"] = stops
            return result
        }
        #expect(LiveActivityProjection.state(journey: duplicated, now: now) == nil)
        let old = try journey { source in
            var result = source
            var prediction = result["prediction"] as! [String: Any]
            prediction["updatedSecondsAgo"] = 601; result["prediction"] = prediction
            return result
        }
        #expect(LiveActivityProjection.state(journey: old, now: now) == nil)
    }
    @Test("older content states decode with an explicit generic arrival label")
    func legacyState() throws {
        let legacy = Data(#"{"nextStation":"BBB","eta":"00:20","delayMinutes":2,"delayLabel":"2 minutes late","distanceToNextKm":10,"confidence":"HIGH","updatedAt":0}"#.utf8)
        #expect(try JSONDecoder().decode(JourneyActivityAttributes.ContentState.self, from: legacy).etaLabel == nil)
    }
}

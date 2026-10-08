import Foundation
import Testing
@testable import Locomate
private final class RegressionFixtureAnchor: NSObject {}
import SwiftUI
import MapKit

private final class RegressionIdentityProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let status: Int
        let payload: Data
        if path == "/v1/auth/device-session" {
            status = 200
            payload = Data(#"{"accessToken":"audit-local","expiresIn":3600}"#.utf8)
        } else if path.hasSuffix("/rake-working") {
            status = 404
            payload = Data(#"{"error":{"code":"unavailable","message":"No rotation evidence","retryable":false}}"#.utf8)
        } else {
            status = 200
            let fixture = Bundle(for: RegressionFixtureAnchor.self).url(forResource: "run-12137-2026-09-18", withExtension: "json")!
            payload = try! Data(contentsOf: fixture)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Adversarial dated response identity regressions", .serialized)
@MainActor struct RegressionIdentityTests {
    private func service() -> RailService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RegressionIdentityProtocol.self]
        return RailService(client: APIClient(baseURL: URL(string: "https://audit.invalid")!,
            tokenStore: InMemoryTokenStore(), installationId: "audit", session: URLSession(configuration: config),
            privacyDeletionPending: { false }))
    }
    @Test("wrong origin date must not be accepted or cached under requested date")
    func rejectsWrongDate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JourneyCache(directory: directory)
        let model = JourneyModel(trainNumber: "12137", originDate: "2026-10-08", service: service(), cache: cache,
            passport: PassportRepository(directory: directory))
        await model.load()
        #expect(model.journey == nil, "Requested 12137:2026-10-08, returned 12137:2026-09-18 must be rejected")
        let stored = await cache.loadJourney(trainNumber: "12137", originDate: "2026-10-08")
        #expect(stored == nil, "A mismatched dated run must not poison the requested cache entry")
    }
    @Test("wrong train must not be presented or pollute another train's cache")
    func rejectsWrongTrain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JourneyCache(directory: directory)
        let model = JourneyModel(trainNumber: "12951", originDate: "2026-10-08", service: service(), cache: cache,
            passport: PassportRepository(directory: directory))
        await model.load()
        #expect(model.journey == nil, "Requested 12951:2026-10-08, returned 12137:2026-09-18 must be rejected")
        let stored = await cache.loadJourney(trainNumber: "12137", originDate: "2026-10-08")
        #expect(stored == nil, "A wrong-number response must not be cached using a different train and requested date")
    }
}

@Suite("Automatic map lighting wiring regressions")
@MainActor struct RegressionMapLightingTests {
    @Test("automatic mode at full daylight uses a day map")
    func automaticDay() async throws {
        let view = RailMapView(journeyID: "audit", route: [.init(latitude: 19, longitude: 73), .init(latitude: 20, longitude: 74)],
            progress: 0, positionDisplay: .hidden, markers: [],
            daylight: .init(solarElevation: 90, nightAmount: 0, label: .day), lightingMode: .automatic,
            sheetVisibleHeight: 330, cameraCommand: nil)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        func findMap(_ view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            return view.subviews.lazy.compactMap { findMap($0) }.first
        }
        let map = try #require(findMap(host.view))
        #expect(map.overrideUserInterfaceStyle == .light, "Automatic daylight should consume the provided full-day evidence")
    }
}

@Suite("Fractional gateway numeric contract regressions")
struct RegressionFractionalTests {
    @Test("finite fractional gateway timing values decode", arguments: ["prediction.delayMinutes", "prediction.leadMinutes", "prediction.updatedSecondsAgo", "scheduledDurationMinutes", "stop.delayMinutes", "stop.arrivalDelayMinutes", "stop.departureDelayMinutes"])
    func fractionalTiming(field: String) throws {
        let fixture = Bundle(for: RegressionFixtureAnchor.self).url(forResource: "run-12137-2026-09-18", withExtension: "json")!
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? [String: Any])
        var journey = try #require(envelope["journey"] as? [String: Any])
        if field.hasPrefix("prediction.") {
            var prediction = try #require(journey["prediction"] as? [String: Any])
            prediction[String(field.dropFirst("prediction.".count))] = 2.5
            journey["prediction"] = prediction
        } else if field.hasPrefix("stop.") {
            var stops = try #require(journey["stops"] as? [[String: Any]])
            stops[0][String(field.dropFirst("stop.".count))] = 2.5
            journey["stops"] = stops
        } else { journey[field] = 2.5 }
        envelope["journey"] = journey
        struct Response: Decodable { let journey: Journey }
        _ = try JSONDecoder.locomote.decode(Response.self, from: JSONSerialization.data(withJSONObject: envelope))
    }
}


@Suite("Validated cache boundary")
struct ValidatedCacheTests {
    private func fixture(id: String? = nil) throws -> Journey {
        let url = try #require(Bundle(for: RegressionFixtureAnchor.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        var payload = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var journey = try #require(payload["journey"] as? [String: Any])
        if let id { journey["id"] = id }
        payload["journey"] = journey
        struct Envelope: Decodable { let journey: Journey }
        return try JSONDecoder.locomote.decode(Envelope.self, from: JSONSerialization.data(withJSONObject: payload)).journey
    }

    @Test("invalid canonical IDs are rejected even when train and date match")
    func canonicalID() throws {
        let wrong = try fixture(id: "run:12951:2026-09-18")
        #expect(throws: JourneyIdentity.ValidationError.self) {
            try JourneyIdentity.validate(wrong, trainNumber: "12137", originDate: "2026-09-18")
        }
    }

    @Test("invalid replacement preserves the last valid cached journey")
    func replacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JourneyCache(directory: directory)
        await cache.saveJourney(try fixture(), originDate: "2026-09-18")
        await cache.saveJourney(try fixture(id: "wrong"), originDate: "2026-09-18")
        #expect(await cache.loadJourney(trainNumber: "12137", originDate: "2026-09-18")?.journey.id == "run:12137:2026-09-18")
    }

    @Test("a forged cache envelope cannot substitute another dated run")
    func forgedEnvelope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JourneyCache(directory: directory)
        let bad = CachedJourney(journey: try fixture(), originDate: "2026-09-19", cachedAt: Date())
        let url = directory.appendingPathComponent("locomote/journey-12137-2026-09-19.json")
        try JSONEncoder.locomote.encode(bad).write(to: url, options: .atomic)
        #expect(await cache.loadJourney(trainNumber: "12137", originDate: "2026-09-19") == nil)
    }

    @Test("fractional delays are presented without truncating the source")
    func fractionalCopy() {
        #expect(RailNaturalLanguage.delay(minutes: 2.5, status: .observed) == "2.5 minutes late")
        #expect(RailNaturalLanguage.delay(minutes: -0.5, status: .estimated) == "0.5 minutes early · estimated")
        #expect(RailNaturalLanguage.delay(minutes: .infinity, status: .observed) == "Delay unavailable")
    }
}

@Suite("Equipment sightings and private reservation details")
struct PersonalDetailsTests {
    @Test("reports validate railway identifiers and contain no passenger or location data")
    func equipmentRequest() throws {
        #expect(PhysicalSighting.locomotive(" 30212 ") == "30212")
        #expect(PhysicalSighting.locomotive("00000") == nil)
        #expect(PhysicalSighting.coaches("12345,12345") == nil)
        #expect(PhysicalSighting.coaches("000000") == nil)
        #expect(PhysicalSighting.request(locomotive: "", coaches: "") == nil)
        let request = try #require(PhysicalSighting.request(locomotive: "30212", coaches: "12345, 23456"))
        #expect(request.sightings.count == 3)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(Set(json.keys) == ["sightings", "consent"])
        let entries = try #require(json["sightings"] as? [[String: Any]])
        #expect(entries.allSatisfy { Set($0.keys) == ["assetKind", "identifier", "observedAt", "evidenceMethod"] })
        #expect(request.consent.noticeHash == Consent.noticeHash)
    }
    @Test("legacy plans decode; private coach and seat survive resolving, cache and Passport")
    func privatePlan() async throws {
        let url = try #require(Bundle(for: RegressionFixtureAnchor.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        struct Envelope: Decodable { let journey: Journey }
        let journey = try JSONDecoder.locomote.decode(Envelope.self, from: Data(contentsOf: url)).journey
        let legacy = try JourneyPlanLogic.create(journey: journey, originDate: journey.travelDate, boardingIndex: 1, alightingIndex: 2)
        #expect(try JSONDecoder().decode(JourneyPlan.self, from: JSONEncoder().encode(legacy)).coach == nil)
        let plan = try JourneyPlanLogic.create(journey: journey, originDate: journey.travelDate, boardingIndex: 1, alightingIndex: 2, coach: " B2 ", seat: "42 (LB)")
        #expect(JourneyPlanLogic.resolve(journey: journey, plan: plan)?.coach == "B2")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JourneyCache(directory: directory)
        await cache.savePlan(plan)
        #expect(await cache.loadPlan(trainNumber: journey.trainNumber, originDate: journey.travelDate)?.seat == "42 (LB)")
        #expect(Passport.makeSaved(journey: journey, originDate: journey.travelDate, plan: plan, preview: false).personalPlan?.coach == "B2")
    }
}

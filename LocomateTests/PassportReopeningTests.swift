import Foundation
import Testing
@testable import Locomate

@Suite("Saved Passport reopening")
@MainActor
struct PassportReopeningTests {
    @Test("saved segment survives a later working-plan edit and the next load")
    func savedPlanWins() async throws {
        let journey = try fixture()
        let date = "2026-10-01"
        let original = try JourneyPlanLogic.create(journey: journey, originDate: date, boardingIndex: 1, alightingIndex: 3)
        let saved = Passport.makeSaved(journey: journey, originDate: date, plan: original, preview: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JourneyCache(directory: directory)
        let passport = PassportRepository(directory: directory)
        await passport.save([saved])
        let reloaded = try #require(await passport.load().first)
        #expect(reloaded.personalPlan == original)
        await cache.savePlan(JourneyPlanLogic.default(journey: journey, originDate: date))
        let model = JourneyModel(trainNumber: journey.trainNumber, originDate: date, service: nil,
                                 cache: cache, passport: passport, savedJourney: reloaded)
        await model.load()
        #expect(model.plan?.boarding.index == 1)
        #expect(model.plan?.alighting.index == 3)
        #expect(model.planNotice == nil)
        let next = JourneyModel(trainNumber: journey.trainNumber, originDate: date, service: nil, cache: cache, passport: passport)
        await next.load()
        #expect(next.plan?.boarding.index == 1)
        #expect(next.plan?.alighting.index == 3)
    }

    @Test("old rows resolve unique saved calls, but duplicate calls require saved indices")
    func legacyResolution() throws {
        let journey = try fixture()
        let plan = try JourneyPlanLogic.create(journey: journey, originDate: "2026-10-01", boardingIndex: 1, alightingIndex: 2)
        let saved = Passport.makeSaved(journey: journey, originDate: plan.originDate, plan: plan)
        var raw = try #require(JSONSerialization.jsonObject(with: JSONEncoder.locomote.encode(saved)) as? [String: Any])
        raw.removeValue(forKey: "personalPlan")
        let legacy = try JSONDecoder.locomote.decode(SavedJourney.self, from: JSONSerialization.data(withJSONObject: raw))
        #expect(legacy.personalPlan == nil)
        #expect(PassportReopening.plan(for: legacy, journey: journey, originDate: plan.originDate)?.boarding.index == 1)
        var route = try #require(JSONSerialization.jsonObject(with: JSONEncoder.locomote.encode(journey)) as? [String: Any])
        let stops = try #require(route["stops"] as? [[String: Any]])
        route["stops"] = [stops[1], stops[2], stops[1], stops[2]]
        let repeated = try JSONDecoder.locomote.decode(Journey.self, from: JSONSerialization.data(withJSONObject: route))
        #expect(PassportReopening.plan(for: legacy, journey: repeated, originDate: plan.originDate) == nil)
        let secondCall = try JourneyPlanLogic.create(journey: repeated, originDate: plan.originDate, boardingIndex: 2, alightingIndex: 3)
        let indexed = Passport.makeSaved(journey: repeated, originDate: plan.originDate, plan: secondCall)
        #expect(PassportReopening.plan(for: indexed, journey: repeated, originDate: plan.originDate)?.boarding.index == 2)
        #expect(PassportReopening.plan(for: indexed, journey: repeated, originDate: "2026-10-02") == nil)
        #expect(PassportReopening.destination(for: saved, production: true)?.date == plan.originDate)
        #expect(PassportReopening.destination(for: saved, production: false) == nil)
        var unknown = saved
        unknown.preview = nil
        #expect(PassportReopening.destination(for: unknown, production: true) == nil)
    }

    @Test("an invalid saved segment shows explicit full-route fallback, not unrelated cached stops")
    func explicitFallback() async throws {
        let journey = try fixture()
        let date = "2026-10-01"
        let working = try JourneyPlanLogic.create(journey: journey, originDate: date, boardingIndex: 2, alightingIndex: 4)
        var saved = Passport.makeSaved(journey: journey, originDate: date, plan: working, preview: true)
        saved.personalPlan = JourneyPlan(trainNumber: "99999", originDate: date,
            boarding: working.boarding, alighting: working.alighting, updatedAt: working.updatedAt)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JourneyCache(directory: directory)
        await cache.savePlan(working)
        let model = JourneyModel(trainNumber: journey.trainNumber, originDate: date, service: nil,
            cache: cache, passport: PassportRepository(directory: directory), savedJourney: saved)
        await model.load()
        #expect(model.plan?.boarding.index == 0)
        #expect(model.plan?.alighting.index == journey.stops.count - 1)
        #expect(model.planNotice?.contains("Showing the full route") == true)
        #expect(await cache.loadPlan(trainNumber: journey.trainNumber, originDate: date)?.boarding.index == 0)
    }

    private func fixture() throws -> Journey {
        PreviewData.journey(from: try #require(RoutePackStore.pack("12137")), originDate: "2026-10-01")
    }
}

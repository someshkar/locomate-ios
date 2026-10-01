import Foundation
import Testing
@testable import Locomate

private actor AlertTestAPI: JourneyAlertAPI {
    var registrations: [JourneyAlertRegistration] = []
    var deletions: [(String, Int64)] = []
    var failures = 0
    var conflictRevision: Int64?
    var hold = false
    var release: CheckedContinuation<Void, Never>?
    var started: CheckedContinuation<Void, Never>?

    func configure(failures: Int = 0, conflictRevision: Int64? = nil, hold: Bool = false) {
        self.failures = failures; self.conflictRevision = conflictRevision; self.hold = hold
    }
    func waitForRegistration() async {
        if !registrations.isEmpty { return }
        await withCheckedContinuation { started = $0 }
    }
    func finishRegistration() { release?.resume(); release = nil }
    func registerJourneyAlerts(_ request: JourneyAlertRegistration) async throws -> JourneyAlertAcknowledgement {
        registrations.append(request)
        started?.resume(); started = nil
        if hold { await withCheckedContinuation { release = $0 }; hold = false }
        if let revision = conflictRevision {
            conflictRevision = nil
            throw APIError(status: 409, code: "revision_conflict", requestId: "", retryable: false,
                message: "Revision conflict", currentRevision: revision)
        }
        if failures > 0 { failures -= 1; throw URLError(.notConnectedToInternet) }
        return .init(stored: true, runId: request.runId, revision: request.revision,
            expiresAt: Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000)
    }
    func unregisterJourneyAlerts(runId: String, revision: Int64) async throws {
        deletions.append((runId, revision))
        if failures > 0 { failures -= 1; throw URLError(.notConnectedToInternet) }
    }
}

@MainActor
private final class AlertTestPush: JourneyAlertPushAuthorization {
    var token: String? = String(repeating: "a", count: 64)
    var environment = "sandbox"
    var denied = false
    var asked = 0
    var registrations = 0
    var holdStatus = false
    var statusWaiting = false
    var statusGate: CheckedContinuation<Bool, Never>?
    func requestPermission() async throws -> Bool { asked += 1; return !denied }
    func isDenied() async -> Bool {
        if holdStatus {
            statusWaiting = true
            return await withCheckedContinuation { statusGate = $0 }
        }
        return denied
    }
    func register() { registrations += 1 }
}

@Suite("Native journey alerts") @MainActor
struct JourneyAlertTests {
    private func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func seed(expired: Bool = false, pending: Bool = true) -> JourneyAlertSubscription {
        .init(runId: "12137:2026-10-01", trainNumber: "12137", serviceDate: "2026-10-01",
            channels: Set(JourneyAlertChannel.allCases), quietHours: nil,
            expiresAt: Date().addingTimeInterval(expired ? -1 : 3600), pending: pending,
            enabled: true, revision: 1, targetFingerprint: nil)
    }
    private func payload(revision: Int64 = 1, now: Date = Date()) -> [String: String] {
        ["type": "journey-alert", "version": "1", "eventId": "alert:abcdef", "runId": "12137:2026-10-01",
         "revision": String(revision), "channel": "delay", "trainNumber": "12137", "serviceDate": "2026-10-01",
         "observedAt": String(Int64(now.timeIntervalSince1970 * 1000)),
         "expiresAt": String(Int64(now.addingTimeInterval(300).timeIntervalSince1970 * 1000)),
         "title": "Delay changed", "body": "12137 is now 10 minutes late.",
         "deepLink": "locomate://journeys/12137?date=2026-10-01"]
    }

    @Test("offline withdrawal survives relaunch and retains its revision tombstone")
    func offlineWithdrawal() async throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = JourneyAlertStore(directory: directory, scope: "production")
        try store.save([seed()])
        let api = AlertTestAPI(); await api.configure(failures: 1)
        let service = JourneyAlertService(api: api, scope: "production", directory: directory, push: AlertTestPush())
        do { try await service.disable(runId: "run:12137:2026-10-01"); Issue.record("Expected offline error") } catch {}
        let desired = try #require(store.load().first)
        #expect(!desired.enabled && desired.pending && desired.revision > 1)
        let restarted = JourneyAlertService(api: api, scope: "production", directory: directory, push: AlertTestPush())
        await restarted.refresh()
        let acknowledged = try #require(store.load().first)
        #expect(!acknowledged.enabled && !acknowledged.pending && acknowledged.revision == desired.revision)
        #expect(await api.deletions.count == 2)
    }

    @Test("late registration cannot overwrite a newer disable")
    func disableDuringRegistration() async throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = JourneyAlertStore(directory: directory, scope: "production"); try store.save([seed()])
        let api = AlertTestAPI(); await api.configure(hold: true)
        let service = JourneyAlertService(api: api, scope: "production", directory: directory, push: AlertTestPush())
        let refresh = Task { await service.refresh() }
        await api.waitForRegistration()
        let disable = Task { try await service.disable(runId: "12137:2026-10-01") }
        for _ in 0..<100 where service.subscriptions.first?.enabled == true { await Task.yield() }
        #expect(service.subscriptions.first?.enabled == false)
        await api.finishRegistration()
        await refresh.value
        try await disable.value
        let final = try #require(store.load().first)
        #expect(!final.enabled && !final.pending)
        #expect(await api.deletions.last?.1 == final.revision)
    }

    @Test("token rotation advances revision and invalidates older delivered messages")
    func tokenRotation() async throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        try JourneyAlertStore(directory: directory, scope: "production").save([seed()])
        let api = AlertTestAPI(); let push = AlertTestPush()
        let service = JourneyAlertService(api: api, scope: "production", directory: directory, push: push)
        await service.refresh()
        let before = try #require(service.subscriptions.first?.revision)
        let old = try #require(JourneyAlertPayload(fields: payload(revision: before)))
        #expect(service.accepts(old, presenting: true))
        #expect(!service.accepts(old, presenting: true))
        #expect(service.accepts(old, presenting: false))
        let restarted = JourneyAlertService(api: api, scope: "production", directory: directory, push: push)
        #expect(!restarted.accepts(old, presenting: true))
        #expect(restarted.accepts(old, presenting: false))
        push.token = String(repeating: "b", count: 64)
        await service.refresh()
        #expect(try #require(service.subscriptions.first?.revision) > before)
        #expect(!service.accepts(old, presenting: false))
        let saved = try String(contentsOf: JourneyAlertStore(directory: directory, scope: "production").file, encoding: .utf8)
        #expect(!saved.contains(String(repeating: "a", count: 64)))
        #expect(!saved.contains(String(repeating: "b", count: 64)))
    }

    @Test("expiry and system permission withdrawal unregister without requesting permission again")
    func expiryAndDenial() async throws {
        for expired in [true, false] {
            let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
            try JourneyAlertStore(directory: directory, scope: "production").save([seed(expired: expired)])
            let api = AlertTestAPI(); let push = AlertTestPush(); push.denied = !expired
            let service = JourneyAlertService(api: api, scope: "production", directory: directory, push: push)
            await service.refresh()
            #expect(service.subscriptions.first?.enabled == false)
            #expect(await api.registrations.isEmpty)
            #expect(await api.deletions.count == 1)
            #expect(push.asked == 0)
        }
    }

    @Test("server revision conflict recovers only the stored desired mutation")
    func conflict() async throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        try JourneyAlertStore(directory: directory, scope: "production").save([seed()])
        let api = AlertTestAPI()
        let revision = Int64(Date().addingTimeInterval(100).timeIntervalSince1970 * 1000)
        await api.configure(conflictRevision: revision)
        let service = JourneyAlertService(api: api, scope: "production", directory: directory, push: AlertTestPush())
        await service.refresh()
        #expect(service.subscriptions.first?.revision == revision + 1)
        #expect(service.subscriptions.first?.pending == false)
        #expect(await api.registrations.count == 2)
    }

    @Test("gateway scopes and unreadable storage cannot silently replace consent choices")
    func storage() async throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = JourneyAlertStore(directory: directory, scope: "production")
        try store.save([seed()])
        #expect(try JourneyAlertStore(directory: directory, scope: "development").load().isEmpty)
        try Data("not json".utf8).write(to: store.file)
        let api = AlertTestAPI()
        let service = JourneyAlertService(api: api, scope: "production", directory: directory, push: AlertTestPush())
        await service.refresh()
        #expect(service.message != nil)
        #expect(await api.registrations.isEmpty)
        #expect(try String(contentsOf: store.file, encoding: .utf8) == "not json")
    }

    @Test("late system-permission callback cannot recreate data after privacy erasure")
    func privacyPermissionRace() async throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = JourneyAlertStore(directory: directory, scope: "production")
        try store.save([seed()])
        let api = AlertTestAPI(); let push = AlertTestPush(); push.holdStatus = true
        let service = JourneyAlertService(api: api, scope: "production", directory: directory, push: push)
        let refresh = Task { await service.refresh() }
        for _ in 0..<100 where !push.statusWaiting { await Task.yield() }
        #expect(push.statusWaiting)
        await service.beginPrivacyDeletion()
        try FileManager.default.removeItem(at: directory)
        push.statusGate?.resume(returning: true); push.statusGate = nil
        await refresh.value
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
        #expect(await api.registrations.isEmpty)
        #expect(await api.deletions.isEmpty)
    }

    @Test("payload rejects forged routes, stale timestamps, wrong runs and unsupported versions")
    func payloadValidation() throws {
        let now = Date()
        let valid = payload(now: now)
        #expect(JourneyAlertPayload(fields: valid, now: now) != nil)
        let invalid = ["deepLink": "locomate://journeys/12137?date=2026-10-01&action=enable",
            "trainNumber": "12951", "serviceDate": "2026-02-30", "runId": "run:12137:2026-10-01",
            "version": "2", "revision": "-1", "channel": "admin", "observedAt": "NaN",
            "expiresAt": String(Int64(now.timeIntervalSince1970 * 1000) - 1)]
        for (key, value) in invalid {
            var changed = valid; changed[key] = value
            #expect(JourneyAlertPayload(fields: changed, now: now) == nil, "Invalid \(key) was accepted")
        }
    }

    @Test("enable uses the dated railway clock timetable and records explicit notification permission")
    func enableClockTimetable() async throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/run-12137-2026-09-18.json")
        let envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var object = try #require(envelope["journey"] as? [String: Any])
        object["id"] = "run:12137:\(IndiaDate.today())"
        object["travelDate"] = IndiaDate.today(); object["completion"] = 0.2
        let journey = try JSONDecoder().decode(Journey.self, from: JSONSerialization.data(withJSONObject: object))
        let api = AlertTestAPI(); let push = AlertTestPush()
        let service = JourneyAlertService(api: api, scope: "production", directory: directory, push: push)
        try await service.enable(journey: journey, channels: [.delay, .platform],
            quietHours: .init(startHour: 22, endHour: 7, timezone: "Asia/Kolkata"))
        #expect(push.asked == 1)
        #expect(service.subscriptions.first?.pending == false)
        let request = try #require(await api.registrations.first)
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect((json["quietHours"] as? [String: String])?["start"] == "22:00")
        #expect((json["quietHours"] as? [String: String])?["timeZone"] == "Asia/Kolkata")
        let noQuiet = JourneyAlertRegistration(runId: request.runId, revision: request.revision,
            target: request.target, channels: request.channels, quietHours: nil)
        let disabled = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(noQuiet)) as? [String: Any])
        #expect(disabled["quietHours"] is NSNull)
    }
}

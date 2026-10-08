import Foundation
import Testing
@testable import Locomate

@Suite("Live Activity delivery recovery")
@MainActor struct LiveActivityRecoveryTests {
    @Test("temporary registration failures retry and expose local-only status until acknowledged")
    func retry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var waits: [Duration] = []
        let registration = LiveActivityRegistration(directory: directory, sleep: { delay in waits.append(delay); await Task.yield() })
        var calls = 0
        registration.register(runId: "run:12345:2026-08-24") { _ in
            calls += 1
            if calls < 3 { throw URLError(.notConnectedToInternet) }
        }
        for _ in 0..<100 where registration.status != .registered { await Task.yield() }
        #expect(calls == 3)
        #expect(waits == [.seconds(1), .seconds(2)])
        #expect(registration.status == .registered)
        registration.erase()
    }

    @Test("withdrawal survives restart without retaining any push token")
    func durableWithdrawal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = LiveActivityRegistration(scope: "test-source", directory: directory, sleep: { _ in throw CancellationError() })
        first.withdraw("run:12345:2026-08-24") { _, _ in throw URLError(.notConnectedToInternet) }
        for _ in 0..<10 { await Task.yield() }
        let bytes = try Data(contentsOf: directory.appendingPathComponent("locomote/test-source/live-activity-unregister.json"))
        let journal = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect((journal["withdrawals"] as? [String: Int64])?["run:12345:2026-08-24"] != nil)
        #expect(journal["pushToken"] == nil)
        let second = LiveActivityRegistration(scope: "test-source", directory: directory)
        var sent: [String] = []
        second.resumeWithdrawals { runId, _ in sent.append(runId) }
        for _ in 0..<100 where !second.pendingWithdrawals.isEmpty { await Task.yield() }
        #expect(sent == ["run:12345:2026-08-24"])
        #expect(second.pendingWithdrawals.isEmpty)
        #expect(LiveActivityRegistration(scope: "another-source", directory: directory).pendingWithdrawals.isEmpty)
        first.erase(); second.erase()
    }

    @Test("erasure defeats a late successful registration callback")
    func lateAcknowledgement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registration = LiveActivityRegistration(directory: directory)
        var completion: CheckedContinuation<Void, Never>?
        registration.register(runId: "run:12345:2026-08-24") { _ in
            await withCheckedContinuation { completion = $0 }
        }
        for _ in 0..<100 where completion == nil { await Task.yield() }
        let callback = try #require(completion)
        registration.erase()
        callback.resume()
        for _ in 0..<10 { await Task.yield() }
        #expect(registration.status == .idle)
        #expect(registration.pendingWithdrawals.isEmpty)
    }
}

extension LiveActivityRecoveryTests {
    @Test("corrupt revision journals fail closed before arithmetic or network dispatch", arguments: [
        #"{"revisions":{"run:12345:2026-08-24":9223372036854775807},"withdrawals":{}}"#,
        #"{"revisions":{"run:12345:2026-08-24":-1},"withdrawals":{}}"#,
        #"{"revisions":{"12345:2026-08-24":1},"withdrawals":{}}"#,
        #"{"revisions":{"run:12345:2026-08-24":1},"withdrawals":{"run:12345:2026-08-24":2}}"#
    ])
    func corruptJournal(_ json: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("locomote/preview/live-activity-unregister.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: file)
        let registration = LiveActivityRegistration(directory: directory, sleep: { _ in throw CancellationError() })
        var sent = false
        registration.register(runId: "run:12345:2026-08-24") { _ in sent = true }
        for _ in 0..<100 where registration.status != .retrying { await Task.yield() }
        #expect(!sent && registration.status == .retrying)
        #expect(try Data(contentsOf: file) == Data(json.utf8))
        registration.cancelRegistration()
    }

    @Test("ordering revisions are durable before dispatch and increase across restart and withdrawal")
    func ordering() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("locomote/test-source/live-activity-unregister.json")
        var seen: [Int64] = []
        let first = LiveActivityRegistration(scope: "test-source", directory: directory)
        first.register(runId: "run:12345:2026-08-24") { revision in
            let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            #expect((json["revisions"] as? [String: Int64])?["run:12345:2026-08-24"] == revision)
            seen.append(revision)
        }
        for _ in 0..<100 where seen.isEmpty { await Task.yield() }
        let second = LiveActivityRegistration(scope: "test-source", directory: directory)
        second.withdraw("run:12345:2026-08-24") { _, revision in seen.append(revision) }
        for _ in 0..<100 where seen.count < 2 { await Task.yield() }
        #expect(seen.count == 2)
        #expect(seen.last! > seen.first!)
        #expect(seen.allSatisfy { $0 > 0 && $0 <= 9_007_199_254_740_991 })
        first.erase(); second.erase()
    }
}

import Foundation
import Testing
@testable import Locomate

@Suite("Destination reliability summary")
@MainActor
struct ReliabilityHistoryTests {
    private let now = Date(timeIntervalSince1970: 1_790_899_200)

    @Test("limit-one contract decodes fractional delay and preserves aggregate policy/provenance")
    func completeContract() throws {
        let value = try fixture()
        try ReliabilitySummary.validate(value, trainNumber: "12137", now: now)
        #expect(value.runs.count == 1)
        #expect(value.runs[0].delayMinutes == 1.5)
        #expect(value.summary.denominator == 5)
        #expect(value.summary.counts.total == 8)
        #expect(ReliabilitySummary.percentage(value.summary.percentages.onTime) == "60%")
        #expect(value.policy.onTimeFromMinutes == -5 && value.policy.onTimeThroughMinutes == 5)
        #expect(!value.provenance.comprehensiveCoverage)
    }

    @Test("empty history and deployed unknown-only history preserve unavailable percentages")
    func zeroDenominator() throws {
        for count in [0, 4] {
            let value = try fixture { raw in
                raw["summary"] = [
                    "counts": ["early": 0, "onTime": 0, "late": 0, "cancelled": 0, "unknown": count, "total": count],
                    "denominator": 0, "percentages": ["early": NSNull(), "onTime": NSNull(), "late": NSNull()],
                    "coverage": count == 0 ? NSNull() : ["from": "2026-08-23", "to": "2026-09-08"],
                    "lowSample": true
                ]
                if count == 0 { raw["runs"] = [] }
                else {
                    var row = (raw["runs"] as! [[String: Any]])[0]
                    row["runId"] = "12137:2026-09-08"
                    row["serviceDate"] = "2026-09-08"
                    row["scheduledArrival"] = "2026-09-09T23:45:00.000Z"
                    row["actualArrival"] = NSNull()
                    row["delayMinutes"] = NSNull()
                    row["classification"] = "unknown"
                    row["source"] = ["schedule": "canonical-intelligence-tables", "actual": NSNull()]
                    raw["runs"] = [row]
                }
            }
            try ReliabilitySummary.validate(value, trainNumber: "12137", now: now)
            #expect(value.summary.denominator == 0)
            #expect(ReliabilitySummary.percentage(value.summary.percentages.onTime) == "—")
            #expect(value.summary.counts.unknown == count)
            #expect((value.summary.coverage != nil) == (count > 0))
        }
    }

    @Test("untrusted counts, percentages, policy, source and timestamps cannot become a reliability claim")
    func validation() throws {
        let edits: [(inout [String: Any]) -> Void] = [
            { $0["trainNumber"] = "12951" },
            { raw in var s = raw["summary"] as! [String: Any]; s["denominator"] = 8; raw["summary"] = s },
            { raw in var s = raw["summary"] as! [String: Any]; s["percentages"] = ["early": 20, "onTime": 75, "late": 20]; raw["summary"] = s },
            { raw in var s = raw["summary"] as! [String: Any]; s["lowSample"] = false; raw["summary"] = s },
            { raw in var s = raw["summary"] as! [String: Any]; s["coverage"] = ["from": "2026-09-31", "to": "2026-09-18"]; raw["summary"] = s },
            { raw in var p = raw["policy"] as! [String: Any]; p["onTimeThroughMinutes"] = 15; raw["policy"] = p },
            { raw in var p = raw["provenance"] as! [String: Any]; p["comprehensiveCoverage"] = true; raw["provenance"] = p },
            { $0["generatedAt"] = "2099-01-01T00:00:00.000Z" },
            { $0["generatedAt"] = "1969-12-31T23:59:00.000Z" }
        ]
        for edit in edits {
            let value = try fixture(edit: edit)
            #expect(throws: ReliabilitySummary.ValidationError.self) {
                try ReliabilitySummary.validate(value, trainNumber: "12137", now: now)
            }
        }
    }

    @Test("once per source/selection/attempt without joining Journey polling")
    func requestScope() async throws {
        let source = NSObject()
        let otherSource = NSObject()
        let model = ReliabilityHistoryModel(privacyPending: { false })
        let value = try fixture()
        var calls = 0
        let fetch = { calls += 1; return value }
        let first = key(source)
        await model.load(key: first, fetch: fetch)
        await model.load(key: first, fetch: fetch)
        #expect(calls == 1)
        if case .idle = model.phase(for: key(otherSource)) {} else { Issue.record("A new source must never render old data before its task starts") }
        if case .idle = model.phase(for: key(source, date: "2026-09-19")) {} else { Issue.record("A new selection must not render old data") }
        if case .unavailable = model.phase(for: key(source, preview: true)) {} else { Issue.record("Preview must immediately hide production history") }
        var retry = first; retry.attempt = 1
        await model.load(key: retry, fetch: fetch)
        #expect(calls == 2)
        await model.load(key: key(otherSource), fetch: fetch)
        #expect(calls == 3)
        await model.load(key: key(otherSource, date: "2026-09-19"), fetch: fetch)
        #expect(calls == 4)
    }

    @Test("preview and pending deletion do not call the service; failures wait for explicit retry")
    func disabledAndRetry() async throws {
        let source = NSObject()
        let latch = Latch()
        let model = ReliabilityHistoryModel(privacyPending: { latch.pending })
        var calls = 0
        await model.load(key: key(source, preview: true)) { calls += 1; throw URLError(.notConnectedToInternet) }
        if case .unavailable = model.phase {} else { Issue.record("Preview must be unavailable") }
        #expect(calls == 0)
        latch.pending = true
        await model.load(key: key(source)) { calls += 1; throw URLError(.notConnectedToInternet) }
        if case .blocked = model.phase {} else { Issue.record("Deletion must block history") }
        #expect(calls == 0)
        latch.pending = false
        var retry = key(source); retry.attempt = 1
        await model.load(key: retry) { calls += 1; throw URLError(.notConnectedToInternet) }
        await model.load(key: retry) { calls += 1; throw URLError(.notConnectedToInternet) }
        #expect(calls == 1)
        if case .failed = model.phase {} else { Issue.record("Failure must remain retryable") }
        retry.attempt = 2
        let value = try fixture()
        await model.load(key: retry) { calls += 1; return value }
        if case .loaded = model.phase {} else { Issue.record("Explicit retry should recover") }
        #expect(calls == 2)
    }

    @Test("late source replies and privacy deletion cannot repopulate the history card")
    func staleRepliesAndDeletion() async throws {
        let source = NSObject(), secondSource = NSObject()
        let latch = Latch()
        let model = ReliabilityHistoryModel(privacyPending: { latch.pending })
        let gate = HistoryGate()
        let old = Task { await model.load(key: key(source)) { try await gate.read() } }
        try await gate.waitUntilPending()
        let current = try fixture { $0["generatedAt"] = "2026-10-01T13:01:00.000Z" }
        await model.load(key: key(secondSource)) { current }
        await gate.complete(try fixture())
        await old.value
        if case .loaded(let value) = model.phase { #expect(value.generatedAt == current.generatedAt) }
        else { Issue.record("New source result must remain visible") }

        var retry = key(secondSource); retry.attempt = 1
        let pending = Task { await model.load(key: retry) { try await gate.read() } }
        try await gate.waitUntilPending()
        latch.pending = true
        await gate.complete(try fixture())
        await pending.value
        if case .blocked = model.phase {} else { Issue.record("Deletion must discard the in-flight response") }
    }

    @Test("cancelling an unfinished card allows a fresh request when it returns")
    func cancellation() async throws {
        let source = NSObject()
        let model = ReliabilityHistoryModel(privacyPending: { false })
        let gate = HistoryGate()
        let pending = Task { await model.load(key: key(source)) { try await gate.read() } }
        try await gate.waitUntilPending()
        pending.cancel()
        model.cancel()
        await gate.complete(try fixture())
        await pending.value
        if case .idle = model.phase {} else { Issue.record("Cancelled card must be idle") }
        let value = try fixture()
        await model.load(key: key(source)) { value }
        if case .loaded = model.phase {} else { Issue.record("Returning card must load") }
    }

    private func key(_ source: NSObject, date: String = "2026-09-18", preview: Bool = false) -> ReliabilityHistoryModel.Key {
        .init(source: ObjectIdentifier(source), trainNumber: "12137", originDate: date, preview: preview)
    }
    private func fixture(edit: (inout [String: Any]) -> Void = { _ in }) throws -> TrainHistoryResponse {
        let url = try #require(Bundle(for: HistoryFixtureAnchor.self).url(forResource: "history-12137", withExtension: "json"))
        var raw = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        edit(&raw)
        return try JSONDecoder.locomote.decode(TrainHistoryResponse.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    private final class Latch { var pending = false }
}

private actor HistoryGate {
    private var continuation: CheckedContinuation<TrainHistoryResponse, Error>?
    func read() async throws -> TrainHistoryResponse { try await withCheckedThrowingContinuation { continuation = $0 } }
    func complete(_ value: TrainHistoryResponse) { continuation?.resume(returning: value); continuation = nil }
    func waitUntilPending() async throws {
        for _ in 0..<100 {
            if continuation != nil { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CancellationError()
    }
}
private final class HistoryFixtureAnchor: NSObject {}

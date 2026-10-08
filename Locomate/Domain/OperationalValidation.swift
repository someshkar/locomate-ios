import Foundation

/// Validate untrusted provider responses before any operational claims or map drawing.
enum OperationalValidation {
    enum InvalidResponse: Error, LocalizedError {
        case malformed
        var errorDescription: String? { "Operational evidence is incomplete or inconsistent." }
    }
    static func check(_ condition: Bool) throws { if !condition { throw InvalidResponse.malformed } }
    static func text(_ value: String, max: Int = 512) -> Bool { !value.isEmpty && value.count <= max }
    static func finite(_ value: Double?) -> Bool { value == nil || value!.isFinite }
    static func timestamp(_ value: Double?) -> Bool { finite(value) && (value == nil || value! >= 0) }
    static func instant(_ value: String) -> Date? { ISO8601DateFormatter.locomote.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
    static func clock(_ value: String) -> Bool { instant(value) != nil || value.range(of: #"\A(?:[01][0-9]|2[0-3]):[0-5][0-9](?::[0-5][0-9])?\z"#, options: .regularExpression) != nil }
    static func runID(_ value: String) -> Bool {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "run" && Routes.isValidTrainNumber(String(parts[1])) && Routes.isValidCalendarDate(String(parts[2]))
    }
    static func coordinate(_ value: RailCoordinate) -> Bool {
        value.latitude.isFinite && value.longitude.isFinite && (-90...90).contains(value.latitude) && (-180...180).contains(value.longitude)
    }
    static func physical(_ response: PhysicalChainResponse, trainNumber: String, originDate: String) throws {
        try check(response.runId == "run:\(trainNumber):\(originDate)" && timestamp(response.asOf)
            && response.asOf <= Date().timeIntervalSince1970 * 1_000 + 60_000)
        try check(["available", "partial", "unavailable"].contains(response.state))
        for (chain, kind) in [(response.rake, "rake"), (response.locomotive, "locomotive")] {
            try check(chain.kind == kind && ["available", "partial", "unavailable"].contains(chain.state))
            try check(chain.assetType == nil || (kind == "rake" ? ["rake", "trainset"] : ["locomotive"]).contains(chain.assetType!))
            try check(chain.unavailableReason == nil || ["no-evidence", "unconfirmed-assignment", "stale-assignment"].contains(chain.unavailableReason!))
            try evidence(chain.assignmentEvidence, asOf: response.asOf)
            if chain.state == "available" { try check(chain.current != nil && chain.assignmentEvidence.freshness == "fresh") }
            let runs = [chain.previous, chain.current, chain.next].compactMap { $0 }
            try check(Set(runs.map(\.runId)).count == runs.count)
            for run in runs {
                try check(runID(run.runId) && run.runId == "run:\(run.trainNumber):\(run.serviceDate)")
                try check(["scheduled", "running", "completed", "cancelled"].contains(run.status))
                try check(StationSearch.isValidCode(run.origin.code) && StationSearch.isValidCode(run.destination.code)
                    && text(run.origin.name, max: 160) && text(run.destination.name, max: 160))
                try check(timestamp(run.scheduledStartAt) && timestamp(run.scheduledEndAt) && run.scheduledStartAt <= run.scheduledEndAt
                    && IndiaDate.today(Date(timeIntervalSince1970: run.scheduledStartAt / 1_000)) == run.serviceDate)
                try check(timestamp(run.scheduledOutboundDepartureAt) && timestamp(run.inboundTerminalArrival.scheduledAt)
                    && timestamp(run.inboundTerminalArrival.predictedAt) && timestamp(run.inboundTerminalArrival.actualAt))
            }
            if let current = chain.current { try check(current.runId == response.runId) }
            if let previous = chain.previous, let current = chain.current { try check(previous.scheduledStartAt <= current.scheduledStartAt) }
            if let current = chain.current, let next = chain.next { try check(current.scheduledStartAt <= next.scheduledStartAt) }
            for link in [chain.inboundLink, chain.outboundLink] {
                try check(["confirmed", "broken", "unavailable"].contains(link.state)
                    && ["confirmed-assignments", "cancelled-transition", "asset-swap", "no-confirmed-run"].contains(link.reason))
                try evidence(link.evidence, asOf: response.asOf)
                try check(timestamp(link.minimumServiceDurationMs) && timestamp(link.serviceReadyAt))
                if link.state == "confirmed" { try check(link.reason == "confirmed-assignments") }
            }
        }
    }
    private static func evidence(_ evidence: PhysicalEvidence, asOf: Double) throws {
        try check(finite(evidence.confidence) && (evidence.confidence == nil || (0...1).contains(evidence.confidence!)))
        try check(evidence.source == nil || text(evidence.source!, max: 100))
        try check(timestamp(evidence.recordedAt) && timestamp(evidence.ageMs) && timestamp(evidence.expiresAt))
        try check(["fresh", "stale", "unknown"].contains(evidence.freshness))
        if let recorded = evidence.recordedAt {
            try check(recorded <= asOf + 60_000)
            if let expires = evidence.expiresAt { try check(expires >= recorded) }
            if let age = evidence.ageMs { try check(abs(age - max(0, asOf - recorded)) <= 60_000) }
        }
        if evidence.freshness == "fresh" {
            try check(evidence.recordedAt != nil && evidence.source != nil)
            if let expires = evidence.expiresAt { try check(expires >= asOf) }
        }
    }
    static func operations(_ response: OperationalChainResponse, trainNumber: String, originDate: String) throws {
        try check(response.trainNumber == trainNumber && response.originDate == originDate)
        try check(["available", "partial", "unavailable"].contains(response.availability) && ["live", "inferred", "preview"].contains(response.mode))
        try check(text(response.disclaimer, max: 4_096) && instant(response.updatedAt) != nil)
        if response.availability != "unavailable" { try check(response.current != nil) }
        let runs = [response.previous, response.current, response.next].compactMap { $0 }
        try check(Set(runs.map(\.id)).count == runs.count)
        for (run, role) in [(response.previous, "previous"), (response.current, "current"), (response.next, "next")] {
            guard let run else { continue }
            try check(run.role == role && runID(run.id) && run.id.split(separator: ":")[1] == Substring(run.trainNumber))
            try check(text(run.trainName, max: 160) && StationSearch.isValidCode(run.originCode) && StationSearch.isValidCode(run.destinationCode))
            try check(clock(run.scheduledDeparture) && clock(run.scheduledArrival))
            if let departure = instant(run.scheduledDeparture), let arrival = instant(run.scheduledArrival) {
                try check(arrival >= departure && IndiaDate.today(departure) == String(run.id.split(separator: ":")[2]))
            }
            if let departure = run.actualDeparture { try check(clock(departure)) }
            if let arrival = run.actualArrival { try check(clock(arrival)) }
            if let departure = run.actualDeparture.flatMap(instant), let arrival = run.actualArrival.flatMap(instant) { try check(arrival >= departure) }
            if let arrival = run.predictedArrival { try check(clock(arrival)) }
            try check(["official", "inferred", "preview"].contains(run.geometry.source)
                && (1...20_000).contains(run.geometry.coordinates.count) && run.geometry.coordinates.allSatisfy(coordinate))
            if let position = run.position {
                try check(coordinate(position.coordinate) && position.progress.isFinite && (0...1).contains(position.progress)
                    && instant(position.observedAt) != nil)
            }
        }
        if let current = response.current { try check(current.id == "run:\(trainNumber):\(originDate)") }
        if let linkage = response.linkage {
            try check(["same-rake", "possible-same-rake", "not-linked"].contains(linkage.claim)
                && ["rake-id", "consist-match", "schedule-continuity", "manual"].contains(linkage.method))
            try check(linkage.caveats.count <= 64 && linkage.caveats.allSatisfy { text($0, max: 1_024) })
        }
        if let assessment = response.delayAssessment {
            try check(assessment.incomingDelayMinutes.isFinite && text(assessment.summary, max: 4_096) && assessment.evidence.count <= 256)
            try check(Set(assessment.evidence.map(\.id)).count == assessment.evidence.count)
            for evidence in assessment.evidence {
                try check(text(evidence.id, max: 128) && ["arrival", "departure", "turnaround", "operations-note"].contains(evidence.kind)
                    && text(evidence.summary, max: 4_096) && finite(evidence.delayMinutes))
                if let at = evidence.observedAt { try check(instant(at) != nil) }
            }
        }
        if let delay = response.propagatedDelay {
            try check(runID(delay.fromRunId) && runID(delay.toRunId) && delay.fromRunId != delay.toRunId
                && delay.minutes.isFinite && text(delay.explanation, max: 4_096) && delay.evidenceIds.count <= 256)
        }
        if let risk = response.turnaroundRisk {
            try check(["low", "medium", "high"].contains(risk.level) && risk.scheduledMinutes.isFinite
                && risk.availableMinutes.isFinite && risk.minimumMinutes.isFinite && text(risk.summary, max: 4_096))
        }
    }
    static func sightingResponse(_ response: PhysicalSightingResponse, expectedCount: Int) throws {
        try check(response.acceptedIds.count == expectedCount && Set(response.acceptedIds).count == expectedCount
            && response.acceptedIds.allSatisfy { text($0, max: 128) } && text(response.message, max: 4_096))
        try check(["proposed", "partial", "confirmed", "conflicting"].contains(response.evidenceState.locomotive)
            && ["proposed", "partial", "confirmed", "conflicting"].contains(response.evidenceState.rake))
    }
}

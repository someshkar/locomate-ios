import Foundation

/// The summary describes the train's final destination, across all eligible
/// gateway records. The response's small run page is not its denominator.
enum ReliabilitySummary {
    enum ValidationError: Error { case invalidHistory }

    static func validate(_ value: TrainHistoryResponse, trainNumber: String, now: Date = Date()) throws {
        let summary = value.summary
        let counts = summary.counts
        let values = [counts.early, counts.onTime, counts.late, counts.cancelled, counts.unknown, counts.total, summary.denominator]
        guard value.trainNumber == trainNumber, Routes.isValidTrainNumber(trainNumber),
              values.allSatisfy({ (0...9_007_199_254_740_991).contains($0) }),
              counts.total == counts.early + counts.onTime + counts.late + counts.cancelled + counts.unknown,
              summary.denominator == counts.early + counts.onTime + counts.late,
              summary.lowSample == (summary.denominator < 10),
              value.policy.version == "destination-arrival-delay-v1",
              value.policy.earlyBelowMinutes == -5, value.policy.onTimeFromMinutes == -5,
              value.policy.onTimeThroughMinutes == 5, value.policy.lateAboveMinutes == 5,
              value.provenance.source == "canonical-intelligence-tables",
              !value.provenance.comprehensiveCoverage,
              !value.provenance.disclosure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let generated = timestamp(value.generatedAt), generated.timeIntervalSince1970 >= 0,
              generated.timeIntervalSince(now) <= 60
        else { throw ValidationError.invalidHistory }
        if counts.total == 0 {
            guard summary.coverage == nil else { throw ValidationError.invalidHistory }
        } else {
            guard let coverage = summary.coverage,
                  Routes.isValidCalendarDate(coverage.from), Routes.isValidCalendarDate(coverage.to),
                  coverage.from <= coverage.to else { throw ValidationError.invalidHistory }
        }
        let pairs = [(counts.early, summary.percentages.early),
                     (counts.onTime, summary.percentages.onTime), (counts.late, summary.percentages.late)]
        for (count, percentage) in pairs {
            if summary.denominator == 0 {
                guard percentage == nil else { throw ValidationError.invalidHistory }
            } else {
                guard let percentage, percentage.isFinite, (0...100).contains(percentage),
                      abs(percentage - Double(count) * 100 / Double(summary.denominator)) < 0.000_001
                else { throw ValidationError.invalidHistory }
            }
        }
    }

    static func timestamp(_ raw: String) -> Date? {
        ISO8601DateFormatter.locomote.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    static func generatedLabel(_ raw: String) -> String {
        guard let date = timestamp(raw) else { return "Generated time unavailable" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = IndiaDate.calendar
        formatter.timeZone = IndiaDate.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Report generated \(formatter.string(from: date)) IST"
    }

    static func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }
}

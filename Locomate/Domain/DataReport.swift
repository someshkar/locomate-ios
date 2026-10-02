//
//  DataReport.swift
//  Locomate
//
//  Provenance banner model — ported from SmartRail `src/domain/dataReport.ts`.
//  The banner is the app's honesty surface: it always states what the user is
//  looking at (demo / old timetable / stale report / saved update / live).
//

import Foundation

public struct DataReportInput: Sendable {
    public var preview: Bool
    public var historicalRoute: Bool
    public var cached: Bool
    public var cachedAt: Date?
    public var error: String?
    public var observedAt: String?
    public init(
        preview: Bool = false,
        historicalRoute: Bool = false,
        cached: Bool = false,
        cachedAt: Date? = nil,
        error: String? = nil,
        observedAt: String? = nil
    ) {
        self.preview = preview
        self.historicalRoute = historicalRoute
        self.cached = cached
        self.cachedAt = cachedAt
        self.error = error
        self.observedAt = observedAt
    }
}

public struct DataBannerModel: Sendable, Equatable {
    public let status: StatusKind
    public let title: String
    public let body: String
}

public enum DataReport {
    public static func banner(_ input: DataReportInput, now: Date = Date()) -> DataBannerModel {
        let cachedMinutes = input.cachedAt.map { max(1, Int((now.timeIntervalSince($0) / 60).rounded())) }
        let reportMinutes: Int? = {
            guard let observedAt = input.observedAt,
                  let date = ISO8601DateFormatter.locomote.date(from: observedAt) else { return nil }
            return max(0, Int((now.timeIntervalSince(date) / 60).rounded()))
        }()
        let oldReport = (reportMinutes ?? 0) > 5

        if input.preview || input.historicalRoute {
            return DataBannerModel(
                status: .preview,
                title: input.preview ? "DEMO DATA" : "OLD TIMETABLE",
                body: input.preview
                    ? "Explore the app with sample information. Nothing here is live."
                    : "This is an old timetable, not current train information."
            )
        }
        if oldReport, let minutes = reportMinutes {
            return DataBannerModel(
                status: .stale,
                title: "OLD RAIL REPORT",
                body: "The latest rail report is \(minutes) min old. Times and positions may no longer be current."
            )
        }
        if input.cached {
            let age = cachedMinutes.map { "Saved \($0) min ago." } ?? "Saved report age unknown."
            return DataBannerModel(
                status: .stale,
                title: "SAVED UPDATE",
                body: input.error != nil
                    ? "\(age) Refresh failed; retrying automatically."
                    : "\(age) Checking for a newer report."
            )
        }
        if let error = input.error {
            return DataBannerModel(status: .error, title: "LIVE UPDATE UNAVAILABLE", body: error)
        }
        return DataBannerModel(
            status: .onTime,
            title: "LATEST RAIL REPORT",
            body: "Times may be estimates. Open details to check the source and report age."
        )
    }
}

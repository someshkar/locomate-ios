//
//  JourneyStore.swift
//  Locomate
//
//  Local persistence: the last successful journey (for offline recovery) and
//  the personal journey plan. Mirrors the RN offline/passport repositories,
//  using file-backed JSON for now (SQLite/GRDB swap lands with Phase 6).
//

import Foundation
import Observation

/// Passport and pending observations belong to this installation, not a
/// restored copy on another device. Atomic writes can reset this flag, so
/// callers also apply it to each newly written file.
func excludeFromBackup(_ location: URL) {
    var url = location
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? url.setResourceValues(values)
}

public actor JourneyCache {
    private let directory: URL

    public init(directory: URL? = nil, scope: String? = nil) {
        let base = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("locomote", isDirectory: true)
        self.directory = scope.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    public func saveJourney(_ journey: Journey, originDate: String) {
        guard (try? JourneyIdentity.validate(journey, trainNumber: journey.trainNumber, originDate: originDate)) != nil else { return }
        let payload = CachedJourney(journey: journey, originDate: originDate, cachedAt: Date())
        if let data = try? JSONEncoder.locomote.encode(payload) {
            try? data.write(to: url("journey-\(journey.trainNumber)-\(originDate).json"), options: .atomic)
        }
    }

    public func loadJourney(trainNumber: String, originDate: String) -> CachedJourney? {
        guard let data = try? Data(contentsOf: url("journey-\(trainNumber)-\(originDate).json")) else { return nil }
        guard let cached = try? JSONDecoder.locomoteDates.decode(CachedJourney.self, from: data),
              cached.originDate == originDate,
              (try? JourneyIdentity.validate(cached.journey, trainNumber: trainNumber, originDate: originDate)) != nil else { return nil }
        return cached
    }

    public func savePlan(_ plan: JourneyPlan) {
        guard let data = try? JSONEncoder.locomote.encode(plan) else { return }
        try? data.write(to: url("plan-\(plan.trainNumber)-\(plan.originDate).json"), options: .atomic)
    }

    public func loadPlan(trainNumber: String, originDate: String) -> JourneyPlan? {
        guard let data = try? Data(contentsOf: url("plan-\(trainNumber)-\(originDate).json")) else { return nil }
        guard let plan = try? JSONDecoder.locomote.decode(JourneyPlan.self, from: data),
              plan.trainNumber == trainNumber, plan.originDate == originDate,
              plan.boarding.index >= 0, plan.alighting.index > plan.boarding.index else { return nil }
        return plan
    }

}

public struct CachedJourney: Codable, Sendable {
    public let journey: Journey
    public let originDate: String
    public let cachedAt: Date
}

// MARK: - Passport repository

public actor PassportRepository {
    private let url: URL

    public init(directory: URL? = nil, scope: String? = nil) {
        let base = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = base.appendingPathComponent("locomote", isDirectory: true)
        let folder = scope.map { root.appendingPathComponent($0, isDirectory: true) } ?? root
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        excludeFromBackup(folder)
        self.url = folder.appendingPathComponent("passport.json")
        if FileManager.default.fileExists(atPath: self.url.path) {
            excludeFromBackup(self.url)
        }
    }

    public func load() -> [SavedJourney] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder.locomote.decode([SavedJourney].self, from: data)) ?? []
    }

    public func save(_ journeys: [SavedJourney]) {
        guard let data = try? JSONEncoder.locomote.encode(journeys) else { return }
        if (try? data.write(to: url, options: .atomic)) != nil {
            excludeFromBackup(url)
        }
    }
}

public extension JSONEncoder {
    static let locomote: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

public extension JSONDecoder {
    static let locomoteDates: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

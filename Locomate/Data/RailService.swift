//
//  RailService.swift
//  Locomate
//
//  Typed rail endpoints — mirrors SmartRail `src/services/railData.ts`
//  (searchTrains, fetchJourney, fetchOperationalChain, fetchNetwork, history).
//

import Foundation

public struct TrainSearchResult: Codable, Sendable, Identifiable {
    public var id: String { number }
    public let number: String
    public let name: String
    public let originCode: String
    public let originName: String
    public let destinationCode: String
    public let destinationName: String
    public let departure: String
    public let arrival: String
    public let durationHours: Double
    public let distanceKm: Double
    public let sourceLabel: String
    public let sourceUpdatedAt: String
    public let live: Bool
}

private struct TrainSearchResponse: Decodable {
    let trains: [TrainSearchResult]
}

private struct JourneyResponse: Decodable {
    let journey: Journey
}

public protocol RailServiceProtocol: Sendable {
    func registerLiveActivityToken(
        runId: String, token: String, state: JourneyActivityAttributes.ContentState
    ) async throws
    func unregisterLiveActivity(runId: String) async throws
    func uploadObservations(_ batch: [CompactObservation]) async throws -> [String]
    func searchTrains(_ query: String) async throws -> [TrainSearchResult]
    func journey(trainNumber: String, originDate: String) async throws -> Journey
    func operationalChain(trainNumber: String, originDate: String) async throws -> OperationalChainResponse
    func networkTrains(bounds: NetworkBounds) async throws -> NetworkTrainsResponse
    func trainHistory(trainNumber: String, limit: Int) async throws -> TrainHistoryResponse
}

public struct RailService: RailServiceProtocol {
    private let client: APIClient

    public init(client: APIClient) { self.client = client }

    /// Register a Live Activity push-to-update token so the gateway can refresh
    /// the ETA without the app polling. Mirrors the SmartRail subscription call.
    public func registerLiveActivityToken(
        runId: String, token: String, state: JourneyActivityAttributes.ContentState
    ) async throws {
        struct Ack: Decodable { let accepted: Bool? }
        let _: Ack = try await client.post(
            "/v1/live-activities/subscriptions",
            body: [
                "runId": runId,
                "pushToken": token,
                "contentState": [
                    "nextStation": state.nextStation,
                    "eta": state.eta,
                    "delayMinutes": state.delayMinutes.map { $0 as Any } ?? NSNull(),
                    "delayLabel": state.delayLabel,
                    "distanceToNextKm": state.distanceToNextKm,
                    "confidence": state.confidence,
                    "updatedAt": state.updatedAt.timeIntervalSinceReferenceDate
                ] as [String: Any]
            ],
            idempotencyKey: "live-activity-\(runId)"
        )
    }

    public func unregisterLiveActivity(runId: String) async throws {
        guard runId.range(of: "^[A-Za-z0-9:._-]{1,128}$", options: .regularExpression) != nil else { return }
        try await client.delete("/v1/live-activities/subscriptions/\(runId)")
    }

    /// Upload a consented observation batch. Returns the accepted local IDs.
    /// Mirrors the SmartRail `/v1/observations/batch` contract (delta-encoded,
    /// idempotent, no passenger identity).
    public func uploadObservations(_ batch: [CompactObservation]) async throws -> [String] {
        guard !batch.isEmpty else { return [] }
        struct Request: Encodable {
            struct Item: Encodable {
                let localId: String
                let runId: String
                let timestamp: Int
                let latE5: Int
                let lonE5: Int
                let speedKph: Double
                let accuracyM: Double
                let routeProgress: Double
                let matchDistanceM: Double
                let consentVersion: Int
            }
            let consentVersion: Int
            let observations: [Item]
        }
        struct Response: Decodable { let acceptedLocalIds: [String] }

        let body = Request(
            consentVersion: batch.map(\.consentVersion).max() ?? Consent.version,
            observations: batch.map { item in
                Request.Item(
                    localId: "\(item.runId):\(item.timestamp)",
                    runId: item.runId,
                    timestamp: item.timestamp,
                    latE5: item.latE5,
                    lonE5: item.lonE5,
                    speedKph: item.speedKph,
                    accuracyM: item.accuracyM,
                    routeProgress: item.routeProgress,
                    matchDistanceM: item.matchDistanceM,
                    consentVersion: item.consentVersion
                )
            }
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let response: Response = try await client.post(
            "/v1/observations/batch",
            body: payload,
            idempotencyKey: "batch-\(batch.first?.runId ?? "unknown")-\(batch.last?.timestamp ?? 0)"
        )
        return response.acceptedLocalIds
    }

    public func searchTrains(_ query: String) async throws -> [TrainSearchResult] {
        let response: TrainSearchResponse = try await client.get(
            "/v1/trains/search", query: ["q": query]
        )
        return response.trains
    }

    public func journey(trainNumber: String, originDate: String) async throws -> Journey {
        let response: JourneyResponse = try await client.get("/v1/runs/\(trainNumber)/\(originDate)")
        return response.journey
    }

    public func operationalChain(trainNumber: String, originDate: String) async throws -> OperationalChainResponse {
        try await client.get(
            "/v1/runs/\(trainNumber)/\(originDate)/rake-working",
            query: ["include": "geometry"]
        )
    }

    public func networkTrains(bounds: NetworkBounds) async throws -> NetworkTrainsResponse {
        let serialized = try NetworkBoundsLogic.serialize(bounds)
        return try await client.get("/v1/network/trains", query: ["bounds": serialized])
    }

    public func trainHistory(trainNumber: String, limit: Int = 20) async throws -> TrainHistoryResponse {
        try await client.get("/v1/trains/\(trainNumber)/history", query: ["limit": String(limit)])
    }
}

/// Bounds normalization — ported from `src/domain/operations.ts`.
public enum NetworkBoundsLogic {
    public static func normalize(_ bounds: NetworkBounds) throws -> NetworkBounds {
        let values = [bounds.west, bounds.south, bounds.east, bounds.north]
        guard values.allSatisfy({ $0.isFinite }) else { throw BoundsError.notFinite }
        let normalized = NetworkBounds(
            west: max(-180, min(180, bounds.west)),
            south: max(-90, min(90, bounds.south)),
            east: max(-180, min(180, bounds.east)),
            north: max(-90, min(90, bounds.north))
        )
        guard normalized.west < normalized.east, normalized.south < normalized.north else {
            throw BoundsError.degenerate
        }
        return normalized
    }

    public static func serialize(_ bounds: NetworkBounds) throws -> String {
        let normalized = try normalize(bounds)
        return "\(normalized.west),\(normalized.south),\(normalized.east),\(normalized.north)"
    }

    public enum BoundsError: Error { case notFinite, degenerate }
}

// MARK: - Data mode (preview vs production)

public enum RailDataMode: Sendable {
    case preview
    case production(baseURL: URL)

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> RailDataMode {
        let raw = environment["LOCOMOTE_RAIL_API_URL"]
            ?? environment["EXPO_PUBLIC_RAIL_API_URL"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "LocomoteRailAPIURL") as? String)
        guard let raw, !raw.isEmpty,
              let url = try? RailAPIURL.validate(raw, development: isDebug) else {
            return .preview
        }
        return .production(baseURL: url)
    }

    private static var isDebug: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    public var isProduction: Bool {
        if case .production = self { return true }
        return false
    }
}

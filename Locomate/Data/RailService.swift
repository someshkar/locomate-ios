//
//  RailService.swift
//  Locomate
//
//  Typed rail endpoints — mirrors SmartRail `src/services/railData.ts`
//  (searchTrains, fetchJourney, fetchOperationalChain, fetchNetwork, history).
//

import Foundation
import CryptoKit

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
    public let sourceUpdatedAt: String?
    public let live: Bool
    public var originDate: String? = nil
    public var boardingDay: Int? = nil
    public var arrivalDay: Int? = nil
}

private struct TrainSearchResponse: Decodable {
    let trains: [TrainSearchResult]
}

private struct JourneyResponse: Decodable {
    let journey: Journey
}

public protocol RailServiceProtocol: JourneyAlertAPI {
    func recordCommunityConsent(_ evidence: CommunityConsentEvidence) async throws
    func exportPrivacyData() async throws -> Data
    func deletePrivacyData() async throws
    func registerLiveActivityToken(
        runId: String, token: String, state: JourneyActivityAttributes.ContentState
    ) async throws
    func unregisterLiveActivity(runId: String) async throws
    func uploadObservations(_ batch: [CompactObservation]) async throws -> [String]
    func searchTrains(_ query: String) async throws -> [TrainSearchResult]
    func searchStations(_ query: String) async throws -> [StationSearchResult]
    func stationTrains(_ code: String) async throws -> StationTrainsResult
    func trainsBetween(from: String, to: String, travelDate: String) async throws -> BetweenStationsResult
    func journey(trainNumber: String, originDate: String) async throws -> Journey
    func operationalChain(trainNumber: String, originDate: String) async throws -> OperationalChainResponse
    func networkTrains(bounds: NetworkBounds) async throws -> NetworkTrainsResponse
    func trainHistory(trainNumber: String, limit: Int) async throws -> TrainHistoryResponse
}

public struct RailService: RailServiceProtocol {
    private let client: APIClient

    public init(client: APIClient) { self.client = client }

    public func registerJourneyAlerts(_ request: JourneyAlertRegistration) async throws -> JourneyAlertAcknowledgement {
        try await client.postData("/v1/journey-alerts/subscriptions", bodyData: JSONEncoder().encode(request))
    }

    public func unregisterJourneyAlerts(runId: String, revision: Int64) async throws {
        guard JourneyAlertIdentity.parse(runId) != nil else { throw JourneyAlertError.invalidJourney }
        try await client.delete("/v1/journey-alerts/subscriptions/\(runId)", query: ["revision": String(revision)])
    }

    public func recordCommunityConsent(_ evidence: CommunityConsentEvidence) async throws {
        struct Ack: Decodable { let recorded: Bool }
        let ack: Ack = try await client.post("/v1/privacy/consent", body: [
            "evidenceId": evidence.evidenceId,
            "purpose": evidence.purpose,
            "decision": evidence.decision,
            "consentVersion": evidence.consentVersion,
            "noticeHash": evidence.noticeHash,
            "recordedAt": evidence.recordedAt,
        ])
        guard ack.recorded else { throw URLError(.badServerResponse) }
    }

    public func exportPrivacyData() async throws -> Data {
        try await client.getRaw("/v1/privacy/export")
    }

    public func deletePrivacyData() async throws {
        try await client.delete("/v1/privacy/installation")
    }

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
        struct Response: Decodable { let acceptedRecordIds: [Int] }
        let encoded = try ObservationBatchCodec.encode(batch)
        let response: Response = try await client.postData(
            "/v1/observations/batch",
            bodyData: encoded.bodyData,
            idempotencyKey: encoded.idempotencyKey
        )
        return response.acceptedRecordIds.compactMap { encoded.keysById[$0] }
    }

    public func searchStations(_ query: String) async throws -> [StationSearchResult] {
        struct Response: Decodable { let stations: [StationSearchResult] }
        let response: Response = try await client.get("/v1/stations/search", query: ["q": query])
        guard response.stations.count <= 50, response.stations.allSatisfy({
            $0.code.range(of: "^[A-Z]{1,10}$", options: .regularExpression) != nil && !$0.name.isEmpty
        }) else { throw URLError(.badServerResponse) }
        return response.stations
    }

    public func stationTrains(_ code: String) async throws -> StationTrainsResult {
        guard code.range(of: "^[A-Z]{1,10}$", options: .regularExpression) != nil else { throw URLError(.badURL) }
        let response: StationTrainsResult = try await client.get("/v1/stations/\(code)/trains")
        guard response.station.code == code, response.trains.count <= 1000,
              response.trains.allSatisfy({ Routes.isValidTrainNumber($0.number) && !$0.name.isEmpty && !$0.live })
        else { throw URLError(.badServerResponse) }
        return response
    }

    public func trainsBetween(from: String, to: String, travelDate: String) async throws -> BetweenStationsResult {
        guard from.range(of: "^[A-Z]{1,10}$", options: .regularExpression) != nil,
              to.range(of: "^[A-Z]{1,10}$", options: .regularExpression) != nil,
              from != to, IndiaDate.isValid(travelDate) else { throw URLError(.badURL) }
        let response: BetweenStationsResult = try await client.get("/v1/trains/between", query: [
            "from": from, "to": to, "date": travelDate
        ])
        guard response.from.code == from, response.to.code == to, response.trains.count <= 1000,
              response.trains.allSatisfy({ Routes.isValidTrainNumber($0.number) && !$0.live &&
                  ($0.originDate.map(IndiaDate.isValid) ?? false) && ($0.boardingDay ?? 0) > 0 && ($0.arrivalDay ?? 0) > 0 })
        else { throw URLError(.badServerResponse) }
        return response
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

/// Exact v1 tuple contract consumed by the gateway observation decoder.
enum ObservationBatchCodec {
    struct Encoded {
        let body: [String: Any]
        let bodyData: Data
        let keysById: [Int: String]
        let idempotencyKey: String
    }

    enum EncodingError: Error { case invalidBatch, duplicateLocalId }

    static func localId(for item: CompactObservation) -> Int {
        let digest = SHA256.hash(data: Data("\(item.runId):\(item.timestamp)".utf8))
        // 48 bits remain exact in JavaScript numbers and fit SQLite INTEGER.
        return digest.prefix(6).reduce(0) { ($0 << 8) | Int($1) }
    }

    static func encode(_ batch: [CompactObservation]) throws -> Encoded {
        guard !batch.isEmpty, batch.count <= 100 else { throw EncodingError.invalidBatch }
        let ordered = batch.sorted { $0.timestamp < $1.timestamp }
        guard let first = ordered.first else { throw EncodingError.invalidBatch }
        var previous = first
        var keysById: [Int: String] = [:]
        var tuples: [[Any]] = []
        for (index, item) in ordered.enumerated() {
            guard item.consentVersion == Consent.version,
                  item.runId.range(of: "^[A-Za-z0-9:_.-]{1,128}$", options: .regularExpression) != nil
            else { throw EncodingError.invalidBatch }
            let id = localId(for: item)
            guard keysById[id] == nil else { throw EncodingError.duplicateLocalId }
            keysById[id] = "\(item.runId):\(item.timestamp)"
            tuples.append([
                id, item.runId, item.consentVersion,
                index == 0 ? 0 : item.timestamp - previous.timestamp,
                index == 0 ? 0 : item.latE5 - previous.latE5,
                index == 0 ? 0 : item.lonE5 - previous.lonE5,
                Int((item.speedKph * 10).rounded()),
                Int((item.accuracyM * 10).rounded()),
                Int((item.routeProgress * 1_000_000).rounded()),
                Int((item.matchDistanceM * 10).rounded()),
            ])
            previous = item
        }
        let body: [String: Any] = [
            "version": 1,
            "base": [first.timestamp, first.latE5, first.lonE5],
            "observations": tuples,
        ]
        let payload = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        return Encoded(body: body, bodyData: payload, keysById: keysById,
            idempotencyKey: "observations-\(digest)")
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

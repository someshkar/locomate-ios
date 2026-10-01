//
//  Models.swift
//  Locomate
//
//  Domain models — ported from SmartRail `src/domain/types.ts` and
//  `src/domain/operations.ts`. Field names and optionality mirror the API
//  contract so decoding stays faithful to the gateway.
//

import Foundation

// MARK: - Enumerations

public enum DataSource: String, Codable, Sendable {
    case device, community, predicted, official, scheduled
}

public enum Confidence: String, Codable, Sendable {
    case high, medium, low
}

public enum StopState: String, Codable, Sendable {
    case passed, current, upcoming
}

public enum TrainPhase: String, Codable, Sendable {
    case running, approaching, dwelling
}

public enum DelayStatus: String, Codable, Sendable {
    case observed, estimated, stale, scheduled, unavailable
}

public enum StopForecastSource: String, Codable, Sendable {
    case observed, empirical, baseline
    case physicalTransition = "physical-transition"
    case unavailable
}

public enum StopForecastFallbackReason: String, Codable, Sendable {
    case insufficientGroupSupport = "insufficient-group-support"
    case noReleasedEmpiricalGroup = "no-released-empirical-group"
    case currentDelayUnknown = "current-delay-unknown"
}

public enum StopForecastExplanationCode: String, Codable, Sendable {
    case actualEventObserved = "actual-event-observed"
    case releasedEmpiricalResidual = "released-empirical-residual"
    case currentDelayBaseline = "current-delay-baseline"
    case currentDelayUnknown = "current-delay-unknown"
    case insufficientGroupSupport = "insufficient-group-support"
    case noReleasedEmpiricalGroup = "no-released-empirical-group"
    case continuityConfirmed = "continuity-confirmed"
    case continuityUnverified = "continuity-unverified"
    case transitionAfterDepartureIgnored = "transition-after-departure-ignored"
    case physicalTransitionBinding = "physical-transition-binding"
    case serviceReadinessBinding = "service-readiness-binding"
    case rakeReadinessBinding = "rake-readiness-binding"
    case locoReadinessBinding = "loco-readiness-binding"
    case swapRiskApplied = "swap-risk-applied"
}

public enum ForecastFreshness: Sendable { case live, stale, predicted, scheduled }

// MARK: - Forecast

public protocol StopForecastProtocol: Sendable {
    var featureAsOf: String { get }
    var support: Double { get }
    var explanationCodes: [StopForecastExplanationCode] { get }
    var isAvailable: Bool { get }
}

public struct AvailableStopForecast: Codable, Sendable {
    public let availability: String // "available"
    public let p10: String
    public let p50: String
    public let p90: String
    public let source: StopForecastSource
    public let modelName: String
    public let modelReleaseId: String?
    public let modelVersion: String
    public let fallbackReason: StopForecastFallbackReason?
    public let featureAsOf: String
    public let support: Double
    public let explanationCodes: [StopForecastExplanationCode]

    public var isAvailable: Bool { true }
}

public struct UnavailableStopForecast: Codable, Sendable {
    public let availability: String // "unavailable"
    public let p10: String?
    public let p50: String?
    public let p90: String?
    public let source: StopForecastSource
    public let modelName: String?
    public let modelReleaseId: String?
    public let modelVersion: String?
    public let fallbackReason: StopForecastFallbackReason?
    public let featureAsOf: String
    public let support: Double
    public let explanationCodes: [StopForecastExplanationCode]

    public var isAvailable: Bool { false }
}

/// Mirrors the TS discriminated union `StopForecast = Available | Unavailable`.
public enum StopForecast: Sendable {
    case available(AvailableStopForecast)
    case unavailable(UnavailableStopForecast)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var featureAsOf: String {
        switch self {
        case .available(let value): return value.featureAsOf
        case .unavailable(let value): return value.featureAsOf
        }
    }

    public var support: Double {
        switch self {
        case .available(let value): return value.support
        case .unavailable(let value): return value.support
        }
    }

    public var explanationCodes: [StopForecastExplanationCode] {
        switch self {
        case .available(let value): return value.explanationCodes
        case .unavailable(let value): return value.explanationCodes
        }
    }

    public var source: StopForecastSource {
        switch self {
        case .available(let value): return value.source
        case .unavailable(let value): return value.source
        }
    }

    public var fallbackReason: StopForecastFallbackReason? {
        switch self {
        case .available(let value): return value.fallbackReason
        case .unavailable(let value): return value.fallbackReason
        }
    }

    public var modelLabel: String? {
        switch self {
        case .available(let value): return "\(value.modelName) \(value.modelVersion)"
        case .unavailable: return nil
        }
    }
}

extension StopForecast: Codable {
    private enum CodingKeys: String, CodingKey {
        case availability
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let availability = try container.decode(String.self, forKey: .availability)
        if availability == "available" {
            self = .available(try AvailableStopForecast(from: decoder))
        } else {
            self = .unavailable(try UnavailableStopForecast(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .available(let value): try value.encode(to: encoder)
        case .unavailable(let value): try value.encode(to: encoder)
        }
    }
}

// MARK: - Provenance

public struct DataProvenance: Codable, Sendable {
    public let provider: String
    public let providerLabel: String
    public let observedAt: String
    public let ingestedAt: String
    public let transformationVersion: String
    public let freshness: String
    public let attribution: String
}

// MARK: - Stops

public struct StationStop: Codable, Sendable, Identifiable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let distanceKm: Double
    public let scheduledArrival: String
    public let scheduledDeparture: String?
    public let predictedArrival: String
    public let actualArrival: String?
    public let actualDeparture: String?
    public let platform: String?
    public let delayMinutes: Int?
    public let arrivalDelayMinutes: Int?
    public let departureDelayMinutes: Int?
    public let delayStatus: DelayStatus?
    public let timingSource: DataSource?
    public let observedAt: String?
    public let state: StopState
    public let progress: Double
    public let forecast: StopForecast?

    public var knownPlatform: String? {
        guard let value = platform?.trimmingCharacters(in: .whitespaces),
              !value.isEmpty, value != "-", value != "—" else { return nil }
        return value
    }
}

// MARK: - Prediction

public struct Prediction: Codable, Sendable {
    public let expectedTime: String?
    public let lowerBound: String?
    public let upperBound: String?
    public let delayMinutes: Int?
    public let delayStatus: DelayStatus?
    public let confidence: Confidence
    public let confidenceScore: Double
    public let modelVersion: String
    public let leadMinutes: Int
    public let reasons: [String]
    public let source: DataSource
    public let updatedSecondsAgo: Int
}

// MARK: - Position & adjacent trains

public struct TrainPosition: Codable, Sendable {
    public let progress: Double
    public let speedKph: Double
    public let phase: TrainPhase
    public let previousStation: String
    public let nextStation: String
    public let distanceToNextKm: Double
    public let observedAt: Double
    public let source: DataSource
    public let confidence: Confidence
}

public struct NearbyTrain: Codable, Sendable {
    public let number: String
    public let progress: Double
    public let direction: Int
    public let status: String
}

// MARK: - Journey

public struct RailCoordinate: Codable, Sendable, Equatable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct Journey: Codable, Sendable, Identifiable {
    public let id: String
    public let trainNumber: String
    public let trainName: String
    public let originCode: String
    public let originName: String
    public let destinationCode: String
    public let destinationName: String
    public let departureTime: String
    public let scheduledArrival: String
    public let predictedArrival: String
    public let coach: String
    public let seat: String
    public let travelDate: String
    public let distanceKm: Double
    public let scheduledDurationMinutes: Int?
    public let completion: Double
    public let stops: [StationStop]
    public let prediction: Prediction
    public let position: TrainPosition
    public let nearbyTrains: [NearbyTrain]
    public let routeCoordinates: [RailCoordinate]?
    public let provenance: DataProvenance?
}

// MARK: - Operational chain (network / rake-working)

public struct NetworkBounds: Sendable, Equatable {
    public var west: Double
    public var south: Double
    public var east: Double
    public var north: Double
    public init(west: Double, south: Double, east: Double, north: Double) {
        self.west = west; self.south = south; self.east = east; self.north = north
    }
}

public enum NetworkPositionKind: String, Codable, Sendable {
    case observed
    case mapMatched = "map-matched"
    case interpolated
    case predicted
}

public struct NetworkTrain: Codable, Sendable, Identifiable {
    public var id: String { runId }
    public let runId: String
    public let originDate: String
    public let trainNumber: String
    public let name: String
    public let coordinate: RailCoordinate
    public let bearingDegrees: Double
    public let observedAt: String
    public let source: DataSource
    public let confidence: Confidence
    public let delayMinutes: Int?
    public let delayStatus: DelayStatus
    public let originCode: String
    public let destinationCode: String
    public let positionKind: NetworkPositionKind
    public let provenance: DataProvenance?
}

public struct NetworkTrainsResponse: Codable, Sendable {
    public let trains: [NetworkTrain]
    public let generatedAt: String
    public let freshUntil: String
}

public struct RoutePolyline: Codable, Sendable {
    public let coordinates: [RailCoordinate]
    public let source: String
}

public struct OperationalPosition: Codable, Sendable {
    public let coordinate: RailCoordinate
    public let progress: Double
    public let observedAt: String
    public let source: DataSource
}

public struct OperationalRun: Codable, Sendable, Identifiable {
    public let id: String
    public let role: String
    public let trainNumber: String
    public let trainName: String
    public let originCode: String
    public let destinationCode: String
    public let scheduledDeparture: String
    public let scheduledArrival: String
    public let actualDeparture: String?
    public let actualArrival: String?
    public let predictedArrival: String?
    public let geometry: RoutePolyline
    public let position: OperationalPosition?
}

public struct LinkageClaim: Codable, Sendable {
    public let claim: String
    public let confidence: Confidence
    public let method: String
    public let caveats: [String]
}

public struct DelayEvidence: Codable, Sendable, Identifiable {
    public let id: String
    public let kind: String
    public let summary: String
    public let delayMinutes: Int?
    public let observedAt: String?
    public let source: DataSource
}

public struct DelayAssessment: Codable, Sendable {
    public let incomingDelayMinutes: Int
    public let confidence: Confidence
    public let summary: String
    public let evidence: [DelayEvidence]
}

public struct PropagatedDelay: Codable, Sendable {
    public let fromRunId: String
    public let toRunId: String
    public let minutes: Int
    public let explanation: String
    public let evidenceIds: [String]
}

public struct TurnaroundRisk: Codable, Sendable {
    public let level: String
    public let scheduledMinutes: Int
    public let availableMinutes: Int
    public let minimumMinutes: Int
    public let summary: String
}

public struct OperationalChainResponse: Codable, Sendable {
    public let trainNumber: String
    public let originDate: String
    public let availability: String
    public let mode: String
    public let disclaimer: String
    public let previous: OperationalRun?
    public let current: OperationalRun?
    public let next: OperationalRun?
    public let linkage: LinkageClaim?
    public let delayAssessment: DelayAssessment?
    public let propagatedDelay: PropagatedDelay?
    public let turnaroundRisk: TurnaroundRisk?
    public let updatedAt: String
}

// MARK: - Train history

public enum TrainHistoryClassification: String, Codable, Sendable {
    case early
    case onTime = "on-time"
    case late, cancelled, unknown
}

public struct TrainHistoryCounts: Codable, Sendable {
    public let early: Int
    public let onTime: Int
    public let late: Int
    public let cancelled: Int
    public let unknown: Int
    public let total: Int
}

public struct HistoricalTrainRun: Codable, Sendable, Identifiable {
    public var id: String { runId }
    public let runId: String
    public let serviceDate: String
    public let status: String
    public let destination: StationRef
    public let scheduledArrival: String?
    public let actualArrival: String?
    public let delayMinutes: Int?
    public let classification: TrainHistoryClassification
}

public struct StationRef: Codable, Sendable {
    public let code: String
    public let name: String
}

public struct TrainHistorySummary: Codable, Sendable {
    public struct Percentages: Codable, Sendable {
        public let early: Double?
        public let onTime: Double?
        public let late: Double?
    }
    public struct Coverage: Codable, Sendable {
        public let from: String
        public let to: String
    }
    public let counts: TrainHistoryCounts
    public let denominator: Int
    public let percentages: Percentages
    public let coverage: Coverage?
    public let lowSample: Bool
}

public struct TrainHistoryResponse: Codable, Sendable {
    public let trainNumber: String
    public let summary: TrainHistorySummary
    public let generatedAt: String
    public let runs: [HistoricalTrainRun]
}

import Foundation

public struct StationSearchResult: Codable, Equatable, Identifiable, Sendable {
    public var id: String { code }
    public let code: String
    public let name: String
    public let sourceLabel: String
    public let sourceUpdatedAt: String?
}

public struct StationTrainsResult: Decodable, Sendable {
    public let station: StationSearchResult
    public let trains: [TrainSearchResult]
    public let truncated: Bool
}

// Fixed catalogue shortcuts from the approved Search design; they do not imply live services.
enum StationSearch {
    static let shortcuts = [("NDLS", "New Delhi"), ("MMCT", "Mumbai Central"), ("KOTA", "Kota Jn"), ("BRC", "Vadodara Jn")]
        .map { StationSearchResult(code: $0.0, name: $0.1, sourceLabel: "Station shortcut", sourceUpdatedAt: nil) }

    static var previewStations: [StationSearchResult] {
        var seen = Set<String>()
        return RoutePackStore.packs.flatMap(\.calls).filter { seen.insert($0.code).inserted }
            .map { StationSearchResult(code: $0.code, name: $0.name, sourceLabel: "Historical route pack", sourceUpdatedAt: nil) }
            .sorted { $0.code < $1.code }
    }

    static func previewTrain(_ pack: OpenRoutePack) -> TrainSearchResult {
        TrainSearchResult(number: pack.trainNumber, name: pack.name,
            originCode: pack.originCode, originName: pack.originName,
            destinationCode: pack.destinationCode, destinationName: pack.destinationName,
            departure: String(pack.departure.prefix(5)), arrival: String(pack.arrival.prefix(5)),
            durationHours: Double(pack.durationMinutes) / 60, distanceKm: pack.distanceKm,
            sourceLabel: "Historical route pack", sourceUpdatedAt: "", live: false)
    }
}

// Unrelated test services need not supply a station catalogue. An unsupported service is an error,
// never an empty successful station search; the concrete gateway client implements both methods.
public extension RailServiceProtocol {
    func searchStations(_ query: String) async throws -> [StationSearchResult] { throw URLError(.unsupportedURL) }
    func stationTrains(_ code: String) async throws -> StationTrainsResult { throw URLError(.unsupportedURL) }
}

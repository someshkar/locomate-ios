import Foundation
import Observation

/// Local train choices, never a saved run status. Each gateway and preview has its own history.
@MainActor @Observable
public final class RecentTrainStore {
    private struct Record: Codable {
        let number: String
        let name: String
        let originCode: String
        let originName: String
        let destinationCode: String
        let destinationName: String
        let sourceLabel: String
        let distanceKm: Double

        init(_ train: TrainSearchResult) {
            number = train.number; name = train.name
            originCode = train.originCode; originName = train.originName
            destinationCode = train.destinationCode; destinationName = train.destinationName
            sourceLabel = train.sourceLabel
            distanceKm = train.distanceKm.isFinite && train.distanceKm >= 0 ? train.distanceKm : 0
        }

        var train: TrainSearchResult {
            TrainSearchResult(number: number, name: name, originCode: originCode, originName: originName,
                destinationCode: destinationCode, destinationName: destinationName, departure: "", arrival: "",
                durationHours: 0, distanceKm: distanceKm, sourceLabel: sourceLabel,
                sourceUpdatedAt: "", live: false)
        }
    }

    public enum StorageError: Error { case invalidTrain, deletionPending }
    public private(set) var trains: [TrainSearchResult] = []
    private let file: URL
    private let privacyDeletionPending: () -> Bool
    private var invalidated = false

    public init(directory: URL? = nil, scope: String,
                privacyDeletionPending: @escaping () -> Bool = { PrivacyDeletionLatch.isPending }) {
        file = (directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("locomote", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
            .appendingPathComponent("recent-trains.json")
        self.privacyDeletionPending = privacyDeletionPending
        guard !privacyDeletionPending(), let data = try? Data(contentsOf: file),
              let records = try? JSONDecoder().decode([Record].self, from: data) else { return }
        var seen = Set<String>()
        trains = records.filter { Self.valid($0.train) && seen.insert($0.number).inserted }
            .prefix(10).map(\.train)
        excludeFromBackup(file)
    }

    public func record(_ train: TrainSearchResult) throws {
        guard !invalidated, !privacyDeletionPending() else { throw StorageError.deletionPending }
        guard Self.valid(train) else { throw StorageError.invalidTrain }
        let next = [Record(train).train] + trains.filter { $0.number != train.number }
        try persist(Array(next.prefix(10)))
    }

    public func clear() throws {
        guard !invalidated, !privacyDeletionPending() else { throw StorageError.deletionPending }
        try persist([])
    }

    /// A dismissed view cannot recreate history after privacy erasure completes.
    public func beginPrivacyDeletion() { invalidated = true; trains = [] }

    private static func valid(_ train: TrainSearchResult) -> Bool {
        Routes.isValidTrainNumber(train.number) && !train.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func persist(_ next: [TrainSearchResult]) throws {
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup(directory)
        try JSONEncoder().encode(next.map(Record.init)).write(to: file, options: .atomic)
        excludeFromBackup(file)
        trains = next
    }
}

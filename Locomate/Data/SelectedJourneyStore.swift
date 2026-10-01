import Foundation

/// A route reference is durable user state, separate from the evictable run
/// cache. Keeping it under the private scope also includes it in export/erasure.
@MainActor
public final class SelectedJourneyStore {
    private struct Record: Codable {
        let trainNumber: String
        let originDate: String
    }
    public enum StorageError: Error { case invalidDestination, deletionPending }

    private let file: URL
    private let privacyDeletionPending: () -> Bool
    private var invalidated = false

    public init(directory: URL? = nil, scope: String,
                privacyDeletionPending: @escaping () -> Bool = { PrivacyDeletionLatch.isPending }) {
        let root = (directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
            .appendingPathComponent("locomote", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
        self.file = root.appendingPathComponent("selected-journey.json")
        self.privacyDeletionPending = privacyDeletionPending
    }

    public func load() -> Routes.JourneyDestination? {
        guard !invalidated, !privacyDeletionPending(),
              let data = try? Data(contentsOf: file),
              let record = try? JSONDecoder().decode(Record.self, from: data),
              Routes.isValidTrainNumber(record.trainNumber),
              Routes.isValidCalendarDate(record.originDate) else { return nil }
        return .init(trainNumber: record.trainNumber, date: record.originDate)
    }

    public func save(_ destination: Routes.JourneyDestination) throws {
        guard !invalidated, !privacyDeletionPending() else { throw StorageError.deletionPending }
        guard Routes.isValidTrainNumber(destination.trainNumber), Routes.isValidCalendarDate(destination.date) else {
            throw StorageError.invalidDestination
        }
        let directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        excludeFromBackup(directory)
        let data = try JSONEncoder().encode(Record(trainNumber: destination.trainNumber, originDate: destination.date))
        try data.write(to: file, options: .atomic)
        excludeFromBackup(file)
    }

    /// An old view/service cannot recreate erased selection data after an await.
    public func beginPrivacyDeletion() { invalidated = true }
}

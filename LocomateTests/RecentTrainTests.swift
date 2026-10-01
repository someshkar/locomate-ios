import Foundation
import Testing
@testable import Locomate

@Suite("Private recent train choices") @MainActor
struct RecentTrainTests {
    private func train(_ number: String, name: String = "Long Complete Train Name") -> TrainSearchResult {
        .init(number: number, name: name, originCode: "NDLS", originName: "New Delhi",
            destinationCode: "MMCT", destinationName: "Mumbai Central", departure: "16:00", arrival: "08:00",
            durationHours: 16, distanceKm: 1384, sourceLabel: "Historical railway snapshot",
            sourceUpdatedAt: "2026-10-02T00:00:00Z", live: true)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test("reselection updates and moves the train first, bounds history and drops run evidence")
    func boundedRoundTrip() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RecentTrainStore(directory: root, scope: "a", privacyDeletionPending: { false })
        for number in 12000...12011 { try store.record(train(String(number))) }
        try store.record(train("12003", name: "Updated full name"))
        let reopened = RecentTrainStore(directory: root, scope: "a", privacyDeletionPending: { false })
        #expect(reopened.trains.count == 10)
        #expect(reopened.trains.first?.number == "12003")
        #expect(reopened.trains.first?.name == "Updated full name")
        #expect(reopened.trains.first?.sourceLabel == "Historical railway snapshot")
        #expect(reopened.trains.first?.originName == "New Delhi")
        #expect(reopened.trains.allSatisfy { !$0.live && $0.departure.isEmpty && $0.arrival.isEmpty && $0.sourceUpdatedAt.isEmpty })
        let data = try Data(contentsOf: root.appendingPathComponent("locomote/a/recent-trains.json"))
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("originDate") && !text.contains("sourceUpdatedAt") && !text.contains("\"live\""))
        #expect(throws: RecentTrainStore.StorageError.self) { try store.record(train("bad")) }
        try store.clear()
        #expect(RecentTrainStore(directory: root, scope: "a", privacyDeletionPending: { false }).trains.isEmpty)
    }

    @Test("gateway and preview scopes are separate and private files participate in export")
    func scopeExportAndBackup() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try RecentTrainStore(directory: root, scope: "a", privacyDeletionPending: { false }).record(train("01234"))
        #expect(RecentTrainStore(directory: root, scope: "b", privacyDeletionPending: { false }).trains.isEmpty)
        #expect(RecentTrainStore(directory: root, scope: "preview", privacyDeletionPending: { false }).trains.isEmpty)
        let file = root.appendingPathComponent("locomote/a/recent-trains.json")
        #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let export = try LocomoteServices.exportLocalFilesBase64(documentRoot: root.appendingPathComponent("locomote"),
            cacheRoot: root.appendingPathComponent("unused"))
        #expect(export["Documents/locomote/a/recent-trains.json"] == (try Data(contentsOf: file)).base64EncodedString())
    }

    @Test("pending and completed privacy erasure block an old store from recreating history")
    func deletionBoundary() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var pending = false
        let store = RecentTrainStore(directory: root, scope: "a", privacyDeletionPending: { pending })
        try store.record(train("01234"))
        pending = true
        #expect(RecentTrainStore(directory: root, scope: "a", privacyDeletionPending: { pending }).trains.isEmpty)
        #expect(throws: RecentTrainStore.StorageError.self) { try store.record(train("12951")) }
        store.beginPrivacyDeletion()
        try FileManager.default.removeItem(at: root)
        pending = false
        #expect(store.trains.isEmpty)
        #expect(throws: RecentTrainStore.StorageError.self) { try store.record(train("12951")) }
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}

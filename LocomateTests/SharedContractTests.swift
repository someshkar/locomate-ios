import Foundation
import CryptoKit
import Testing
@testable import Locomate

private final class SharedFixtureAnchor: NSObject {}
@Suite("Shared native/backend journey corpus")
struct SharedContractTests {
    struct Manifest: Decodable {
        struct Case: Decodable {
            struct Request: Decodable { let trainNumber: String; let originDate: String }
            let file: String; let sha256: String; let request: Request; let accepted: Bool
        }
        let cases: [Case]
    }
    private func data(_ file: String) throws -> Data {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        let bundle = Bundle(for: SharedFixtureAnchor.self)
        let url = try #require(bundle.url(forResource: name, withExtension: ext, subdirectory: "rail-api-v1")
            ?? bundle.url(forResource: name, withExtension: ext))
        return try Data(contentsOf: url)
    }
    @Test("all canonical identity cases match the shared acceptance policy and exact bytes")
    func corpus() async throws {
        let manifest = try JSONDecoder().decode(Manifest.self, from: data("manifest.json"))
        #expect(manifest.cases.count == 9)
        struct Envelope: Decodable { let journey: Journey }
        for item in manifest.cases {
            let bytes = try data(item.file)
            #expect(SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == item.sha256)
            let journey = try JSONDecoder.locomote.decode(Envelope.self, from: bytes).journey
            let accepted = (try? JourneyIdentity.validate(journey, trainNumber: item.request.trainNumber,
                originDate: item.request.originDate)) != nil
            #expect(accepted == item.accepted, "\(item.file)")
            if item.file == "journey-fractional.json" {
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at: directory) }
                let cache = JourneyCache(directory: directory)
                await cache.saveJourney(journey, originDate: item.request.originDate)
                let saved = try #require(await cache.loadJourney(trainNumber: item.request.trainNumber,
                    originDate: item.request.originDate))
                #expect(saved.journey.prediction.delayMinutes == journey.prediction.delayMinutes)
                #expect(saved.journey.scheduledDurationMinutes == journey.scheduledDurationMinutes)
                #expect(saved.journey.stops[1].arrivalDelayMinutes == journey.stops[1].arrivalDelayMinutes)
            }
        }
    }
}

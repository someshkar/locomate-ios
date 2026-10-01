import Foundation
import Testing
@testable import Locomate

/// Run with LOCOMOTE_LOCAL_GATEWAY_URL=http://127.0.0.1:8787 after starting
/// Wrangler locally. CI skips this because current public-feed data is external.
@Suite(
    "Local gateway integration",
    .enabled(if: ProcessInfo.processInfo.environment["LOCOMOTE_LOCAL_GATEWAY_URL"]?
        .hasPrefix("http://127.0.0.1:") == true)
)
struct LocalGatewayIntegrationTests {
    @Test("native service decodes current search, journey, and network responses")
    func currentPublicFeed() async throws {
        let rawURL = try #require(ProcessInfo.processInfo.environment["LOCOMOTE_LOCAL_GATEWAY_URL"])
        let baseURL = try RailAPIURL.validate(rawURL, development: true)
        let client = APIClient(
            baseURL: baseURL,
            tokenStore: InMemoryTokenStore(),
            installationId: UUID().uuidString
        )
        let service = RailService(client: client)
        let search = try await service.searchTrains("12137")
        #expect(search.contains { $0.number == "12137" })

        let journey = try await service.journey(trainNumber: "12137", originDate: IndiaDate.today())
        #expect(journey.trainNumber == "12137")
        #expect(journey.stops.count > 1)
        #expect(journey.routeCoordinates?.isEmpty == false)

        let network = try await service.networkTrains(
            bounds: NetworkBounds(west: 68, south: 7, east: 97, north: 36)
        )
        #expect(!network.trains.isEmpty)
    }
}

import Foundation
import Testing
@testable import Locomate

private final class PrivacyRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var blocked = false
    private var blockAfterAuthentication = false
    private var requests: [URLRequest] = []
    var pending: Bool { lock.withLock { blocked } }
    var urls: [URL] { lock.withLock { requests.compactMap(\.url) } }
    func reset(pending: Bool, blockAfterAuthentication: Bool = false) {
        lock.withLock { blocked = pending; self.blockAfterAuthentication = blockAfterAuthentication; requests = [] }
    }
    func respond(_ request: URLRequest) -> (Int, Data) {
        lock.withLock {
            requests.append(request)
            if request.url?.path == "/v1/auth/device-session" {
                if blockAfterAuthentication { blocked = true }
                return (200, Data(#"{"accessToken":"test-session","expiresIn":3600}"#.utf8))
            }
            return (204, Data())
        }
    }
}

private final class PrivacyRequestProtocol: URLProtocol, @unchecked Sendable {
    static let state = PrivacyRequestState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, data) = Self.state.respond(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Privacy request boundary", .serialized)
struct PrivacyRequestTests {
    private func client() -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PrivacyRequestProtocol.self]
        return APIClient(baseURL: URL(string: "https://privacy-test.invalid")!, tokenStore: InMemoryTokenStore(),
            installationId: "privacy-test", session: URLSession(configuration: configuration),
            privacyDeletionPending: { PrivacyRequestProtocol.state.pending })
    }

    @Test("explicit deletion can authenticate and reach the wire while all other requests are blocked")
    func deletionRetry() async throws {
        let state = PrivacyRequestProtocol.state
        state.reset(pending: true)
        let client = client()
        try await client.delete("/v1/privacy/installation")
        #expect(state.urls.map(\.path) == ["/v1/auth/device-session", "/v1/privacy/installation"])
        do {
            _ = try await client.getRaw("/v1/privacy/export")
            Issue.record("Expected pending-deletion guard")
        } catch let error as APIError { #expect(error.code == "privacy_deletion_pending") }
        #expect(state.urls.count == 2)
    }

    @Test("deletion beginning during authentication prevents the following ordinary request")
    func authenticationRace() async throws {
        let state = PrivacyRequestProtocol.state
        state.reset(pending: false, blockAfterAuthentication: true)
        do {
            _ = try await client().getRaw("/v1/network/trains")
            Issue.record("Expected guard after authentication resumed")
        } catch let error as APIError { #expect(error.code == "privacy_deletion_pending") }
        #expect(state.urls.map(\.path) == ["/v1/auth/device-session"])
    }

    @Test("alert deletion serializes revision as a query parameter")
    func revisionQuery() async throws {
        let state = PrivacyRequestProtocol.state
        state.reset(pending: false)
        try await client().delete("/v1/journey-alerts/subscriptions/12137:2026-10-01", query: ["revision": "123"])
        let url = try #require(state.urls.last)
        #expect(url.path == "/v1/journey-alerts/subscriptions/12137:2026-10-01")
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems == [URLQueryItem(name: "revision", value: "123")])
    }
}

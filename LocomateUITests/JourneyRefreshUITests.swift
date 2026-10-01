import XCTest
import Network

final class JourneyRefreshUITests: XCTestCase {
    @MainActor
    func testActiveSceneResumeRefreshesExactDatedRunWithoutConsent() async throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let ready = expectation(description: "Journey refresh gateway ready")
        let gateway = try JourneyRefreshGateway(fixture: Data(contentsOf: fixture), ready: ready)
        defer { gateway.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        app.launch()
        defer { app.terminate() }
        app.open(try XCTUnwrap(URL(string: "locomate://journeys/12137?date=2026-09-18")))
        XCTAssertTrue(app.staticTexts["12137 · Initial dated response"].waitForExistence(timeout: 10))
        let initialRequests = gateway.runRequests
        XCTAssertGreaterThanOrEqual(initialRequests, 1)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        gateway.useUpdatedResponse()
        // Cadence and cancellation timing are deterministic model tests. This
        // short real lifecycle check proves the production scene wiring.
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(gateway.runRequests, initialRequests)
        app.activate()
        XCTAssertTrue(app.staticTexts["12137 · Resumed dated response"].waitForExistence(timeout: 10))
        XCTAssertEqual(gateway.runRequests, initialRequests + 1)
        XCTAssertFalse(gateway.paths.contains { $0.contains("journey-alerts") || $0.contains("/privacy/consent") || $0.contains("observations") || $0.contains("live-activities") })
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Production dated Journey refreshed after resume"
        image.lifetime = .keepAlways
        add(image)
    }
}

/// Changes its returned snapshot only after the test backgrounds the app.
private final class JourneyRefreshGateway: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "JourneyRefreshGateway")
    private let lock = NSLock()
    private var requests: [String] = []
    private var updated = false
    private let journey: [String: Any]
    var paths: [String] { lock.withLock { requests } }
    var runRequests: Int { paths.filter { $0 == "/v1/runs/12137/2026-09-18" }.count }
    var baseURL: String? { listener.port.map { "http://127.0.0.1:\($0.rawValue)" } }
    func useUpdatedResponse() { lock.withLock { updated = true } }

    init(fixture: Data, ready: XCTestExpectation) throws {
        journey = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, data: Data())
        }
        listener.start(queue: queue)
    }
    func stop() { listener.cancel() }
    private func receive(_ connection: NWConnection, data accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            guard let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete || error != nil || buffer.count > 65536 { connection.cancel() }
                else { self.receive(connection, data: buffer) }
                return
            }
            let raw = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let path = String(raw.split(separator: "?").first ?? "")
            self.lock.withLock { self.requests.append(path) }
            let payload: [String: Any]
            let status: String
            if path == "/v1/auth/device-session" {
                payload = ["accessToken": "fixture-only", "expiresIn": 3600]; status = "200 OK"
            } else if path == "/v1/runs/12137/2026-09-18" {
                var envelope = self.journey
                var run = envelope["journey"] as! [String: Any]
                run["trainName"] = self.lock.withLock { self.updated ? "Resumed dated response" : "Initial dated response" }
                envelope["journey"] = run
                payload = envelope; status = "200 OK"
            } else {
                payload = ["error": ["code": "fixture_unavailable", "message": "Fixture unavailable."]]; status = "404 Not Found"
            }
            let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

import XCTest
import Network

final class ReliabilityHistoryUITests: XCTestCase {
    @MainActor
    func testInsightsRetriesRealHistoryAndShowsReadablePartialEvidence() async throws {
        continueAfterFailure = false
        let bundle = Bundle(for: Self.self)
        let runFile = try XCTUnwrap(bundle.url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let historyFile = try XCTUnwrap(bundle.url(forResource: "history-12137", withExtension: "json"))
        let ready = expectation(description: "History gateway ready")
        let gateway = try HistoryGateway(journey: Data(contentsOf: runFile), history: Data(contentsOf: historyFile), ready: ready)
        defer { gateway.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        defer { app.terminate() }
        app.open(try XCTUnwrap(URL(string: "locomate://journeys/12137?date=2026-09-18")))
        XCTAssertTrue(app.staticTexts["12137 · Punjab Mail"].waitForExistence(timeout: 10))
        openInsights(app)
        let error = app.staticTexts["reliability.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        reveal(error, app: app)
        XCTAssertEqual(gateway.historyRequests, 1)
        gateway.setMode(.populated)
        let retry = app.buttons["reliability.retry"]
        reveal(retry, app: app)
        retry.tap()
        let sample = app.staticTexts["reliability.sample"]
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        reveal(sample, app: app)
        XCTAssertEqual(sample.label, "Based on 5 recorded destination arrivals")
        let onTime = app.descendants(matching: .any)["reliability.metric.onTime"].firstMatch
        XCTAssertTrue(onTime.exists)
        XCTAssertTrue(onTime.label.contains("60%"))
        XCTAssertEqual(gateway.historyRequests, 2)
        capture(app, "Reliability history normal text after retry")
        app.terminate()

        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.staticTexts["12137 · Punjab Mail"].waitForExistence(timeout: 10))
        openInsights(app)
        XCTAssertTrue(sample.waitForExistence(timeout: 10))
        for id in ["reliability.metric.onTime", "reliability.sample", "reliability.exclusions",
                   "reliability.coverage", "reliability.lowSample", "reliability.disclosure"] {
            let element = app.descendants(matching: .any)[id].firstMatch
            reveal(element, app: app)
            capture(app, "Largest reliability \(id)")
        }
        XCTAssertEqual(app.staticTexts["reliability.exclusions"].label, "1 cancelled and 2 unknown runs excluded")
        XCTAssertEqual(app.staticTexts["reliability.coverage"].label, "Service dates: 2026-09-10 to 2026-09-18")
        XCTAssertTrue(app.staticTexts["reliability.generated"].label.hasPrefix("Report generated"))
        XCTAssertEqual(gateway.historyRequests, 3, "Scrolling and layout changes must not poll history.")

        // Matches the deployed zero-denominator/positive-total shape.
        gateway.setMode(.unknownOnly)
        reveal(retry, app: app)
        retry.tap()
        let empty = app.staticTexts["reliability.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        reveal(empty, app: app)
        XCTAssertEqual(empty.label, "Arrival timing percentages are unavailable for the recorded runs.")
        XCTAssertFalse(onTime.exists)
        let exclusions = app.staticTexts["reliability.exclusions"]
        reveal(exclusions, app: app)
        XCTAssertEqual(exclusions.label, "0 cancelled and 4 unknown runs excluded")
        XCTAssertEqual(app.staticTexts["reliability.coverage"].label, "Service dates: 2026-08-23 to 2026-09-08")
        capture(app, "Unknown-only history has no percentage")
        XCTAssertEqual(gateway.historyRequests, 4)
        XCTAssertTrue(gateway.historyURLs.allSatisfy { $0 == "/v1/trains/12137/history?limit=1" })
        XCTAssertFalse(gateway.paths.contains { $0.contains("journey-alerts") || $0.contains("/privacy/consent") || $0.contains("observations") || $0.contains("live-activities") })
    }

    @MainActor private func openInsights(_ app: XCUIApplication) {
        let expand = app.buttons["Expand journey details"]
        if expand.exists { expand.tap() }
        let insights = app.buttons["Insights"]
        XCTAssertTrue(insights.waitForExistence(timeout: 5))
        reveal(insights, app: app)
        insights.tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        func region() -> CGRect {
            let frame = scroll.frame
            let top = max(frame.minY, 64) + 8
            return CGRect(x: frame.minX, y: top, width: frame.width,
                          height: max(0, min(frame.maxY, app.buttons["Passport"].frame.minY - 12) - top))
        }
        for _ in 0..<30 {
            let reading = region()
            if element.exists && element.isHittable && reading.contains(element.frame) { return }
            let frame = element.frame
            let downward = frame.minY < reading.minY
            let overflow = downward ? reading.minY - frame.minY : frame.maxY - reading.maxY
            let distance = min(190, max(40, overflow + 12), max(40, reading.height - 48))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: reading.minX + 8, dy: reading.midY + (downward ? -distance / 2 : distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: reading.minX + 8, dy: reading.midY + (downward ? distance / 2 : -distance / 2)))
            start.press(forDuration: 0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(region().contains(element.frame), "The complete evidence text must fit the reading region: \(element.frame)")
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private final class HistoryGateway: @unchecked Sendable {
    enum Mode { case unavailable, populated, unknownOnly }
    private let listener: NWListener
    private let queue = DispatchQueue(label: "ReliabilityHistoryGateway")
    private let lock = NSLock()
    private var requests: [String] = []
    private var mode: Mode = .unavailable
    private let journey: [String: Any]
    private let history: [String: Any]
    var paths: [String] { lock.withLock { requests } }
    var historyURLs: [String] { paths.filter { $0.hasPrefix("/v1/trains/12137/history") } }
    var historyRequests: Int { historyURLs.count }
    var baseURL: String? { listener.port.map { "http://127.0.0.1:\($0.rawValue)" } }
    func setMode(_ mode: Mode) { lock.withLock { self.mode = mode } }

    init(journey: Data, history: Data, ready: XCTestExpectation) throws {
        self.journey = try XCTUnwrap(JSONSerialization.jsonObject(with: journey) as? [String: Any])
        self.history = try XCTUnwrap(JSONSerialization.jsonObject(with: history) as? [String: Any])
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
            self.lock.withLock { self.requests.append(raw) }
            var payload: [String: Any]
            var status = "200 OK"
            if path == "/v1/auth/device-session" {
                payload = ["accessToken": "fixture-only", "expiresIn": 3600]
            } else if path == "/v1/runs/12137/2026-09-18" {
                payload = self.journey
            } else if path == "/v1/trains/12137/history", self.lock.withLock({ self.mode != .unavailable }) {
                payload = self.history
                if self.lock.withLock({ self.mode == .unknownOnly }) {
                    payload["summary"] = [
                        "counts": ["early": 0, "onTime": 0, "late": 0, "cancelled": 0, "unknown": 4, "total": 4],
                        "denominator": 0, "percentages": ["early": NSNull(), "onTime": NSNull(), "late": NSNull()],
                        "coverage": ["from": "2026-08-23", "to": "2026-09-08"], "lowSample": true]
                    var row = (self.history["runs"] as! [[String: Any]])[0]
                    row["runId"] = "12137:2026-09-08"
                    row["serviceDate"] = "2026-09-08"
                    row["scheduledArrival"] = "2026-09-09T23:45:00.000Z"
                    row["actualArrival"] = NSNull()
                    row["delayMinutes"] = NSNull()
                    row["classification"] = "unknown"
                    row["source"] = ["schedule": "canonical-intelligence-tables", "actual": NSNull()]
                    payload["runs"] = [row]
                }
            } else {
                status = path.contains("history") ? "503 Service Unavailable" : "404 Not Found"
                payload = ["error": ["code": "fixture_unavailable", "message": "Fixture unavailable."]]
            }
            let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
            var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

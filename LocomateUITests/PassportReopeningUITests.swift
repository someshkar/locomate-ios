import XCTest
import Network

final class PassportReopeningUITests: XCTestCase {
    @MainActor
    func testSavedRowRestoresPersonalSegmentAndDeleteStaysIndependentAtLargestText() async throws {
        continueAfterFailure = false
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let ready = expectation(description: "Passport gateway ready")
        let gateway = try PassportReopeningGateway(fixture: Data(contentsOf: fixture), ready: ready)
        defer { gateway.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        app.open(try XCTUnwrap(URL(string: "locomate://journeys/12137?date=2026-09-18")))
        XCTAssertTrue(app.staticTexts["12137 · \(gateway.name)"].waitForExistence(timeout: 10))
        setPlan(app, boarding: "Dadar (DR)", alighting: "Kalyan Jn (KYN)")
        XCTAssertTrue(app.staticTexts["Dadar to Kalyan Jn"].waitForExistence(timeout: 5))
        expand(app)
        let save = app.buttons["Save"]
        reveal(save, in: app.scrollViews.firstMatch, app: app)
        save.tap()
        XCTAssertTrue(app.staticTexts["Journey saved privately on this device."].waitForExistence(timeout: 5))

        // Later edits to the working plan must not change the saved row's segment.
        app.open(try XCTUnwrap(URL(string: "locomate://journeys/12137?date=2026-09-18")))
        setPlan(app, boarding: "Mumbai CSMT (CSMT)", alighting: "Kasara (KSRA)")
        XCTAssertTrue(app.staticTexts["Mumbai CSMT to Kasara"].waitForExistence(timeout: 5))
        app.buttons["Passport"].tap()
        let name = app.staticTexts["passport.name.12137-2026-09-18"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        reveal(name, in: app.scrollViews["passport.content"], app: app)
        XCTAssertEqual(name.label, gateway.name)
        let normalHeight = name.frame.height
        capture(app, "Saved Passport row normal size")
        app.terminate()

        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        app.buttons["Passport"].tap()
        let page = app.scrollViews["passport.content"]
        for label in ["SAVED RUNS", "SCHEDULED", "STATIONS"] {
            let metric = app.staticTexts["passport.metric.\(label)"]
            XCTAssertTrue(metric.waitForExistence(timeout: 5))
            reveal(metric, in: page, app: app)
            XCTAssertEqual(metric.label, label)
            capture(app, "Passport largest text \(label)")
        }
        reveal(name, in: page, app: app)
        XCTAssertEqual(name.label, gateway.name)
        XCTAssertGreaterThan(name.frame.height, normalHeight * 1.5)
        capture(app, "Full saved train name largest text")

        let open = app.buttons["passport.open.12137-2026-09-18"]
        let remove = app.buttons["passport.remove.12137-2026-09-18"]
        reveal(open, in: page, app: app)
        XCTAssertTrue(open.isHittable && remove.isHittable)
        XCTAssertGreaterThanOrEqual(open.frame.height, 44)
        XCTAssertGreaterThanOrEqual(remove.frame.height, 44)
        XCTAssertFalse(open.frame.intersects(remove.frame))
        capture(app, "Separate open and delete controls largest text")
        let requestsBeforeOpen = gateway.runRequests
        open.tap()
        XCTAssertTrue(app.staticTexts["Dadar to Kalyan Jn"].waitForExistence(timeout: 10))
        XCTAssertGreaterThan(gateway.runRequests, requestsBeforeOpen)
        XCTAssertFalse(app.staticTexts["Mumbai CSMT to Kasara"].exists)
        expand(app)
        reveal(app.staticTexts["Dadar to Kalyan Jn"], in: app.scrollViews.firstMatch, app: app)
        capture(app, "Saved personal segment reopened")

        app.buttons["Passport"].tap()
        reveal(remove, in: app.scrollViews["passport.content"], app: app)
        let requestsBeforeDelete = gateway.runRequests
        remove.tap()
        XCTAssertTrue(app.staticTexts["A thousand places.\nYour first page."].waitForExistence(timeout: 5))
        XCTAssertFalse(open.exists)
        XCTAssertEqual(gateway.runRequests, requestsBeforeDelete, "Removing must not open the journey.")
        XCTAssertTrue(app.buttons["Passport"].isSelected)
        XCTAssertFalse(gateway.paths.contains { $0.contains("journey-alerts") || $0.contains("/privacy/consent") || $0.contains("observations") })
        app.terminate()
    }

    @MainActor private func setPlan(_ app: XCUIApplication, boarding: String, alighting: String) {
        let edit = app.buttons["Edit your journey"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        let board = app.buttons["journey.plan.Boarding"]
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        board.tap()
        app.buttons[boarding].tap()
        app.buttons["journey.plan.Drop-off"].tap()
        app.buttons[alighting].tap()
        app.navigationBars.buttons["Save"].tap()
    }

    @MainActor private func expand(_ app: XCUIApplication) {
        let button = app.buttons["Expand journey details"]
        if button.exists { button.tap() }
    }

    @MainActor private func reveal(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) {
        func region() -> CGRect {
            let frame = scroll.frame
            let top = max(frame.minY, 64) + 8
            return CGRect(x: frame.minX, y: top, width: frame.width,
                          height: max(0, min(frame.maxY, app.buttons["Passport"].frame.minY - 12) - top))
        }
        for _ in 0..<24 {
            let reading = region()
            if element.exists && element.isHittable && reading.contains(element.frame) { return }
            let frame = element.frame
            let downward = frame.minY < reading.minY
            let overflow = downward ? reading.minY - frame.minY : frame.maxY - reading.maxY
            let distance = min(160, max(40, overflow + 12), max(40, reading.height - 48))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: reading.minX + 8, dy: reading.midY + (downward ? -distance / 2 : distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: reading.minX + 8, dy: reading.midY + (downward ? distance / 2 : -distance / 2)))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(region().contains(element.frame), "Whole text/control must fit the reading region: \(element.frame)")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Supplies a short captured timetable through the ordinary gateway configuration.
private final class PassportReopeningGateway: @unchecked Sendable {
    let name = "Punjab Mail Western and Northern Railway Express"
    private let listener: NWListener
    private let queue = DispatchQueue(label: "PassportReopeningGateway")
    private let lock = NSLock()
    private var requests: [String] = []
    private let journey: [String: Any]
    var paths: [String] { lock.withLock { requests } }
    var runRequests: Int { paths.filter { $0 == "/v1/runs/12137/2026-09-18" }.count }
    var baseURL: String? { listener.port.map { "http://127.0.0.1:\($0.rawValue)" } }

    init(fixture: Data, ready: XCTestExpectation) throws {
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture) as? [String: Any])
        var run = try XCTUnwrap(envelope["journey"] as? [String: Any])
        let stops = try XCTUnwrap(run["stops"] as? [[String: Any]])
        run["stops"] = Array(stops.prefix(4))
        run["trainName"] = name
        envelope["journey"] = run
        journey = envelope
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
                payload = self.journey; status = "200 OK"
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

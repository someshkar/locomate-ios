import XCTest
import Network

final class SearchAccessibilityUITests: XCTestCase {
    @MainActor
    func testSearchRetriesAndReplacedQueriesCannotKeepOldActions() async throws {
        continueAfterFailure = false
        let ready = expectation(description: "Search gateway ready")
        let gateway = try SearchSelectionGateway(ready: ready)
        defer { gateway.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 10))
        app.buttons["Find a train"].tap()
        let field = app.textFields["Search trains"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("12951\n")
        XCTAssertTrue(app.buttons["Try again"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["search.result.12951"].exists)
        app.buttons["Try again"].tap()
        XCTAssertTrue(app.buttons["search.result.12951"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["search.result.source.12951"].label, "Historical railway snapshot")
        capture(app, "Native compact Search row after real HTTP retry")

        field.tap()
        field.typeText("2")
        let held = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            gateway.paths.contains("/v1/trains/search?q=129512")
        }, object: nil)
        await fulfillment(of: [held], timeout: 5)
        XCTAssertFalse(app.buttons["search.result.12951"].exists,
                       "The old result must lose its action while the replacement request is held.")
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        XCTAssertFalse(app.buttons["search.result.12951"].exists)
        field.typeText("54321\n")
        XCTAssertTrue(app.buttons["search.result.54321"].waitForExistence(timeout: 10))
        gateway.releaseHeldResponse()
        XCTAssertFalse(app.buttons["search.result.12951"].exists)
        XCTAssertFalse(app.buttons["search.result.129512"].exists)
        let result = app.buttons["search.result.54321"]
        XCTAssertEqual(result.label, "54321 Current Express")
        capture(app, "Only the current Search query retains a native action")
        result.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Selected dated query reached fixture.")).firstMatch
            .waitForExistence(timeout: 10))
        XCTAssertTrue(gateway.paths.contains { $0.hasPrefix("/v1/runs/54321/") })
        XCTAssertFalse(gateway.paths.contains { $0.hasPrefix("/v1/runs/12951/") || $0.contains("/privacy/consent") || $0.contains("journey-alerts") })
    }

    @MainActor
    func testLongTrainResultIsReadableAndOpensExactJourneyAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 10))
        app.buttons["Find a train"].tap()
        let field = app.textFields["Search trains"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.containing(.textField, identifier: "Search trains").firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        reveal(field, in: scroll, app: app)
        field.tap()
        for digit in "12951" { field.typeText(String(digit)) }
        XCTAssertEqual(field.value as? String, "12951")
        field.typeText("\n")

        let fullName = "Mumbai Central-New Delhi Rajdhani Express"
        let result = app.buttons["search.result.12951"]
        let name = app.staticTexts["search.result.name.12951"]
        let number = app.staticTexts["search.result.number.12951"]
        let source = app.staticTexts["search.result.source.12951"]
        let route = app.staticTexts["search.result.route.12951"]
        let distance = app.staticTexts["search.result.distance.12951"]
        reveal(result, in: scroll, app: app)
        XCTAssertEqual(result.label, "12951 \(fullName)")

        reveal(source, in: scroll, app: app)
        XCTAssertEqual(number.label, "12951")
        XCTAssertEqual(source.label, "Historical route pack")
        XCTAssertGreaterThanOrEqual(source.frame.minY, number.frame.maxY)
        capture(app, "Largest Search result number and source")

        reveal(name, in: scroll, app: app)
        XCTAssertEqual(name.label, fullName)
        XCTAssertGreaterThan(name.frame.height, number.frame.height,
                             "The full long name must occupy multiple enlarged lines.")
        capture(app, "Full Search result name at largest text")

        reveal(distance, in: scroll, app: app)
        XCTAssertEqual(route.label, "BCT → NDLS")
        XCTAssertEqual(distance.label, "1,384 km")
        XCTAssertGreaterThanOrEqual(distance.frame.minY, route.frame.maxY)
        capture(app, "Largest Search result route and distance")

        // Tap a visible part of the actual result, not its offscreen center.
        reveal(name, in: scroll, app: app)
        name.tap()
        XCTAssertTrue(app.staticTexts["12951 · \(fullName)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Timetable sample"].exists)
        XCTAssertFalse(field.exists, "Selection must dismiss Search.")
        capture(app, "Exact long-name journey selected")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in scroll: XCUIElement, app: XCUIApplication) {
        func region() -> CGRect {
            let frame = scroll.frame
            let top = max(frame.minY, 64) + 8
            let dockTop = app.buttons["Find a train"].frame.minY - 12
            return CGRect(x: frame.minX + 8, y: top, width: frame.width - 16,
                          height: max(0, min(frame.maxY, dockTop) - top - 8))
        }
        for _ in 0..<36 {
            let reading = region()
            if element.exists && element.isHittable && reading.contains(element.frame) { return }
            // A lazy result has no native element until its row reaches the viewport.
            let frame = element.exists ? element.frame : .zero
            let downward = element.exists && frame.minY < reading.minY
            let overflow = element.exists ? (downward ? reading.minY - frame.minY : frame.maxY - reading.maxY) : 280
            let distance = min(280, max(40, overflow + 12), max(40, reading.height - 48))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: scroll.frame.minX + 24, dy: reading.midY + (downward ? -distance / 2 : distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: scroll.frame.minX + 24, dy: reading.midY + (downward ? distance / 2 : -distance / 2)))
            start.press(forDuration: 0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(region().contains(element.frame), "Whole text/control must fit the reading region: \(element.frame)")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The app uses its ordinary authenticated HTTP client; the replacement reply is held by the server.
private final class SearchSelectionGateway: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SearchSelectionGateway")
    private let lock = NSLock()
    private var requests: [String] = []
    private var failedFirstRequest = false
    private var held: [NWConnection] = []
    var paths: [String] { lock.withLock { requests } }
    var baseURL: String? { listener.port.map { "http://127.0.0.1:\($0.rawValue)" } }

    init(ready: XCTestExpectation) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        queue.async { [self] in held.forEach { $0.cancel() }; held.removeAll() }
    }

    func releaseHeldResponse() {
        queue.async { [self] in
            for connection in held { send(connection, body: catalogue("129512", "Obsolete Express")) }
            held.removeAll()
        }
    }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            guard let text = String(data: buffer, encoding: .utf8), text.contains("\r\n\r\n") else {
                if complete || error != nil || buffer.count > 65536 { connection.cancel() }
                else { self.receive(connection, accumulated: buffer) }
                return
            }
            let path = text.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            self.lock.withLock { self.requests.append(path) }
            if path == "/v1/auth/device-session" {
                self.send(connection, body: ["accessToken": "fixture-only", "expiresIn": 3600])
            } else if path == "/v1/trains/search?q=129512" {
                self.held.append(connection)
            } else if path.hasPrefix("/v1/trains/search?q=") {
                if !self.failedFirstRequest {
                    self.failedFirstRequest = true
                    self.send(connection, status: "503 Service Unavailable",
                              body: ["error": ["code": "provider_unavailable", "message": "Search temporarily unavailable."]])
                } else {
                    let number = String(path.split(separator: "=").last ?? "")
                    self.send(connection, body: self.catalogue(number, number == "54321" ? "Current Express" : "First Express"))
                }
            } else {
                self.send(connection, status: "404 Not Found",
                          body: ["error": ["code": "fixture_unavailable", "message": "Selected dated query reached fixture."]])
            }
        }
    }

    private func catalogue(_ number: String, _ name: String) -> [String: Any] {
        ["trains": [["number": number, "name": name, "originCode": "AAA", "originName": "Origin",
                     "destinationCode": "BBB", "destinationName": "Destination", "departure": "16:40", "arrival": "08:30",
                     "durationHours": 16.0, "distanceKm": 1384.0, "sourceLabel": "Historical railway snapshot",
                     "sourceUpdatedAt": "2026-09-30T00:00:00Z", "live": false]]]
    }

    private func send(_ connection: NWConnection, status: String = "200 OK", body: [String: Any]) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        var response = Data("HTTP/1.1 \(status)\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

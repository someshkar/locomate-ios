import XCTest
import Network

final class TimetablePassportUITests: XCTestCase {
    @MainActor
    func testScheduledCountdownAndPassportYearFiltersAtBothTextSizes() async throws {
        continueAfterFailure = false
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let fixture = try Data(contentsOf: fixtureURL)
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let ready = expectation(description: "Timetable fixture listening")
            let gateway = try TimetablePassportGateway(fixture: fixture, ready: ready)
            defer { gateway.stop() }
            await fulfillment(of: [ready], timeout: 5)
            let app = XCUIApplication()
            app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", category]
            app.launch()

            try openRun(app, date: gateway.futureDate, name: "Scheduled Boarding Express")
            let countdown = app.staticTexts["journey.departureCountdown"]
            XCTAssertTrue(countdown.waitForExistence(timeout: 10))
            XCTAssertTrue(countdown.label.contains("until scheduled departure"))
            XCTAssertTrue(countdown.label.contains("day"))
            let expand = app.buttons["Expand journey details"]
            if expand.exists { expand.tap() }
            reveal(countdown, in: app.scrollViews.firstMatch)
            capture(app, "Scheduled countdown \(category)")
            save(app)

            try openRun(app, date: gateway.pastDate, name: "Earlier Year Express")
            XCTAssertTrue(app.staticTexts["12137 · Earlier Year Express"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["journey.departureCountdown"].exists)
            save(app)
            app.buttons["Passport"].tap()

            let allTime = app.buttons["passport.period.All-Time"]
            XCTAssertTrue(allTime.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Train origin year"].exists)
            let currentYear = app.buttons["passport.period.\(gateway.year)"]
            let periods = app.scrollViews["passport.periods"]
            for _ in 0..<3 where !currentYear.isHittable { periods.swipeLeft() }
            XCTAssertTrue(currentYear.isHittable)
            currentYear.tap()
            XCTAssertTrue(currentYear.isSelected)
            let futureName = app.staticTexts["Scheduled Boarding Express"]
            reveal(futureName, in: app.scrollViews["passport.content"])
            XCTAssertTrue(futureName.exists)
            XCTAssertFalse(app.staticTexts["Earlier Year Express"].exists)
            capture(app, "Passport current year \(category)")

            let previousYear = app.buttons["passport.period.\(gateway.year - 1)"]
            // Return to the period control, then scroll its native horizontal region if needed.
            let page = app.scrollViews["passport.content"]
            reveal(periods, in: page)
            if !previousYear.isHittable {
                periods.swipeLeft()
            }
            XCTAssertTrue(previousYear.isHittable)
            previousYear.tap()
            XCTAssertTrue(previousYear.isSelected)
            let pastName = app.staticTexts["Earlier Year Express"]
            reveal(pastName, in: page)
            XCTAssertTrue(pastName.exists)
            XCTAssertFalse(app.staticTexts["Scheduled Boarding Express"].exists)
            capture(app, "Passport previous year \(category)")
            XCTAssertTrue(gateway.paths.contains("/v1/runs/12137/\(gateway.futureDate)"))
            XCTAssertTrue(gateway.paths.contains("/v1/runs/12137/\(gateway.pastDate)"))
            XCTAssertFalse(gateway.paths.contains { $0.contains("journey-alerts") || $0.contains("/privacy/consent") || $0.contains("observations") })
            app.terminate()
        }
    }

    @MainActor private func openRun(_ app: XCUIApplication, date: String, name: String) throws {
        // Exercise the production dated route and loader; Explore selection has its own gate.
        app.open(try XCTUnwrap(URL(string: "locomate://journeys/12137?date=\(date)")))
        XCTAssertTrue(app.staticTexts["12137 · \(name)"].waitForExistence(timeout: 10))
    }

    @MainActor private func save(_ app: XCUIApplication) {
        let expand = app.buttons["Expand journey details"]
        if expand.exists { expand.tap() }
        let button = app.buttons["Save"]
        reveal(button, in: app.scrollViews.firstMatch)
        XCTAssertTrue(button.isHittable)
        button.tap()
        XCTAssertTrue(app.staticTexts["Journey saved privately on this device."].waitForExistence(timeout: 10))
    }

    @MainActor private func reveal(_ element: XCUIElement, in scroll: XCUIElement) {
        let app = XCUIApplication()
        let dock = app.buttons["Passport"]
        func readingRegion() -> CGRect {
            let bottom = dock.exists && dock.isHittable ? dock.frame.minY - 12 : app.frame.maxY - 40
            let frame = scroll.exists ? scroll.frame : app.frame
            let top = max(frame.minY, 64) + 8
            return CGRect(x: frame.minX, y: top, width: frame.width,
                          height: max(0, min(bottom, frame.maxY) - top))
        }
        guard scroll.exists else {
            XCTAssertTrue(element.isHittable)
            XCTAssertTrue(readingRegion().contains(element.frame))
            return
        }
        for _ in 0..<18 {
            // Re-read after each gesture: the native sheet can settle at a new height.
            let reading = readingRegion()
            if element.exists, element.isHittable, reading.contains(element.frame) { return }
            let frame = element.frame
            let downward = element.exists && frame.minY < reading.minY
            let overflow = downward ? reading.minY - frame.minY : frame.maxY - reading.maxY
            // A full-height swipe can jump past a tall accessibility label and oscillate.
            let distance = min(160, max(40, overflow + 12), max(40, reading.height - 48))
            // The page's padding is an inert scroll gutter. A synthetic press that
            // starts on a button may activate it while its frame moves under the finger.
            let gutterX = reading.minX + 8
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: gutterX, dy: reading.midY + (downward ? -distance / 2 : distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: gutterX, dy: reading.midY + (downward ? distance / 2 : -distance / 2)))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(readingRegion().contains(element.frame), "Control must be wholly above the navigation dock: \(element.frame)")
    }

    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Test-process HTTP fixture. The app uses ordinary gateway reads and Save actions.
private final class TimetablePassportGateway: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "TimetablePassportGateway")
    private let lock = NSLock()
    private var requests: [String] = []
    private let fixture: Data
    let futureDate: String
    let pastDate: String
    let year: Int
    var paths: [String] { lock.withLock { requests } }
    var baseURL: String? { listener.port.map { "http://127.0.0.1:\($0.rawValue)" } }

    init(fixture: Data, ready: XCTestExpectation) throws {
        self.fixture = fixture
        let calendar = Calendar(identifier: .gregorian)
        let future = calendar.date(byAdding: .day, value: 2, to: Date())!
        let date = DateFormatter()
        date.calendar = calendar
        date.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        date.locale = Locale(identifier: "en_US_POSIX")
        date.dateFormat = "yyyy-MM-dd"
        futureDate = date.string(from: future)
        year = Int(futureDate.prefix(4))!
        pastDate = "\(year - 1)-10-01"
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var buffer = accumulated
            if let data { buffer.append(data) }
            guard let request = String(data: buffer, encoding: .utf8), request.contains("\r\n\r\n") else {
                if complete || error != nil || buffer.count > 65536 { connection.cancel() }
                else { self.receive(connection, accumulated: buffer) }
                return
            }
            let rawPath = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let path = String(rawPath.split(separator: "?").first ?? "")
            self.lock.withLock { self.requests.append(path) }
            let response = self.response(path)
            let body = (try? JSONSerialization.data(withJSONObject: response.body)) ?? Data()
            var bytes = Data("HTTP/1.1 \(response.status)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            bytes.append(body)
            connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func response(_ path: String) -> (status: String, body: [String: Any]) {
        if path == "/v1/auth/device-session" { return ("200 OK", ["accessToken": "test-only", "expiresIn": 3600]) }
        if path == "/v1/runs/12137/\(futureDate)" || path == "/v1/runs/12137/\(pastDate)",
           var body = (try? JSONSerialization.jsonObject(with: fixture)) as? [String: Any],
           var journey = body["journey"] as? [String: Any] {
            let date = path.hasSuffix(futureDate) ? futureDate : pastDate
            journey["id"] = "run:12137:\(date)"
            journey["travelDate"] = date
            journey["trainName"] = date == futureDate ? "Scheduled Boarding Express" : "Earlier Year Express"
            body["journey"] = journey
            return ("200 OK", body)
        }
        return ("404 Not Found", ["error": ["code": "fixture_unavailable", "message": "This fixture only supplies scheduled journeys."]])
    }
}

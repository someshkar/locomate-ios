import XCTest
import Network

final class SearchAccessibilityUITests: XCTestCase {
    @MainActor
    func testBetweenStationsUsesBoardingDateAndOpensDerivedOriginRun() async throws { try await verifyBetween(largest: false) }

    @MainActor
    func testBetweenStationsRemainsReadableAtLargestText() async throws { try await verifyBetween(largest: true) }

    @MainActor
    private func verifyBetween(largest: Bool) async throws {
        continueAfterFailure = false
        let ready = expectation(description: "Route gateway ready")
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let gateway = try SearchSelectionGateway(ready: ready, stationJourney: Data(contentsOf: fixture))
        defer { gateway.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        if largest { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); defer { app.terminate() }
        app.buttons["Find a train"].tap()
        let scroll = app.scrollViews.firstMatch
        let from = app.buttons["search.between.from"]
        reveal(from, in: scroll, app: app); from.tap()
        app.buttons["search.between.station.NDLS"].tap()
        let to = app.buttons["search.between.to"]
        reveal(to, in: scroll, app: app); to.tap()
        app.buttons["search.between.station.MMCT"].tap()
        let find = app.buttons["search.between.submit"]
        reveal(find, in: scroll, app: app); XCTAssertTrue(find.isEnabled); find.tap()
        let name = app.staticTexts["search.result.name.12137"]
        reveal(name, in: scroll, app: app)
        XCTAssertEqual(app.staticTexts["search.result.source.12137"].label, "RailRadar route timetable")
        let schedule = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "16:55 → 08:35")).firstMatch
        reveal(schedule, in: scroll, app: app)
        XCTAssertTrue(schedule.label.contains("train origin"))
        capture(app, "Native route search with dated scheduled service " + (largest ? "largest" : "normal"))
        let routePath = try XCTUnwrap(gateway.paths.first { $0.hasPrefix("/v1/trains/between?") })
        let travelDate = try XCTUnwrap(URLComponents(string: "http://localhost\(routePath)")?.queryItems?.first(where: { $0.name == "date" })?.value)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let boarding = try XCTUnwrap(formatter.date(from: travelDate))
        let origin = formatter.string(from: try XCTUnwrap(Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: boarding)))
        reveal(name, in: scroll, app: app)
        name.tap()
        XCTAssertTrue(app.staticTexts["12137 · Punjab Mail"].waitForExistence(timeout: 10))
        XCTAssertTrue(gateway.paths.contains("/v1/runs/12137/\(origin)"))
        app.buttons["Find a train"].tap()
        XCTAssertEqual(app.buttons["search.originDate.calendar"].value as? String, origin)
        XCTAssertFalse(gateway.paths.contains { $0.contains("privacy/consent") || $0.contains("journey-alerts") })
    }

    @MainActor
    func testStationShortcutLookupRetryAndExactDatedJourney() async throws { try await verifyStationSearch(largest: false) }

    @MainActor
    func testStationChoicesAndTimetableRemainReadableAtLargestText() async throws { try await verifyStationSearch(largest: true) }

    @MainActor
    private func verifyStationSearch(largest: Bool) async throws {
        continueAfterFailure = false
        let ready = expectation(description: "Station gateway ready")
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "run-12137-2026-09-18", withExtension: "json"))
        let gateway = try SearchSelectionGateway(ready: ready, stationJourney: Data(contentsOf: fixture))
        defer { gateway.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        if largest { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); defer { app.terminate() }
        app.buttons["Find a train"].tap()
        var scroll = app.scrollViews.firstMatch
        let shortcut = app.buttons["search.station.NDLS"]
        reveal(shortcut, in: scroll, app: app)
        XCTAssertEqual(shortcut.label, "Find trains at New Delhi, NDLS")
        XCTAssertGreaterThanOrEqual(shortcut.frame.height, 44)
        capture(app, "Station shortcuts " + (largest ? "largest" : "normal"))
        shortcut.tap()
        let retry = app.buttons["Try again"]
        reveal(retry, in: scroll, app: app); retry.tap()
        let source = app.staticTexts["search.result.source.12137"]
        reveal(source, in: scroll, app: app)
        XCTAssertEqual(source.label, "RailRadar station timetable")
        capture(app, "Scheduled station train source " + (largest ? "largest" : "normal"))
        let yesterday = app.buttons["Yest"]
        reveal(yesterday, in: scroll, app: app); yesterday.tap()
        let date = try XCTUnwrap(yesterday.value as? String)
        let name = app.staticTexts["search.result.name.12137"]
        reveal(name, in: scroll, app: app)
        XCTAssertEqual(name.label, "Station Express With A Complete Long Name")
        capture(app, "Complete scheduled station train " + (largest ? "largest" : "normal"))
        name.tap()
        XCTAssertTrue(app.staticTexts["12137 · Punjab Mail"].waitForExistence(timeout: 10))
        XCTAssertTrue(gateway.paths.contains("/v1/runs/12137/\(date)"))
        XCTAssertTrue(gateway.paths.contains("/v1/stations/NDLS/trains"))
        app.buttons["Find a train"].tap(); scroll = app.scrollViews.firstMatch
        let field = app.textFields["Search trains"]
        reveal(field, in: scroll, app: app); field.tap(); field.typeText("Delhi\n")
        let stationRetry = app.buttons["Retry station search"]
        reveal(stationRetry, in: scroll, app: app); stationRetry.tap()
        reveal(shortcut, in: scroll, app: app)
        XCTAssertFalse(app.staticTexts["No trains found"].exists)
        capture(app, "Station autocomplete after retry " + (largest ? "largest" : "normal"))
        shortcut.tap(); reveal(name, in: scroll, app: app)
        XCTAssertTrue(gateway.paths.contains("/v1/stations/search?q=Delhi"))
        XCTAssertFalse(gateway.paths.contains { $0.contains("privacy/consent") || $0.contains("journey-alerts") })
        if !largest {
            let clear = app.buttons["Clear search"]
            reveal(clear, in: scroll, app: app); clear.tap()
            reveal(field, in: scroll, app: app); field.tap(); field.typeText("Obsolete\n")
            let held = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in gateway.waitingForStationReply }, object: nil)
            await fulfillment(of: [held], timeout: 5)
            reveal(clear, in: scroll, app: app); clear.tap()
            gateway.releaseHeldStationReply()
            XCTAssertFalse(app.buttons["search.station.XYZ"].waitForExistence(timeout: 1))
            XCTAssertFalse(app.buttons["search.result.12137"].exists)
            capture(app, "Cleared search rejects obsolete station reply")
        }
    }

    @MainActor
    func testRecentTrainPersistsReopensChosenDateAndStaysInItsGatewayScope() async throws {
        continueAfterFailure = false
        let ready = expectation(description: "Recent gateway ready")
        let gateway = try SearchSelectionGateway(ready: ready)
        defer { gateway.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        app.launch()
        defer { app.terminate() }
        app.buttons["Find a train"].tap()
        let field = app.textFields["Search trains"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("12951\n")
        var scroll = app.scrollViews.firstMatch
        reveal(app.buttons["Try again"], in: scroll, app: app)
        app.buttons["Try again"].tap()
        let result = app.buttons["search.result.12951"]
        reveal(result, in: scroll, app: app)
        result.tap()
        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 10))
        app.buttons["Find a train"].tap()
        scroll = app.scrollViews.firstMatch
        let recent = app.buttons["search.recent.12951"]
        reveal(recent, in: scroll, app: app)
        XCTAssertEqual(recent.label, "12951 First Express")
        XCTAssertFalse(app.staticTexts["On Time"].exists)
        capture(app, "Recent train restored after app restart")
        let yesterday = app.buttons["Yest"]
        reveal(yesterday, in: scroll, app: app); yesterday.tap()
        let selectedDate = try XCTUnwrap(yesterday.value as? String)
        reveal(recent, in: scroll, app: app); recent.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Selected dated query reached fixture.")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(gateway.paths.contains("/v1/runs/12951/\(selectedDate)"))
        XCTAssertEqual(gateway.paths.filter { $0.hasPrefix("/v1/trains/search?") }.count, 2)

        let otherReady = expectation(description: "Other gateway ready")
        let other = try SearchSelectionGateway(ready: otherReady)
        defer { other.stop() }
        await fulfillment(of: [otherReady], timeout: 5)
        app.terminate()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(other.baseURL)
        app.launch(); app.buttons["Find a train"].tap()
        XCTAssertFalse(app.buttons["search.recent.12951"].exists)
        app.terminate()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        app.launch(); app.buttons["Find a train"].tap()
        scroll = app.scrollViews.firstMatch
        let clear = app.buttons["Clear recent trains"]
        reveal(clear, in: scroll, app: app)
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        clear.tap()
        XCTAssertFalse(recent.exists)
        capture(app, "Recent trains cleared through the native action")
        app.terminate(); app.launch(); app.buttons["Find a train"].tap()
        XCTAssertFalse(recent.exists)
        XCTAssertFalse(gateway.paths.contains { $0.contains("/privacy/consent") || $0.contains("journey-alerts") })
    }

    @MainActor
    func testRecentPreviewTrainRemainsReadableAndClearableAtLargestText() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 10))
        app.buttons["Find a train"].tap()
        var scroll = app.scrollViews.firstMatch
        let field = app.textFields["Search trains"]
        reveal(field, in: scroll, app: app)
        field.tap(); field.typeText("12951\n")
        let name = app.staticTexts["search.result.name.12951"]
        reveal(name, in: scroll, app: app); name.tap()
        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 5))
        app.buttons["Find a train"].tap()
        scroll = app.scrollViews.firstMatch
        reveal(name, in: scroll, app: app)
        XCTAssertEqual(name.label, "Mumbai Central-New Delhi Rajdhani Express")
        XCTAssertTrue(app.buttons["search.recent.12951"].exists)
        capture(app, "Full recent train name at largest text")
        let source = app.staticTexts["search.result.source.12951"]
        reveal(source, in: scroll, app: app)
        XCTAssertEqual(source.label, "Historical route pack")
        capture(app, "Recent catalogue provenance at largest text")
        reveal(name, in: scroll, app: app); name.tap()
        XCTAssertTrue(app.staticTexts["12951 · Mumbai Central-New Delhi Rajdhani Express"].waitForExistence(timeout: 10))
        app.buttons["Find a train"].tap()
        scroll = app.scrollViews.firstMatch
        let clear = app.buttons["Clear recent trains"]
        reveal(clear, in: scroll, app: app)
        XCTAssertGreaterThanOrEqual(clear.frame.height, 44)
        capture(app, "Reachable clear-recent action at largest text")
        clear.tap()
        XCTAssertFalse(app.buttons["search.recent.12951"].exists)
    }

    @MainActor
    func testOriginCalendarConfirmsExactDateAndCancelRetainsQuickSelection() async throws {
        try await verifyOriginCalendar(largest: false)
    }

    @MainActor
    func testOriginCalendarAtLargestTextConfirmsExactDatedSelection() async throws {
        try await verifyOriginCalendar(largest: true)
    }

    @MainActor
    private func verifyOriginCalendar(largest: Bool) async throws {
        continueAfterFailure = false
        let ready = expectation(description: "Calendar gateway ready")
        let gateway = try SearchSelectionGateway(ready: ready)
        defer { gateway.stop() }
        await fulfillment(of: [ready], timeout: 5)
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLocale", "en_US"]
        if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = try XCTUnwrap(gateway.baseURL)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 10))
        app.buttons["Find a train"].tap()
        let field = app.textFields["Search trains"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("12951\n")
        let scroll = app.scrollViews.firstMatch
        reveal(app.buttons["Try again"], in: scroll, app: app)
        app.buttons["Try again"].tap()
        let calendar = app.buttons["search.originDate.calendar"]
        reveal(calendar, in: scroll, app: app)
        let yesterday = app.buttons["Yest"]
        reveal(yesterday, in: scroll, app: app)
        yesterday.tap()
        let quickDate = try XCTUnwrap(yesterday.value as? String)
        XCTAssertEqual(calendar.value as? String, quickDate)
        reveal(calendar, in: scroll, app: app)
        capture(app, "Shared origin date controls \(largest ? "largest" : "normal")")
        calendar.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        let year = app.pickerWheels.matching(NSPredicate(format: "value MATCHES %@", "[0-9]{4}")).firstMatch
        XCTAssertTrue(year.exists)
        year.adjust(toPickerWheelValue: "2019")
        revealCalendarAction(app.buttons["Cancel"], in: app)
        XCTAssertGreaterThanOrEqual(app.buttons["Cancel"].frame.height, 44)
        app.buttons["Cancel"].tap()
        XCTAssertEqual(calendar.value as? String, quickDate)
        calendar.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        let month = app.pickerWheels.matching(NSPredicate(format: "value MATCHES %@", "[A-Za-z]+" )).firstMatch
        let day = app.pickerWheels.matching(NSPredicate(format: "value MATCHES %@", "[0-9]{1,2}")).firstMatch
        year.adjust(toPickerWheelValue: "2019")
        month.adjust(toPickerWheelValue: "February")
        day.adjust(toPickerWheelValue: "15")
        let confirm = app.buttons["search.originDate.confirm"]
        revealCalendarAction(confirm, in: app)
        XCTAssertTrue(confirm.isHittable)
        XCTAssertGreaterThanOrEqual(confirm.frame.height, 44)
        capture(app, "Native origin calendar \(largest ? "largest" : "normal")")
        confirm.tap()
        reveal(calendar, in: scroll, app: app)
        XCTAssertEqual(calendar.value as? String, "2019-02-15")
        capture(app, "Confirmed date outside the quick strip \(largest ? "largest" : "normal")")
        let result = app.buttons["search.result.12951"]
        reveal(result, in: scroll, app: app)
        result.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Selected dated query reached fixture.")).firstMatch
            .waitForExistence(timeout: 10))
        XCTAssertTrue(gateway.paths.contains("/v1/runs/12951/2019-02-15"))
        XCTAssertFalse(gateway.paths.contains { $0.contains("/privacy/consent") || $0.contains("journey-alerts") })
    }

    @MainActor
    private func revealCalendarAction(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["search.originDate.scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            if element.isHittable && scroll.frame.insetBy(dx: 8, dy: 8).contains(element.frame) { return }
            let frame = scroll.frame
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + 8, dy: frame.midY + 120))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + 8, dy: frame.midY - 120))
            start.press(forDuration: 0, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(scroll.frame.insetBy(dx: 8, dy: 8).contains(element.frame))
    }

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
    private var heldStations: [NWConnection] = []
    private var failedStationLookup = false
    private var failedStationBoard = false
    private let stationJourney: [String: Any]?
    var waitingForStationReply: Bool { lock.withLock { requests.contains("/v1/stations/search?q=Obsolete") } }
    var paths: [String] { lock.withLock { requests } }
    var baseURL: String? { listener.port.map { "http://127.0.0.1:\($0.rawValue)" } }

    init(ready: XCTestExpectation, stationJourney: Data? = nil) throws {
        self.stationJourney = try stationJourney.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? nil
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
        queue.async { [self] in (held + heldStations).forEach { $0.cancel() }; held.removeAll(); heldStations.removeAll() }
    }

    func releaseHeldStationReply() {
        queue.async { [self] in
            for connection in heldStations { send(connection, body: ["stations": [["code": "XYZ", "name": "Obsolete Station",
                "sourceLabel": "Fixture catalogue", "sourceUpdatedAt": NSNull()]]]) }
            heldStations.removeAll()
        }
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
            } else if self.stationJourney != nil && path == "/v1/stations/search?q=Obsolete" {
                self.heldStations.append(connection)
            } else if self.stationJourney != nil && path.hasPrefix("/v1/stations/search?") {
                if !self.failedStationLookup {
                    self.failedStationLookup = true
                    self.send(connection, status: "503 Unavailable", body: ["error": ["message": "Station lookup temporarily unavailable."]])
                } else { self.send(connection, body: ["stations": [["code": "NDLS", "name": "New Delhi",
                    "sourceLabel": "RailRadar station catalogue", "sourceUpdatedAt": NSNull()]]]) }
            } else if self.stationJourney != nil && path == "/v1/stations/NDLS/trains" {
                if !self.failedStationBoard {
                    self.failedStationBoard = true
                    self.send(connection, status: "503 Unavailable", body: ["error": ["message": "Station timetable temporarily unavailable."]])
                } else {
                    var catalogue = self.catalogue("12137", "Station Express With A Complete Long Name")
                    var trains = catalogue["trains"] as! [[String: Any]]
                    trains[0]["sourceLabel"] = "RailRadar station timetable"; trains[0]["distanceKm"] = 0
                    catalogue["trains"] = trains
                    catalogue["station"] = ["code": "NDLS", "name": "New Delhi", "sourceLabel": "RailRadar station timetable", "sourceUpdatedAt": NSNull()]
                    catalogue["truncated"] = false
                    self.send(connection, body: catalogue)
                }
            } else if self.stationJourney != nil && path.hasPrefix("/v1/trains/between?") {
                let date = URLComponents(string: "http://localhost\(path)")?.queryItems?.first(where: { $0.name == "date" })?.value ?? "2026-10-02"
                let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = TimeZone(secondsFromGMT: 0)
                let boarding = formatter.date(from: date) ?? Date()
                let origin = formatter.string(from: Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: boarding) ?? boarding)
                self.send(connection, body: [
                    "from": ["code": "NDLS", "name": "New Delhi", "sourceLabel": "RailRadar route timetable", "sourceUpdatedAt": NSNull()],
                    "to": ["code": "MMCT", "name": "Mumbai Central", "sourceLabel": "RailRadar route timetable", "sourceUpdatedAt": NSNull()],
                    "truncated": false,
                    "trains": [["number": "12137", "name": "Station Express With A Complete Long Name",
                        "originCode": "NDLS", "originName": "New Delhi", "destinationCode": "MMCT", "destinationName": "Mumbai Central",
                        "departure": "16:55", "arrival": "08:35", "durationHours": 15.67, "distanceKm": 1388.4,
                        "sourceLabel": "RailRadar route timetable", "sourceUpdatedAt": NSNull(), "live": false,
                        "originDate": origin, "boardingDay": 2, "arrivalDay": 3]]])
            } else if let journey = self.stationJourney, path.hasPrefix("/v1/runs/12137/") && !path.contains("working") {
                var response = journey
                var body = response["journey"] as! [String: Any]
                let date = String(path.split(separator: "/").last ?? "")
                body["id"] = "run:12137:\(date)"; body["travelDate"] = date
                response["journey"] = body
                self.send(connection, body: response)
            } else if self.stationJourney != nil && path.hasPrefix("/v1/trains/search?") {
                self.send(connection, body: ["trains": []])
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

import XCTest

final class NavigationUITests: XCTestCase {
    @MainActor
    func testCurrentLocalGatewayJourneyAndNetwork() throws {
        guard let gateway = ProcessInfo.processInfo.environment["LOCOMOTE_LOCAL_GATEWAY_URL"],
              gateway.hasPrefix("http://127.0.0.1:") else {
            throw XCTSkip("Run with a local Wrangler gateway to exercise the current public feed.")
        }

        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = gateway
        app.launch()

        XCTAssertTrue(app.buttons["Find your train"].waitForExistence(timeout: 10))
        app.buttons["Find your train"].tap()
        let field = app.textFields["Search trains"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("12137")
        let result = app.buttons["12137 Punjab Mail"]
        XCTAssertTrue(result.waitForExistence(timeout: 20))
        result.tap()

        XCTAssertTrue(app.staticTexts["12137 · Punjab Mail"].waitForExistence(timeout: 25))
        XCTAssertFalse(app.staticTexts["Timetable sample"].exists)
        app.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["Rail network"].waitForExistence(timeout: 10))
        let updated = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "UPDATED ")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 25))
    }

    @MainActor
    func testProductionStartsWithoutSampleTrain() {
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = "https://example.invalid"
        app.launch()

        XCTAssertTrue(app.staticTexts["Every journey starts here."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Timetable sample"].exists)
        app.buttons["Find your train"].tap()
        XCTAssertTrue(app.textFields["Search trains"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testPrimarySurfacesOpenOnSimulator() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["My Journeys"].waitForExistence(timeout: 10))
        capture(app, "Journey")

        app.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["Rail network"].waitForExistence(timeout: 5))
        capture(app, "Explore")

        app.buttons["Passport"].tap()
        XCTAssertTrue(app.staticTexts["Passport"].waitForExistence(timeout: 5))
        capture(app, "Passport")

        app.buttons["Find a train"].tap()
        XCTAssertTrue(app.textFields["Search trains"].waitForExistence(timeout: 5))
        capture(app, "Search")
    }

    @MainActor
    func testSearchSheetSelectsPreviewJourney() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 10))
        app.buttons["Find a train"].tap()
        let field = app.textFields["Search trains"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("12951")

        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "12951 ")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        result.tap()

        let journey = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "12951 ·")).firstMatch
        XCTAssertTrue(journey.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Timetable sample"].exists)
        XCTAssertFalse(field.exists)
    }

    @MainActor
    func testPreviewJourneyAlertsStayUnavailable() {
        let app = XCUIApplication()
        app.launch()

        let expand = app.buttons["Expand journey details"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        let alerts = app.buttons["journeyAlerts.open"]
        for _ in 0..<5 where !alerts.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(alerts.isHittable)
        alerts.tap()

        XCTAssertTrue(app.navigationBars["Journey alerts"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Alerts need a current journey from the production service. Historical previews and cached journeys cannot enable new alerts."].exists)
        XCTAssertFalse(app.buttons["journeyAlerts.enable"].exists)
        XCTAssertFalse(app.switches["journeyAlerts.channel.delay"].exists)
        XCTAssertTrue(app.buttons["Open notification settings"].exists)
        capture(app, "Preview alerts unavailable")
        app.buttons["Done"].tap()

        app.buttons["Passport"].tap()
        let settings = app.buttons["Open settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        let unavailable = app.staticTexts["Journey alerts are unavailable in historical preview."]
        for _ in 0..<5 where !unavailable.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(unavailable.isHittable)
        XCTAssertFalse(app.buttons["Stop all journey alerts"].exists)
        XCTAssertFalse(app.buttons["Refresh and retry pending changes"].exists)
        XCTAssertTrue(app.buttons["Open notification settings"].exists)
        capture(app, "Preview alert settings")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

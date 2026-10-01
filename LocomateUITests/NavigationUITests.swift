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
    func testAccessibleJourneyControlsAndTimetableSummary() {
        let app = XCUIApplication()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let expand = app.buttons["Expand journey details"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(expand.frame.height, 44 - 0.001)
        expand.tap()
        for title in ["Trip", "Stops", "Insights"] {
            let button = app.buttons[title]
            XCTAssertTrue(button.isHittable)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44 - 0.001)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44 - 0.001)
        }
        let summary = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@ AND label CONTAINS %@",
            "MUMBAI CST, 19:40", "FIROZPUR CANT, 05:40", "kilometres")).firstMatch
        XCTAssertTrue(summary.exists, "VoiceOver must include both station names and their timetable times.")
        let alerts = app.buttons["journeyAlerts.open"]
        for _ in 0..<6 where !alerts.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(alerts.isHittable)
        alerts.tap()
        let settings = app.buttons["Open notification settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44 - 0.001)
        capture(app, "Accessible alert controls")
    }

    @MainActor
    func testLargestTextKeepsNavigationAndSearchReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        let title = app.staticTexts["My Journeys"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let regularHeight = title.frame.height
        capture(app, "Journey regular text")
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(title.frame.height, regularHeight * 1.3,
                             "The test must exercise actual Dynamic Type scaling.")
        for label in ["Journey", "Explore", "Passport", "Find a train"] {
            let control = app.buttons[label]
            XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 - 0.001)
            XCTAssertLessThan(control.frame.height, 100, "Navigation must leave room for the enlarged content.")
        }
        capture(app, "Journey largest text")
        app.buttons["Journey"].press(forDuration: 4)
        app.buttons["Passport"].tap()
        XCTAssertTrue(app.buttons["Open settings"].waitForExistence(timeout: 5))
        capture(app, "Passport largest text")
        app.buttons["Find a train"].tap()
        let search = app.textFields["Search trains"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        for _ in 0..<3 where !search.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(search.isHittable)
        capture(app, "Search largest text")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Audits the rendered native controls without filtering issue categories.
/// Physical VoiceOver navigation remains a separate release check.
final class AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LOCOMATE_RUN_ACCESSIBILITY_AUDITS"] == "1",
                          "Full accessibility audits are an explicit release gate. Set LOCOMATE_RUN_ACCESSIBILITY_AUDITS=1.")
    }

    @MainActor
    func testJourneyAccessibility() throws {
        let app = previewApp()
        XCTAssertTrue(app.buttons["Expand journey details"].waitForExistence(timeout: 10))
        try audit(app, screen: "Journey map and summary")
        app.buttons["Expand journey details"].tap()
        try audit(app, screen: "Journey details")
    }

    @MainActor
    func testExploreAccessibility() throws {
        let app = previewApp()
        app.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["Rail network"].waitForExistence(timeout: 5))
        try audit(app, screen: "Explore")
    }

    @MainActor
    func testPassportAccessibility() throws {
        let app = previewApp()
        app.buttons["Passport"].tap()
        XCTAssertTrue(app.buttons["Open settings"].waitForExistence(timeout: 5))
        try audit(app, screen: "Passport")
    }

    @MainActor
    func testSearchAccessibility() throws {
        let app = previewApp()
        app.buttons["Find a train"].tap()
        XCTAssertTrue(app.textFields["Search trains"].waitForExistence(timeout: 5))
        try audit(app, screen: "Search")
    }

    @MainActor
    func testJourneyAlertsAccessibility() throws {
        let app = previewApp()
        let expand = app.buttons["Expand journey details"]
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        let alerts = app.buttons["journeyAlerts.open"]
        for _ in 0..<5 where !alerts.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(alerts.isHittable)
        alerts.tap()
        XCTAssertTrue(app.navigationBars["Journey alerts"].waitForExistence(timeout: 5))
        try audit(app, screen: "Journey alerts unavailable")
    }

    @MainActor
    func testSettingsAccessibility() throws {
        let app = previewApp()
        app.buttons["Passport"].tap()
        let settings = app.buttons["Open settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
        try audit(app, screen: "Settings appearance and journey alerts")
        app.scrollViews.firstMatch.swipeUp()
        try audit(app, screen: "Settings contribution and privacy")
    }

    @MainActor
    func testLightSettingsAccessibility() throws {
        let app = previewApp()
        app.buttons["Passport"].tap()
        app.buttons["Open settings"].tap()
        let darkMode = app.buttons["Dark mode"]
        XCTAssertTrue(darkMode.waitForExistence(timeout: 5))
        darkMode.tap()
        defer { darkMode.tap() }
        XCTAssertTrue(app.staticTexts["Off · tap to switch"].waitForExistence(timeout: 5))
        try audit(app, screen: "Settings in light appearance")
    }

    @MainActor
    private func previewApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["My Journeys"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func audit(_ app: XCUIApplication, screen: String) throws {
        try XCTContext.runActivity(named: "Accessibility: \(screen)") { activity in
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = screen
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
            try app.performAccessibilityAudit(for: .all) { issue in
                let details = "\(issue.compactDescription)\n\(issue.detailedDescription)\n\(issue.element?.debugDescription ?? "No element identified")"
                let attachment = XCTAttachment(string: details)
                attachment.name = "\(screen): \(issue.compactDescription)"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
                return false
            }
        }
    }
}

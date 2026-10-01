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
    func testTimelinePreservesLongStationNamesAtLargestText() {
        let app = XCUIApplication()
        var regularNameHeight: CGFloat = 0
        for category in ["UICTContentSizeCategoryL", "UICTContentSizeCategoryAccessibilityXXXL"] {
            let largest = category == "UICTContentSizeCategoryAccessibilityXXXL"
            app.launchArguments = ["-UIPreferredContentSizeCategoryName", category]
            app.launch()
            let expand = app.buttons["Expand journey details"]
            XCTAssertTrue(expand.waitForExistence(timeout: 10))
            expand.tap()
            let stops = app.buttons["Stops"]
            revealForReading(stops, in: app, screen: "Stops selector")
            stops.tap()

            let source = app.descendants(matching: .any).matching(NSPredicate(
                format: "label == %@", "DEMO DATA. Explore the app with sample information. Nothing here is live.")).firstMatch
            let sourceRegion = revealForReading(source, in: app, screen: "Timeline source")
            XCTAssertGreaterThanOrEqual(source.frame.minY, sourceRegion.minY)
            XCTAssertLessThanOrEqual(source.frame.maxY, sourceRegion.maxY)
            capture(app, largest ? "Timeline source largest text" : "Timeline source regular text")

            let station = app.staticTexts["journeyTimeline.DR.name"]
            let time = app.staticTexts["journeyTimeline.DR.arrival"]
            XCTAssertEqual(station.label, "MUMBAI DADAR CENTRAL")
            XCTAssertEqual(time.label, "Scheduled time, 19:53")
            revealForReading(station, in: app, screen: "Dadar station name")
            let readingRegion = revealForReading(time, in: app, screen: "Dadar scheduled arrival")
            XCTAssertGreaterThanOrEqual(station.frame.minY, readingRegion.minY)
            XCTAssertLessThanOrEqual(time.frame.maxY, readingRegion.maxY)
            XCTAssertGreaterThanOrEqual(station.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(station.frame.maxX, app.frame.maxX)
            if largest {
                XCTAssertGreaterThan(station.frame.height, regularNameHeight * 1.5,
                                     "The full station name must wrap as its font grows.")
                XCTAssertGreaterThanOrEqual(time.frame.minY, station.frame.maxY,
                                            "The scheduled time must sit below the full name at accessibility sizes.")
            } else {
                regularNameHeight = station.frame.height
            }
            capture(app, largest ? "Dadar timeline largest text" : "Dadar timeline regular text")
            app.terminate()
        }
    }

    @MainActor
    func testContributionControlsRespectTextSizeAndHitRegions() {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Passport"].waitForExistence(timeout: 10))
        app.buttons["Passport"].tap()
        app.buttons["Open settings"].tap()
        for title in ["Contribute while using the app", "Continue in the background"] {
            let control = app.buttons[title]
            let readingRegion = revealForReading(control, in: app, screen: title)
            XCTAssertLessThanOrEqual(control.frame.height, readingRegion.height,
                                      "Each contribution choice and explanation must fit together at the largest size.")
            XCTAssertGreaterThanOrEqual(control.frame.minY, readingRegion.minY)
            XCTAssertLessThanOrEqual(control.frame.maxY, readingRegion.maxY)
            XCTAssertFalse(control.isEnabled, "Historical previews must keep location collection unavailable.")
            XCTAssertTrue((control.value as? String)?.hasPrefix("Unavailable.") == true)
            capture(app, title + " largest text")
        }
        app.terminate()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        app.buttons["Passport"].tap()
        app.buttons["Open settings"].tap()
        for title in ["Contribute while using the app", "Continue in the background"] {
            let control = app.buttons[title]
            revealForReading(control, in: app, screen: title + " regular text")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 - 0.001,
                                        "The complete row is the tap target, including the shorter background choice.")
        }
        capture(app, "Contribution controls regular text")
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
    func testLargestTextPassagesWhenScrolledIntoView() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["Passport"].waitForExistence(timeout: 10))
        app.buttons["Passport"].tap()
        let heading = app.staticTexts["A thousand places.\nYour first page."]
        try revealAndAudit(heading, in: app, screen: "Passport empty heading fully scrolled")

        app.buttons["Find a train"].tap()
        XCTAssertTrue(app.textFields["Search trains"].waitForExistence(timeout: 5))
        try revealAndAudit(app.buttons["Today"], in: app, screen: "Search origin dates fully scrolled", modal: true)
        try revealAndAudit(app.staticTexts["The origin date is the day the train starts in India — overnight runs may reach your station the next day."],
                           in: app, screen: "Search origin help fully scrolled", modal: true)
        try revealAndAudit(app.staticTexts["Search uses a historical Indian Railways snapshot. Results are real records, not current schedules."],
                           in: app, screen: "Search snapshot notice fully scrolled", modal: true)
        app.terminate()
        app.launch()
        app.buttons["Passport"].tap()
        app.buttons["Open settings"].tap()
        try revealAndAudit(app.staticTexts["COMMUNITY CONTRIBUTION"], in: app, screen: "Contribution heading fully scrolled")
        try revealAndAudit(app.buttons["Contribute while using the app"], in: app, screen: "Contribution foreground fully scrolled")
        try revealAndAudit(app.buttons["Continue in the background"], in: app, screen: "Contribution background fully scrolled")
    }

    @MainActor
    private func revealAndAudit(_ element: XCUIElement, in app: XCUIApplication, screen: String,
                                modal: Bool = false) throws {
        revealForReading(element, in: app, screen: screen, modal: modal)
        try audit(app, screen: screen)
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

private extension XCTestCase {
    /// Scroll without momentum so the screenshot records the complete passage,
    /// rather than relying on isHittable (which also accepts partly visible text).
    @MainActor @discardableResult
    func revealForReading(_ element: XCUIElement, in app: XCUIApplication, screen: String,
                          modal: Bool = false) -> CGRect {
        XCTAssertTrue(element.waitForExistence(timeout: 5), screen)
        let scroll = app.scrollViews.firstMatch
        let screenFrame = app.frame
        let top = max(scroll.frame.minY + 12, screenFrame.minY + 70)
        let bottom = modal ? min(scroll.frame.maxY - 16, screenFrame.maxY - 30)
            : min(scroll.frame.maxY - 12, app.buttons["Passport"].frame.minY - 18)
        let middle = (top + bottom) / 2
        for _ in 0..<30 {
            let frame = element.frame
            if frame.minY >= top && frame.maxY <= bottom { break }
            let desired = frame.height <= bottom - top ? frame.midY : frame.minY + (bottom - top) / 2
            let offset = max(-240, min(240, desired - middle))
            if abs(offset) < 10 { break }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: screenFrame.midX, dy: middle))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: screenFrame.midX, dy: middle - offset))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        let diagnostic = XCTAttachment(string: "Target \(element.label) frame \(element.frame). Visible reading region y=\(top)...\(bottom).\n\(element.debugDescription)")
        diagnostic.name = screen + " bounds"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTAssertTrue(element.isHittable, screen)
        return CGRect(x: screenFrame.minX, y: top, width: screenFrame.width, height: bottom - top)
    }
}

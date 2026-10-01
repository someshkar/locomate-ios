import XCTest

final class NavigationUITests: XCTestCase {
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
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

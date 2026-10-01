import XCTest

final class NavigationUITests: XCTestCase {
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

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

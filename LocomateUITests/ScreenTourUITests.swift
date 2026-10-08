import XCTest

/// Walks the primary surfaces against a real gateway and writes one PNG per
/// screen to `LOCOMATE_TOUR_DIR`, for design review against the Doop canvas.
/// Skipped unless both `LOCOMATE_TOUR_DIR` and `LOCOMATE_TOUR_GATEWAY` are set.
final class ScreenTourUITests: XCTestCase {
    @MainActor
    func testScreenTour() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["LOCOMATE_TOUR_DIR"], let gateway = env["LOCOMATE_TOUR_GATEWAY"] else {
            throw XCTSkip("Set LOCOMATE_TOUR_DIR and LOCOMATE_TOUR_GATEWAY to run the screen tour")
        }
        let train = env["LOCOMATE_TOUR_TRAIN"] ?? "12951"
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = gateway
        app.launch()

        func shot(_ name: String, settle: TimeInterval = 1.5) {
            Thread.sleep(forTimeInterval: settle)
            let png = XCUIScreen.main.screenshot().pngRepresentation
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }

        XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 15))
        shot("01-journeys", settle: 3)

        app.buttons["Find a train"].tap()
        shot("02-search-empty")
        let field = app.textFields["Search trains"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(train)
        let result = app.buttons["\(train) "].firstMatch
        let number = app.staticTexts["search.result.number.\(train)"]
        XCTAssertTrue(number.waitForExistence(timeout: 20))
        shot("03-search-results")
        if result.exists { result.tap() } else { number.tap() }

        shot("04-journey-collapsed", settle: 6)
        let sheet = app.otherElements["journey.sheet"].firstMatch
        if sheet.exists { sheet.swipeUp() } else { app.swipeUp() }
        shot("05-journey-expanded", settle: 2)
        app.swipeUp()
        shot("06-journey-scrolled", settle: 1.5)

        app.buttons["Explore"].tap()
        shot("07-explore", settle: 6)

        app.buttons["Passport"].tap()
        shot("08-passport", settle: 3)
    }
}

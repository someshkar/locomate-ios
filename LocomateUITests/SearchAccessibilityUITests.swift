import XCTest

final class SearchAccessibilityUITests: XCTestCase {
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
        XCTAssertTrue(result.waitForExistence(timeout: 10))
        XCTAssertEqual(result.label, "12951 \(fullName)")

        reveal(source, in: scroll, app: app)
        XCTAssertEqual(number.label, "12951")
        XCTAssertEqual(source.label, "HISTORICAL ROUTE PACK")
        XCTAssertGreaterThanOrEqual(source.frame.minY, number.frame.maxY)
        capture(app, "Largest Search result number and source")

        reveal(name, in: scroll, app: app)
        XCTAssertEqual(name.label, fullName)
        XCTAssertGreaterThan(name.frame.height, number.frame.height * 2,
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
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        func region() -> CGRect {
            let frame = scroll.frame
            let top = max(frame.minY, 64) + 8
            return CGRect(x: frame.minX + 8, y: top, width: frame.width - 16,
                          height: max(0, min(frame.maxY, app.frame.maxY - 34) - top - 8))
        }
        for _ in 0..<24 {
            let reading = region()
            if element.exists && element.isHittable && reading.contains(element.frame) { return }
            let frame = element.frame
            let downward = frame.minY < reading.minY
            let overflow = downward ? reading.minY - frame.minY : frame.maxY - reading.maxY
            let distance = min(160, max(40, overflow + 12), max(40, reading.height - 48))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: scroll.frame.minX + 2, dy: reading.midY + (downward ? -distance / 2 : distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: scroll.frame.minX + 2, dy: reading.midY + (downward ? distance / 2 : -distance / 2)))
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

import XCTest

final class PersonalJourneyUITests: XCTestCase {
    @MainActor func testPrivateCoachSeatSurviveRestartAndRemainSeparateFromEquipmentReporting() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch(); defer { app.terminate() }
        let edit = app.buttons["Edit your journey"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10)); edit.tap()
        let coach = app.textFields["journey.plan.coach"]
        let seat = app.textFields["journey.plan.seat"]
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
        coach.tap(); coach.typeText("B2")
        seat.tap(); seat.typeText("42 LB")
        app.buttons["Save"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(edit.waitForExistence(timeout: 10)); edit.tap()
        XCTAssertTrue(coach.waitForExistence(timeout: 5))
        XCTAssertEqual(coach.value as? String, "B2")
        XCTAssertEqual(seat.value as? String, "42 LB")
        let saved = XCTAttachment(screenshot: app.screenshot()); saved.name = "Private reservation details after cold restart"; saved.lifetime = .keepAlways; add(saved)
        coach.tap(); coach.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        seat.tap(); seat.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 5))
        app.buttons["Save"].tap()
        let expand = app.buttons["Expand journey details"]
        if expand.exists { expand.tap() }
        let insights = app.buttons["Insights"]
        XCTAssertTrue(insights.waitForExistence(timeout: 5)); insights.tap()
        let report = app.buttons["physicalSightings.open"]
        for _ in 0..<12 where !report.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(report.exists)
        XCTAssertFalse(report.isEnabled, "Preview data cannot authorize a public physical equipment report.")
        let physical = XCTAttachment(screenshot: app.screenshot()); physical.name = "Separate physical assignment evidence and disabled preview reporting"; physical.lifetime = .keepAlways; add(physical)
    }
}

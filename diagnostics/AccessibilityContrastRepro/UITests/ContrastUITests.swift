import XCTest
final class ContrastUITests: XCTestCase {
    @MainActor private func check(_ sample: String) throws {
        let app = XCUIApplication()
        app.launchEnvironment["CONTRAST_SAMPLE"] = sample
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "The origin date")).firstMatch.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = sample; attachment.lifetime = .keepAlways
        add(attachment)
        try app.performAccessibilityAudit(for: .contrast) { _ in false }
    }
    @MainActor func testSwiftUIStyle() throws { try check("style") }
    @MainActor func testSwiftUIColor() throws { try check("color") }
    @MainActor func testSwiftUISystem() throws { try check("system") }
    @MainActor func testShapeScroll() throws { try check("scroll-shape") }
    @MainActor func testSolidScroll() throws { try check("scroll-solid") }
    @MainActor func testScroll() throws { try check("scroll") }
    @MainActor func testMapScroll() throws { try check("map") }
    @MainActor func testUIKit() throws { try check("uikit") }
}

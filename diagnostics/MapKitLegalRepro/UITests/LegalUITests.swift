import XCTest

final class LegalUITests: XCTestCase {
    @MainActor func testNativeMapKitLegalActivation() {
        for mode in ["standard", "hybrid"] {
            let app = XCUIApplication()
            app.launchEnvironment["MAP_MODE"] = mode
            app.launch()
            let legal = app.links["Legal"].firstMatch
            XCTAssertTrue(legal.waitForExistence(timeout: 15))
            XCTAssertTrue(legal.isHittable, "Pure UIKit MapKit Legal link is not hittable in \(mode) mode.")
            let hierarchy = XCTAttachment(string: "Legal frame \(legal.frame), app state \(app.state).\n\(app.debugDescription)")
            hierarchy.name = "Pure UIKit \(mode) hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: legal.frame.midX, dy: legal.frame.midY)).tap()
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Pure UIKit \(mode) after Legal tap"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }
}

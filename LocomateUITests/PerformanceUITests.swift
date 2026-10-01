import XCTest
import UIKit

/// Explicitly opt-in. A successful dry run proves the workload can run, not that
/// startup, memory, frame rate, or hitch targets have been met.
final class PerformanceUITests: XCTestCase {
    private var environment: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunchToResponsiveOnDevice() throws {
        try requireDeviceMeasurement()
        let app = try productionApp()
        attachConditions(workload: "Process launch to first responsive frame; production empty Journey")
        let options = measurementOptions()
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            stopMeasuring()
            XCTAssertTrue(app.buttons["Find a train"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    @MainActor
    func testMapSheetAndSearchOnDevice() throws {
        try requireDeviceMeasurement()
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("App hitch measurement requires iOS 26+. Profile older supported devices with Instruments.")
        }
        let app = try productionApp()
        let train = try requiredValue("LOCOMATE_PERFORMANCE_TRAIN_NUMBER", pattern: "^[0-9]{4,6}$")
        let date = try requiredValue("LOCOMATE_PERFORMANCE_SERVICE_DATE", pattern: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$")
        let route = try XCTUnwrap(URL(string: "locomate://journeys/\(train)?date=\(date)"))
        app.launch()
        app.open(route)
        XCTAssertTrue(app.buttons["Expand journey details"].waitForExistence(timeout: 30),
                      "A real dated run must load before the measured workload starts.")
        XCTAssertFalse(app.staticTexts["Timetable sample"].exists)
        attachConditions(workload: "Loaded dated run \(train):\(date); map, sheet, Trip content, Search")
        // These metrics observe the app process, not the UI-test runner. Network
        // setup is outside this interval. Every iteration returns to one detent.
        measure(metrics: [XCTHitchMetric(application: app), XCTMemoryMetric(application: app)],
                options: measurementOptions()) {
            exerciseMapSheetAndSearch(app)
        }
        app.terminate()
    }

    @MainActor
    func testPerformanceWorkloadDryRun() throws {
        guard environment["LOCOMATE_PERFORMANCE_MODE"] == "dry-run" else {
            throw XCTSkip("Set LOCOMATE_PERFORMANCE_MODE=dry-run to check the workload without recording performance.")
        }
        let app = XCUIApplication()
        // The ordinary historical route pack makes this path deterministic.
        // Production measurements above require a configured real gateway/run.
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = ""
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["Expand journey details"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Timetable sample"].exists)
        exerciseMapSheetAndSearch(app)
        let evidence = XCTAttachment(string: "DRY RUN ONLY. Historical route pack. No performance metrics or performance pass recorded.")
        evidence.lifetime = .keepAlways
        add(evidence)
        app.terminate()
    }

    private func requireDeviceMeasurement() throws {
        guard environment["LOCOMATE_PERFORMANCE_MODE"] == "measure" else {
            throw XCTSkip("Use the LocomatePerformance scheme with LOCOMATE_PERFORMANCE_MODE=measure on a physical device.")
        }
        #if targetEnvironment(simulator)
        throw XCTSkip("Simulator timing cannot establish the device performance targets. Use dry-run for workload validation.")
        #elseif DEBUG
        throw XCTSkip("Performance measurements require the optimized Release configuration.")
        #endif
    }

    @MainActor
    private func productionApp() throws -> XCUIApplication {
        let raw = environment["LOCOMATE_PERFORMANCE_GATEWAY_URL"] ?? ""
        let url = try XCTUnwrap(URLComponents(string: raw))
        XCTAssertEqual(url.scheme, "https", "Use an authorized HTTPS production or staging rail gateway.")
        XCTAssertNotNil(url.host)
        XCTAssertNil(url.user)
        XCTAssertNil(url.password)
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
        // Stop before a malformed setup can silently fall back to preview.
        guard url.scheme == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
            throw ConfigurationError.invalidGateway
        }
        let app = XCUIApplication()
        app.launchEnvironment["LOCOMOTE_RAIL_API_URL"] = raw
        app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        return app
    }

    private func requiredValue(_ key: String, pattern: String) throws -> String {
        let value = environment[key] ?? ""
        XCTAssertNotNil(value.range(of: pattern, options: .regularExpression), "Provide \(key) for an available dated run.")
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            throw ConfigurationError.missingRun
        }
        return value
    }

    private func measurementOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        return options
    }

    @MainActor
    private func exerciseMapSheetAndSearch(_ app: XCUIApplication) {
        let expand = app.buttons["Expand journey details"]
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
        expand.tap()
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        scroll.swipeUp(velocity: .slow)
        scroll.swipeDown(velocity: .slow)
        let collapse = app.buttons["Show more map"]
        XCTAssertTrue(collapse.isHittable)
        collapse.tap()
        app.buttons["Find a train"].tap()
        let search = app.textFields["Search trains"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let grabber = app.buttons["Sheet Grabber"]
        XCTAssertTrue(grabber.isHittable)
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99)))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: search)], timeout: 5), .completed)
        XCTAssertTrue(expand.waitForExistence(timeout: 5))
    }

    @MainActor
    private func attachConditions(workload: String) {
        let info = ProcessInfo.processInfo
        let text = """
        Workload: \(workload)
        Configuration: Release, standard Dynamic Type, ten measured iterations
        Device: \(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)
        Maximum supported refresh rate: \(UIScreen.main.maximumFramesPerSecond) Hz (not measured frame rate)
        Low Power Mode: \(info.isLowPowerModeEnabled)
        Thermal state: \(info.thermalState.rawValue)
        Launch measurements terminate the process between iterations; filesystem/tile caches are not purged.
        No baseline or target is considered passed until physical measurements and traces are reviewed.
        """
        let attachment = XCTAttachment(string: text)
        attachment.name = "Performance conditions"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum ConfigurationError: Error { case invalidGateway, missingRun }
}

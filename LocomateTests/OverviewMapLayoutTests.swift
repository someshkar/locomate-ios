import XCTest
import SwiftUI
import MapKit
@testable import Locomate

@MainActor
final class OverviewMapLayoutTests: XCTestCase {
    func testFullNativeMapUnderSheetAndDockQueriesOnlyExposedViewport() async throws {
        let state = OverviewTestState()
        let (window, host) = hostPage(state)
        defer { window.isHidden = true; window.rootViewController = nil }
        let surface = try await renderedMap(in: host.view)
        let map = surface.mapView
        let frame = map.convert(map.bounds, to: window)
        XCTAssertEqual(frame.minY, window.bounds.minY, accuracy: 1)
        XCTAssertEqual(frame.maxY, window.bounds.maxY, accuracy: 1,
                       "The native map must extend under the sheet, floating dock and bottom safe area.")
        XCTAssertEqual(frame.width, window.bounds.width, accuracy: 1)
        XCTAssertTrue(map.preferredConfiguration is MKHybridMapConfiguration)
        let viewport = try XCTUnwrap(surface.exposedViewport)
        XCTAssertGreaterThanOrEqual(viewport.minY, window.safeAreaInsets.top)
        XCTAssertGreaterThanOrEqual(viewport.height, 128)
        XCTAssertLessThanOrEqual(viewport.height, 190)
        XCTAssertEqual(map.layoutMargins.bottom, map.bounds.maxY - viewport.maxY + 8, accuracy: 1)
        let center = map.convert(CLLocationCoordinate2D(latitude: 22.6, longitude: 79.5), toPointTo: map)
        XCTAssertTrue(viewport.contains(center), "The initial regional camera must be centered in the exposed map: \(center), \(viewport)")

        let requested = try XCTUnwrap(state.bounds.last)
        let projected = try XCTUnwrap(surface.visibleNetworkBounds)
        XCTAssertEqual(requested.south, projected.south, accuracy: 0.00001)
        XCTAssertEqual(requested.north, projected.north, accuracy: 0.00001)
        let fullRegion = map.convert(map.bounds, toRegionFrom: map)
        XCTAssertLessThan(requested.north - requested.south, fullRegion.span.latitudeDelta / 2,
                          "Covered geography must not be requested as visible network data.")
        let scroll = try XCTUnwrap(descendants(host.view, of: UIScrollView.self).first)
        let scrollFrame = scroll.convert(scroll.bounds, to: window)
        XCTAssertEqual(scrollFrame.minY, frame.minY + viewport.maxY, accuracy: 1)
        let readingBottom = scrollFrame.maxY - scroll.adjustedContentInset.bottom
        XCTAssertLessThan(readingBottom, window.bounds.maxY - 70,
                          "The native scroll inset must keep its reading area above the dock: frame \(scrollFrame), inset \(scroll.adjustedContentInset)")
        capture(host.view, name: "Full native Explore map beneath glass and dock")
    }

    func testViewportChangesAndKeyboardCollapseKeepNativeMapAndCamera() async throws {
        let state = OverviewTestState()
        let (window, host) = hostPage(state)
        defer { window.isHidden = true; window.rootViewController = nil }
        let surface = try await renderedMap(in: host.view)
        let map = surface.mapView
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 26, longitude: 80),
                                        span: .init(latitudeDelta: 3, longitudeDelta: 5)), animated: false)
        try await Task.sleep(for: .milliseconds(250))
        let camera = map.camera.copy() as! MKMapCamera
        let queryCount = state.bounds.count
        state.hidden = true
        try await settle(host.view)
        XCTAssertTrue(descendants(host.view, of: OverviewMapContainer.self).first?.mapView === map)
        XCTAssertNil(surface.exposedViewport)
        XCTAssertNil(surface.visibleNetworkBounds)
        XCTAssertEqual(state.bounds.count, queryCount, "A hidden keyboard viewport must not query network positions.")
        state.hidden = false
        try await settle(host.view)
        XCTAssertTrue(descendants(host.view, of: OverviewMapContainer.self).first?.mapView === map)
        XCTAssertEqual(map.camera.centerCoordinate.latitude, camera.centerCoordinate.latitude, accuracy: 0.001)
        XCTAssertEqual(map.camera.centerCoordinate.longitude, camera.centerCoordinate.longitude, accuracy: 0.001)
        XCTAssertEqual(map.camera.centerCoordinateDistance, camera.centerCoordinateDistance, accuracy: 1)

        state.textSize = .accessibility5
        try await settle(host.view)
        XCTAssertTrue(descendants(host.view, of: OverviewMapContainer.self).first?.mapView === map)
        XCTAssertEqual(try XCTUnwrap(surface.exposedViewport).height, 96, accuracy: 1)
        XCTAssertEqual(map.camera.centerCoordinate.latitude, camera.centerCoordinate.latitude, accuracy: 0.001)
        XCTAssertEqual(map.camera.centerCoordinate.longitude, camera.centerCoordinate.longitude, accuracy: 0.001)
        let latest = try XCTUnwrap(state.bounds.last)
        let projected = try XCTUnwrap(surface.visibleNetworkBounds)
        XCTAssertEqual(latest.south, projected.south, accuracy: 0.00001)
        XCTAssertEqual(latest.north, projected.north, accuracy: 0.00001,
                       "Viewport-only changes must publish the current exposed bounds.")
        capture(host.view, name: "Full native Explore map at largest text")

        // The exposed strip stays at 96 points when the window's
        // height changes. Native margins must still follow the resized map.
        window.frame.size.height -= 120
        host.view.frame = window.bounds
        try await settle(host.view)
        XCTAssertTrue(descendants(host.view, of: OverviewMapContainer.self).first?.mapView === map)
        let resizedViewport = try XCTUnwrap(surface.exposedViewport)
        XCTAssertEqual(resizedViewport.height, 96, accuracy: 1)
        XCTAssertEqual(map.layoutMargins.bottom, map.bounds.maxY - resizedViewport.maxY + 8, accuracy: 1)
        XCTAssertEqual(map.convert(map.bounds, to: window).maxY, window.bounds.maxY, accuracy: 1)
        let resizedBounds = try XCTUnwrap(surface.visibleNetworkBounds)
        XCTAssertEqual(try XCTUnwrap(state.bounds.last).north, resizedBounds.north, accuracy: 0.00001)
    }

    private func hostPage(_ state: OverviewTestState) -> (UIWindow, UIHostingController<OverviewTestPage>) {
        let host = UIHostingController(rootView: OverviewTestPage(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        return (window, host)
    }

    private func renderedMap(in view: UIView) async throws -> OverviewMapContainer {
        for _ in 0..<100 {
            view.layoutIfNeeded()
            if let surface = descendants(view, of: OverviewMapContainer.self).first,
               surface.exposedViewport != nil, surface.mapView.layoutMargins.bottom > 300 {
                try await Task.sleep(for: .milliseconds(700))
                return surface
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return try XCTUnwrap(descendants(view, of: OverviewMapContainer.self).first)
    }

    private func settle(_ view: UIView) async throws {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        view.layoutIfNeeded()
    }

    private func descendants<T: UIView>(_ view: UIView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }

    private func capture(_ view: UIView, name: String) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@Observable @MainActor
private final class OverviewTestState {
    var hidden = false
    var textSize = DynamicTypeSize.large
    var bounds: [NetworkBounds] = []
}

private struct OverviewTestPage: View {
    @Bindable var state: OverviewTestState

    var body: some View {
        OverviewPage(hidesMap: state.hidden) { viewport in
            NetworkMapView(markers: [], viewportOnScreen: viewport, onSelect: { _ in },
                           onInspectCluster: { _ in }, onBoundsChange: { state.bounds.append($0) })
        } sheet: {
            ExploreNetworkOverlay(production: false, markers: [], loading: false,
                                  error: nil, expired: false, generatedAt: nil)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomDock(active: .explore, onChange: { _ in })
                .frame(maxWidth: 330)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
        }
        .environment(\.locomoteColors, LocomateTheme.dark)
        .dynamicTypeSize(state.textSize)
        .preferredColorScheme(.dark)
    }
}

import Testing
import MapKit
@testable import Locomate

@Suite("Native Journey camera")
struct JourneyMapCameraTests {
    private let route = [RailCoordinate(latitude: 19.07, longitude: 72.88),
                         RailCoordinate(latitude: 30.95, longitude: 74.60)]

    @Test("Repeated focus and fit actions move the native camera above the sheet")
    @MainActor func repeatedActions() async throws {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = RailMapView.Coordinator()
        await update(coordinator, map, scope: "first", display: .preview, command: nil)
        #expect(map.layoutMargins.bottom == 330)
        let fittedSpan = map.region.span.latitudeDelta
        let focus = RailMapCommand(journeyID: "first", target: .position)
        await update(coordinator, map, scope: "first", display: .preview, command: focus)
        #expect(map.region.span.latitudeDelta < fittedSpan / 2)
        let point = try RouteGeometry.coordinate(along: route, progress: 0.5)
        let projected = map.convert(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), toPointTo: map)
        #expect(CGRect(x: 32, y: 112, width: 286, height: 380).contains(projected))
        // An unchanged command must not undo the user's subsequent pan.
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 0, longitude: 0),
                                         span: .init(latitudeDelta: 1, longitudeDelta: 1)), animated: false)
        await update(coordinator, map, scope: "first", display: .preview, command: focus)
        #expect(abs(map.region.center.latitude) < 0.1)
        await update(coordinator, map, scope: "first", display: .preview,
                     command: RailMapCommand(journeyID: "first", target: .position))
        #expect(map.region.center.latitude > 15)
        await update(coordinator, map, scope: "first", display: .preview,
                     command: RailMapCommand(journeyID: "first", target: .route))
        #expect(map.region.span.latitudeDelta > fittedSpan * 0.9)
        for point in route {
            let projected = map.convert(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), toPointTo: map)
            #expect(CGRect(x: 30, y: 110, width: 290, height: 384).contains(projected))
        }
    }

    @Test("Hidden position and a command from another dated journey cannot focus a marker")
    @MainActor func hiddenAndReplacedJourney() async {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = RailMapView.Coordinator()
        await update(coordinator, map, scope: "first", display: .observed,
                     command: RailMapCommand(journeyID: "first", target: .position))
        let focusedSpan = map.region.span.latitudeDelta
        await update(coordinator, map, scope: "first", display: .hidden, command: nil)
        #expect(map.region.span.latitudeDelta > focusedSpan * 2)
        await update(coordinator, map, scope: "second", display: .preview,
                     command: RailMapCommand(journeyID: "first", target: .position))
        #expect(map.region.span.latitudeDelta > focusedSpan * 2)
    }

    @Test("A station coordinate/name refresh updates its native callout without a state change")
    @MainActor func refreshedStation() {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = RailMapView.Coordinator()
        coordinator.update(mapView: map, journeyID: "first", route: route, progress: 0.5,
            positionDisplay: .hidden, markers: [.init(id: "B", coordinate: route[0], name: "Old name", state: .current)],
            sheetVisibleHeight: 320, cameraCommand: nil)
        coordinator.update(mapView: map, journeyID: "first", route: route, progress: 0.5,
            positionDisplay: .hidden,
            markers: [.init(id: "B", coordinate: .init(latitude: 22, longitude: 73), name: "Updated station", state: .current)],
            sheetVisibleHeight: 320, cameraCommand: nil)
        #expect(map.annotations.contains { $0.title == "Updated station (B)" && $0.coordinate.latitude == 22 })
        #expect(!map.annotations.contains { $0.title == "Old name (B)" })
    }

    @MainActor private func update(_ coordinator: RailMapView.Coordinator, _ map: MKMapView,
                                    scope: String, display: JourneyPositionDisplay, command: RailMapCommand?) async {
        coordinator.update(mapView: map, journeyID: scope, route: route, progress: 0.5,
                           positionDisplay: display, markers: [], sheetVisibleHeight: 320, cameraCommand: command,
                           attributionTopOnScreen: 524)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        map.layoutIfNeeded()
    }
}

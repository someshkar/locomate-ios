import SwiftUI
import MapKit

struct MapStationMarker: Identifiable, Equatable {
    let id: String
    let coordinate: RailCoordinate
    let state: StopState
}

/// Apple Maps route surface with a glowing rail line and sheet-aware camera.
struct RailMapView: UIViewRepresentable {
    let route: [RailCoordinate]
    let progress: Double
    let preview: Bool
    let markers: [MapStationMarker]
    let daylight: MapDaylight
    let lightingMode: Preferences.MapLighting
    let sheetVisibleHeight: Double

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = .hybridFlyover
        mapView.overrideUserInterfaceStyle = lightingMode == .day ? .light : .dark
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.showsUserLocation = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.overrideUserInterfaceStyle = lightingMode == .day ? .light : .dark
        context.coordinator.update(mapView: mapView, route: route, progress: progress,
                                   preview: preview, markers: markers, sheetVisibleHeight: sheetVisibleHeight)
    }

    @MainActor final class Coordinator: NSObject, @preconcurrency MKMapViewDelegate {
        private var previousRoute: [RailCoordinate] = []
        private var glow: MKPolyline?
        private var line: MKPolyline?
        private var stationAnnotations: [RailAnnotation] = []
        private var trainAnnotation: RailAnnotation?
        private var previousMarkers = ""
        private var previousProgress = -1.0
        private var previousPreview: Bool?
        private var previousSheetHeight = -1.0
        private var fitted = false

        func update(mapView: MKMapView, route: [RailCoordinate], progress: Double, preview: Bool,
                    markers: [MapStationMarker], sheetVisibleHeight: Double) {
            guard route.count >= 2 else { return }
            if route != previousRoute {
                previousRoute = route
                if let glow { mapView.removeOverlay(glow) }
                if let line { mapView.removeOverlay(line) }
                var coordinates = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                let glow = MKPolyline(coordinates: &coordinates, count: coordinates.count)
                let line = MKPolyline(coordinates: &coordinates, count: coordinates.count)
                self.glow = glow
                self.line = line
                mapView.addOverlays([glow, line], level: .aboveRoads)
                fitted = false
                previousProgress = -1
            }

            let visibleMarkers = markers.enumerated().filter { index, marker in
                index == 0 || index == markers.count - 1 || marker.state == .current
            }.map(\.element)
            let markerKey = visibleMarkers.map { "\($0.id):\($0.state.rawValue)" }.joined(separator: ",")
            if markerKey != previousMarkers {
                previousMarkers = markerKey
                mapView.removeAnnotations(stationAnnotations)
                stationAnnotations = visibleMarkers.map { marker in
                    RailAnnotation(
                        coordinate: CLLocationCoordinate2D(latitude: marker.coordinate.latitude,
                                                           longitude: marker.coordinate.longitude),
                        title: marker.id, kind: .station
                    )
                }
                mapView.addAnnotations(stationAnnotations)
            }

            if abs(progress - previousProgress) > 0.0001 || previousPreview != preview {
                previousProgress = progress
                previousPreview = preview
                if let point = try? RouteGeometry.coordinate(along: route, progress: progress) {
                    trainAnnotation.map { mapView.removeAnnotation($0) }
                    let train = RailAnnotation(
                        coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                        title: preview ? "Historical route sample · not live" : "Train position · verify source in journey details",
                        kind: preview ? .preview : .train
                    )
                    trainAnnotation = train
                    mapView.addAnnotation(train)
                }
            }

            if !fitted || abs(previousSheetHeight - sheetVisibleHeight) > 48 {
                previousSheetHeight = sheetVisibleHeight
                fitted = true
                DispatchQueue.main.async { [weak mapView] in
                    guard let mapView, mapView.bounds.height > 100 else { return }
                    Self.fit(route, on: mapView, sheetVisibleHeight: sheetVisibleHeight)
                }
            }
        }

        private static func fit(_ route: [RailCoordinate], on mapView: MKMapView, sheetVisibleHeight: Double) {
            let points = route.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            guard let first = points.first else { return }
            let rect = points.dropFirst().reduce(MKMapRect(x: first.x, y: first.y, width: 0, height: 0)) {
                $0.union(MKMapRect(x: $1.x, y: $1.y, width: 0, height: 0))
            }
            let padding = UIEdgeInsets(top: 95, left: 42,
                bottom: min(CGFloat(sheetVisibleHeight) + 45, mapView.bounds.height - 160), right: 42)
            mapView.setVisibleMapRect(rect, edgePadding: padding, animated: false)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            let renderer = MKPolylineRenderer(overlay: overlay)
            renderer.lineCap = .round
            renderer.lineJoin = .round
            if let glow, overlay === glow {
                renderer.strokeColor = UIColor(red: 0.37, green: 0.68, blue: 0.96, alpha: 0.35)
                renderer.lineWidth = 13
            } else {
                renderer.strokeColor = UIColor(red: 0.37, green: 0.68, blue: 0.96, alpha: 1)
                renderer.lineWidth = 4.5
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let point = annotation as? RailAnnotation else { return nil }
            let reuse = point.kind == .train ? "train-dot" : (point.kind == .preview ? "preview-dot" : "station-dot")
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: reuse)
                ?? MKAnnotationView(annotation: point, reuseIdentifier: reuse)
            view.annotation = point
            let size: CGFloat = point.kind == .station ? 10 : 20
            view.frame = CGRect(x: 0, y: 0, width: size, height: size)
            view.layer.cornerRadius = size / 2
            view.layer.borderWidth = point.kind == .station ? 1.5 : 3
            view.layer.borderColor = UIColor.white.cgColor
            view.backgroundColor = point.kind == .preview
                ? UIColor(red: 0.61, green: 0.55, blue: 1, alpha: 1)
                : (point.kind == .train
                    ? UIColor(red: 0.0, green: 0.62, blue: 0.98, alpha: 1)
                    : UIColor(red: 0.37, green: 0.68, blue: 0.96, alpha: 1))
            view.layer.shadowColor = UIColor(red: 0.37, green: 0.68, blue: 0.96, alpha: 1).cgColor
            view.layer.shadowRadius = point.kind == .station ? 5 : 12
            view.layer.shadowOpacity = 0.8
            view.layer.shadowOffset = .zero
            view.canShowCallout = true
            view.displayPriority = point.kind == .station ? .defaultLow : .required
            return view
        }
    }
}

private final class RailAnnotation: NSObject, MKAnnotation {
    enum Kind { case train, preview, station }
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let kind: Kind

    init(coordinate: CLLocationCoordinate2D, title: String, kind: Kind) {
        self.coordinate = coordinate
        self.title = title
        self.kind = kind
    }
}

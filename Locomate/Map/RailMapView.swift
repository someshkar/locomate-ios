import SwiftUI
import MapKit

/// An unannotated native basemap. Saved summaries contain no verified route geometry.
struct PassportMapBackdrop: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.mapType = .hybridFlyover
        map.overrideUserInterfaceStyle = .dark
        map.showsCompass = false
        map.isScrollEnabled = false
        map.isZoomEnabled = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.6, longitude: 79.5),
            span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 18)
        ), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}
}

struct MapStationMarker: Identifiable, Equatable {
    let id: String
    let coordinate: RailCoordinate
    var name: String? = nil
    let state: StopState
}

struct RailMapCommand: Equatable {
    enum Target { case route, position }
    let id = UUID()
    let journeyID: String
    let target: Target
}

/// Apple Maps route surface with a glowing rail line and sheet-aware camera.
struct RailMapView: UIViewRepresentable {
    let journeyID: String
    let route: [RailCoordinate]
    let progress: Double
    let positionDisplay: JourneyPositionDisplay
    let markers: [MapStationMarker]
    let daylight: MapDaylight
    let lightingMode: Preferences.MapLighting
    let sheetVisibleHeight: Double
    let cameraCommand: RailMapCommand?
    var sheetTopOnScreen: Double? = nil
    var attributionTopOnScreen: Double? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = .hybrid
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
        context.coordinator.update(mapView: mapView, journeyID: journeyID, route: route, progress: progress,
                                   positionDisplay: positionDisplay, markers: markers,
                                   sheetVisibleHeight: sheetVisibleHeight, cameraCommand: cameraCommand,
                                   sheetTopOnScreen: sheetTopOnScreen,
                                   attributionTopOnScreen: attributionTopOnScreen)
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        private var previousRoute: [RailCoordinate] = []
        private var glow: MKPolyline?
        private var line: MKPolyline?
        private var stationAnnotations: [RailAnnotation] = []
        private var trainAnnotation: RailAnnotation?
        private var previousMarkers = ""
        private var previousProgress = -1.0
        private var previousPositionDisplay: JourneyPositionDisplay?
        private var previousSheetHeight = -1.0
        private var fitted = false
        private var previousJourneyID = ""
        private var previousCommandID: UUID?
        private var cameraTarget: RailMapCommand.Target = .route
        private var cameraRevision = 0
        private var previousSheetTop: Double?
        private var previousAttributionTop: Double?

        func update(mapView: MKMapView, journeyID: String, route: [RailCoordinate], progress: Double,
                    positionDisplay: JourneyPositionDisplay,
                    markers: [MapStationMarker], sheetVisibleHeight: Double,
                    cameraCommand: RailMapCommand?, sheetTopOnScreen: Double? = nil,
                    attributionTopOnScreen: Double? = nil) {
            guard route.count >= 2 else { return }
            if journeyID != previousJourneyID {
                previousJourneyID = journeyID
                cameraTarget = .route
                fitted = false
            }
            if let cameraCommand, cameraCommand.journeyID == journeyID,
               cameraCommand.id != previousCommandID {
                previousCommandID = cameraCommand.id
                cameraTarget = cameraCommand.target
                fitted = false
            }
            if cameraTarget == .position && positionDisplay == .hidden {
                cameraTarget = .route
                fitted = false
            }
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
            let markerKey = visibleMarkers.map {
                "\($0.id):\($0.state.rawValue):\($0.coordinate.latitude):\($0.coordinate.longitude):\($0.name ?? "")"
            }.joined(separator: ",")
            if markerKey != previousMarkers {
                previousMarkers = markerKey
                mapView.removeAnnotations(stationAnnotations)
                stationAnnotations = visibleMarkers.map { marker in
                    RailAnnotation(
                        coordinate: CLLocationCoordinate2D(latitude: marker.coordinate.latitude,
                                                           longitude: marker.coordinate.longitude),
                        title: marker.name.map { "\($0) (\(marker.id))" } ?? marker.id, kind: .station
                    )
                }
                mapView.addAnnotations(stationAnnotations)
            }

            if abs(progress - previousProgress) > 0.0001 || previousPositionDisplay != positionDisplay {
                previousProgress = progress
                previousPositionDisplay = positionDisplay
                trainAnnotation.map { mapView.removeAnnotation($0) }
                trainAnnotation = nil
                if positionDisplay != .hidden,
                   let point = try? RouteGeometry.coordinate(along: route, progress: progress) {
                    let title: String = switch positionDisplay {
                        case .preview: "Historical route sample · not live"
                        case .observed: "Observed train position"
                        case .stale: "Last observed position · stale"
                        case .hidden: ""
                    }
                    let kind: RailAnnotation.Kind = switch positionDisplay {
                        case .preview: .preview
                        case .observed: .train
                        case .stale: .stale
                        case .hidden: .train
                    }
                    let train = RailAnnotation(
                        coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                        title: title,
                        kind: kind
                    )
                    trainAnnotation = train
                    mapView.addAnnotation(train)
                }
            }

            if !fitted || abs(previousSheetHeight - sheetVisibleHeight) > 48 || previousSheetTop != sheetTopOnScreen
                || previousAttributionTop != attributionTopOnScreen {
                previousSheetHeight = sheetVisibleHeight
                previousSheetTop = sheetTopOnScreen
                previousAttributionTop = attributionTopOnScreen
                fitted = true
                cameraRevision += 1
                let revision = cameraRevision
                let target = cameraTarget
                DispatchQueue.main.async { [weak self, weak mapView] in
                    guard let self, revision == self.cameraRevision,
                          let mapView, mapView.bounds.height > 100 else { return }
                    // Public margins keep Apple's attribution above the resting sheet.
                    // Keep the map full size so expanding/collapsing preserves its surface.
                    let covered = attributionTopOnScreen.map {
                        mapView.convert(mapView.bounds, to: nil).maxY - CGFloat($0)
                    } ?? CGFloat(sheetVisibleHeight)
                    mapView.layoutMargins = UIEdgeInsets(top: 0, left: 7,
                        bottom: min(max(0, covered) + 10, max(0, mapView.bounds.height - 120)), right: 7)
                    mapView.layoutIfNeeded()
                    if target == .position, positionDisplay != .hidden, progress.isFinite,
                       let point = try? RouteGeometry.coordinate(along: route, progress: progress) {
                        Self.focus(point, on: mapView, sheetVisibleHeight: sheetVisibleHeight, sheetTopOnScreen: sheetTopOnScreen)
                    } else {
                        Self.fit(route, on: mapView, sheetVisibleHeight: sheetVisibleHeight, sheetTopOnScreen: sheetTopOnScreen)
                    }
                }
            }
        }

        private static func padding(on mapView: MKMapView, sheetVisibleHeight: Double, sheetTopOnScreen: Double?) -> UIEdgeInsets {
            let obscured = sheetTopOnScreen.map { mapView.convert(mapView.bounds, to: nil).maxY - CGFloat($0) }
                ?? CGFloat(sheetVisibleHeight)
            let requested = UIEdgeInsets(top: 112, left: 32,
                bottom: min(max(0, obscured) + 32, max(0, mapView.bounds.height - 212)), right: 72)
            // MapKit also applies its layout margins to the camera. Account for
            // them once, otherwise the route loses the visible space above the sheet.
            let margins = mapView.layoutMargins
            return UIEdgeInsets(top: max(0, requested.top - margins.top),
                left: max(0, requested.left - margins.left),
                bottom: max(0, requested.bottom - margins.bottom),
                right: max(0, requested.right - margins.right))
        }

        private static func fit(_ route: [RailCoordinate], on mapView: MKMapView, sheetVisibleHeight: Double, sheetTopOnScreen: Double?) {
            let points = route.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
            guard let first = points.first else { return }
            let rect = points.dropFirst().reduce(MKMapRect(x: first.x, y: first.y, width: 0, height: 0)) {
                $0.union(MKMapRect(x: $1.x, y: $1.y, width: 0, height: 0))
            }
            mapView.setVisibleMapRect(rect, edgePadding: padding(on: mapView, sheetVisibleHeight: sheetVisibleHeight, sheetTopOnScreen: sheetTopOnScreen), animated: false)
        }

        private static func focus(_ point: RailCoordinate, on mapView: MKMapView, sheetVisibleHeight: Double, sheetTopOnScreen: Double?) {
            let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            let center = MKMapPoint(coordinate)
            let side = MKMapPointsPerMeterAtLatitude(point.latitude) * 90_000
            guard side.isFinite, side > 0 else { return }
            mapView.setVisibleMapRect(MKMapRect(x: center.x - side / 2, y: center.y - side / 2,
                                              width: side, height: side),
                edgePadding: padding(on: mapView, sheetVisibleHeight: sheetVisibleHeight, sheetTopOnScreen: sheetTopOnScreen), animated: false)
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
            let reuse = switch point.kind {
                case .train: "train-dot"
                case .stale: "stale-dot"
                case .preview: "preview-dot"
                case .station: "station-dot"
            }
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? RailDotAnnotationView)
                ?? RailDotAnnotationView(annotation: point, reuseIdentifier: reuse)
            view.annotation = point
            let color: UIColor = switch point.kind {
                case .preview: UIColor(red: 0.61, green: 0.55, blue: 1, alpha: 1)
                case .train: UIColor(red: 0.22, green: 0.79, blue: 0.51, alpha: 1)
                case .stale: UIColor(red: 1, green: 0.72, blue: 0.3, alpha: 1)
                case .station: UIColor(red: 0.37, green: 0.68, blue: 0.96, alpha: 1)
            }
            view.configureDot(size: point.kind == .station ? 10 : 20, color: color)
            view.accessibilityLabel = point.title
            view.accessibilityHint = "Double-tap to show map details."
            view.canShowCallout = true
            view.displayPriority = point.kind == .station ? .defaultLow : .required
            return view
        }
    }
}

private final class RailAnnotation: NSObject, MKAnnotation {
    enum Kind { case train, stale, preview, station }
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let kind: Kind

    init(coordinate: CLLocationCoordinate2D, title: String, kind: Kind) {
        self.coordinate = coordinate
        self.title = title
        self.kind = kind
    }
}

/// The visual dot stays compact while its native selection target is 44 points.
final class RailDotAnnotationView: MKAnnotationView {
    private let dot = UIView()

    override init(annotation: (any MKAnnotation)?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        dot.isUserInteractionEnabled = false
        dot.isAccessibilityElement = false
        addSubview(dot)
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func configureDot(size: CGFloat, color: UIColor) {
        dot.frame = CGRect(x: (44 - size) / 2, y: (44 - size) / 2, width: size, height: size)
        dot.backgroundColor = color
        dot.layer.cornerRadius = size / 2
        dot.layer.borderWidth = 1.5
        dot.layer.borderColor = UIColor.white.cgColor
        dot.layer.shadowColor = color.cgColor
        dot.layer.shadowRadius = 5
        dot.layer.shadowOpacity = 0.8
        dot.layer.shadowOffset = .zero
    }
}

import MapKit

/// A full-size native map with a separately described, exposed viewport.
/// Public margins position Apple's credits; network requests use the exposed
/// rectangle rather than geographic content covered by the data sheet.
final class OverviewMapContainer: UIView {
    let mapView = MKMapView(frame: .zero)

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The exposed screen rectangle already includes the status/dock insets.
        mapView.insetsLayoutMarginsFromSafeArea = false
        addSubview(mapView)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        mapView.insetsLayoutMarginsFromSafeArea = false
        addSubview(mapView)
    }

    var viewportOnScreen: CGRect? {
        didSet {
            guard viewportOnScreen != oldValue else { return }
            setNeedsLayout()
        }
    }
    var onViewportChange: ((OverviewMapContainer) -> Void)?
    private var previousViewport: CGRect?
    private var previousBounds = CGRect.zero
    private var fittedInitialCamera = false

    var exposedViewport: CGRect? {
        guard mapView.bounds.width > 0, mapView.bounds.height > 0 else { return nil }
        let requested = viewportOnScreen.map { mapView.convert($0, from: nil) } ?? mapView.bounds
        let clipped = requested.intersection(mapView.bounds)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }

    var visibleNetworkBounds: NetworkBounds? {
        guard let viewport = exposedViewport else { return nil }
        let region = mapView.convert(viewport, toRegionFrom: mapView)
        let west = max(-180, region.center.longitude - region.span.longitudeDelta / 2)
        let east = min(180, region.center.longitude + region.span.longitudeDelta / 2)
        let south = max(-90, region.center.latitude - region.span.latitudeDelta / 2)
        let north = min(90, region.center.latitude + region.span.latitudeDelta / 2)
        guard [west, east, south, north].allSatisfy(\.isFinite), west < east, south < north else { return nil }
        return NetworkBounds(west: west, south: south, east: east, north: north)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        mapView.frame = bounds
        guard window != nil else { return }
        let viewport = exposedViewport
        guard viewport != previousViewport || bounds != previousBounds else { return }
        previousViewport = viewport
        previousBounds = bounds
        if let viewport {
            mapView.layoutMargins = UIEdgeInsets(top: viewport.minY + 8, left: viewport.minX + 8,
                                                 bottom: bounds.maxY - viewport.maxY + 8,
                                                 right: bounds.maxX - viewport.maxX + 8)
            if !fittedInitialCamera {
                fittedInitialCamera = true
                let northWest = MKMapPoint(CLLocationCoordinate2D(latitude: 25.6, longitude: 70.5))
                let southEast = MKMapPoint(CLLocationCoordinate2D(latitude: 19.6, longitude: 88.5))
                let region = MKMapRect(x: northWest.x, y: northWest.y,
                                      width: southEast.x - northWest.x, height: southEast.y - northWest.y)
                mapView.setVisibleMapRect(region, edgePadding: .zero, animated: false)
            }
        }
        // Hiding Search for the keyboard preserves the last margins/camera.
        onViewportChange?(self)
    }
}

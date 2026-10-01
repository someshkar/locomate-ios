//
//  ExploreScreen.swift
//  Locomate
//
//  Full-bleed rail network map with a floating frosted header and a floating
//  stats card — ported from SmartRail `src/screens/Network/NetworkView.tsx`.
//  In preview mode the stats card states honestly that no live layer is drawn.
//

import SwiftUI
import CoreLocation
import MapKit

struct ExploreScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    @Environment(\.locomoteServices) private var services

    @State private var bounds = NetworkBounds(west: 68, south: 6, east: 98, north: 37)
    @State private var trains: [NetworkTrain] = []
    @State private var loading = false
    @State private var error: String?
    @State private var updatedAt: Date?
    @State private var refreshTask: Task<Void, Never>?

    private var production: Bool { services.mode.isProduction }

    var body: some View {
        ZStack(alignment: .top) {
            colors.canvas.ignoresSafeArea(edges: .top)
            NetworkMapView(
                trains: trains,
                onBoundsChange: { newBounds in
                    bounds = newBounds
                    scheduleRefresh()
                }
            )
            .overlay { Color.black.opacity(0.30).allowsHitTesting(false) }
            .ignoresSafeArea(edges: .top)

            header
                .padding(.horizontal, Spacing.units(4))
                .safeAreaPadding(.top)

            VStack {
                Spacer()
                statsCard
                    .padding(.horizontal, Spacing.units(4))
                    .padding(.bottom, 54)
            }
        }
        .task { await refresh() }
        .onDisappear { refreshTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center))) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rail network")
                    .font(LocomateFont.title)
                    .tracking(-1.2)
                    .foregroundStyle(colors.textPrimary)
                Text("Pan, zoom and inspect active services")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textTertiary)
            }
            Spacer(minLength: Spacing.units(3))
            if !production {
                Text("PREVIEW").eyebrow(colors.pair(for: .preview).fg)
            } else {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(trains.count)")
                        .font(LocomateFont.timeLarge)
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                        .contentTransition(.numericText())
                    Text("IN VIEW").eyebrow(colors.textTertiary)
                }
            }
        }
        .padding(Spacing.units(3.5))
        .background {
            GlassSurface(shape: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Stats card

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2)) {
            if production, !trains.isEmpty {
                HStack(spacing: Spacing.units(2)) {
                    networkStat("IN VIEW", value: trains.count)
                    networkStat("OBSERVED", value: trains.filter { $0.positionKind == .observed }.count)
                    networkStat("PREDICTED", value: trains.filter { $0.positionKind == .predicted }.count)
                }
            }
            Text(statsBody)
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Text(updatedLabel)
                .font(LocomateFont.micro)
                .monospacedDigit()
                .foregroundStyle(colors.accentBase)
        }
        .padding(Spacing.units(3.5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GlassSurface(shape: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous), heavy: true)
        }
    }

    private func networkStat(_ label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.formatted())
                .font(LocomateFont.title)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(colors.textPrimary)
            Text(label)
                .font(LocomateFont.micro)
                .foregroundStyle(colors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.units(2.5))
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(colors.raised))
    }

    private var statsBody: String {
        if !production {
            return "Connect the licensed gateway to render current trains. Preview mode never manufactures a nationwide live layer."
        }
        if let error { return "Last valid map retained. \(error)" }
        return "The visible map refreshes every minute with observed, map-matched, or explicitly estimated positions."
    }

    private var updatedLabel: String {
        guard production else { return "WAITING FOR NETWORK UPDATE" }
        if loading { return "REFRESHING NETWORK" }
        guard let updatedAt else { return "WAITING FOR NETWORK UPDATE" }
        let formatter = DateFormatter()
        formatter.timeZone = IndiaDate.timeZone
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "HH:mm"
        return "UPDATED \(formatter.string(from: updatedAt)) IST"
    }

    // MARK: Data

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func refresh() async {
        guard let service = services.railService else { return }
        loading = true
        do {
            let response = try await service.networkTrains(bounds: bounds)
            trains = response.trains
            updatedAt = Date()
            error = nil
        } catch {
            // Keep the last valid map rather than clearing it.
            self.error = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Network map (Apple MapKit)

struct NetworkMapView: UIViewRepresentable {
    let trains: [NetworkTrain]
    let onBoundsChange: (NetworkBounds) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onBoundsChange: onBoundsChange) }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.mapType = .hybridFlyover
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsCompass = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        mapView.setRegion(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 22.6, longitude: 79.5),
            span: MKCoordinateSpan(latitudeDelta: 25, longitudeDelta: 27)
        ), animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.update(mapView: mapView, trains: trains)
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        private let onBoundsChange: (NetworkBounds) -> Void
        private var annotations: [NetworkAnnotation] = []
        private var lastKey = ""
        private var lastBounds = ""

        init(onBoundsChange: @escaping (NetworkBounds) -> Void) {
            self.onBoundsChange = onBoundsChange
        }

        func update(mapView: MKMapView, trains: [NetworkTrain]) {
            let key = trains.map { "\($0.runId):\($0.coordinate.latitude),\($0.coordinate.longitude)" }.joined(separator: "|")
            guard key != lastKey else { return }
            lastKey = key
            mapView.removeAnnotations(annotations)
            annotations = trains.map { train in
                NetworkAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: train.coordinate.latitude,
                                                       longitude: train.coordinate.longitude),
                    title: "\(train.trainNumber) · \(train.name)",
                    subtitle: "\(train.positionKind.rawValue) · \(train.source.rawValue) · \(train.observedAt)",
                    observed: train.positionKind == .observed
                )
            }
            mapView.addAnnotations(annotations)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            let west = max(-180, region.center.longitude - region.span.longitudeDelta / 2)
            let east = min(180, region.center.longitude + region.span.longitudeDelta / 2)
            let south = max(-90, region.center.latitude - region.span.latitudeDelta / 2)
            let north = min(90, region.center.latitude + region.span.latitudeDelta / 2)
            guard west < east, south < north else { return }
            let bounds = NetworkBounds(west: west, south: south, east: east, north: north)
            let key = String(format: "%.2f,%.2f,%.2f,%.2f", west, south, east, north)
            guard key != lastBounds else { return }
            lastBounds = key
            onBoundsChange(bounds)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let reuse = "train-cluster"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: reuse)
                view.annotation = cluster
                view.markerTintColor = UIColor(red: 0, green: 0.62, blue: 0.98, alpha: 1)
                view.glyphText = "\(cluster.memberAnnotations.count)"
                view.displayPriority = .defaultHigh
                view.canShowCallout = true
                return view
            }
            guard let train = annotation as? NetworkAnnotation else { return nil }
            let reuse = train.observed ? "observed-train" : "estimated-train"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? RailDotAnnotationView)
                ?? RailDotAnnotationView(annotation: train, reuseIdentifier: reuse)
            view.annotation = train
            view.configureDot(size: 13, color: train.observed
                ? UIColor(red: 0.22, green: 0.79, blue: 0.51, alpha: 1)
                : UIColor(red: 1, green: 0.72, blue: 0.30, alpha: 1))
            view.accessibilityLabel = train.title
            view.accessibilityValue = train.subtitle
            view.accessibilityHint = "Double-tap to show train details."
            view.canShowCallout = true
            view.clusteringIdentifier = "locomate-trains"
            view.displayPriority = .defaultLow
            view.collisionMode = .circle
            return view
        }
    }
}

private final class NetworkAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let observed: Bool

    init(coordinate: CLLocationCoordinate2D, title: String, subtitle: String, observed: Bool) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.observed = observed
    }
}

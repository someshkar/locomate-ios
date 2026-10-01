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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locomoteColors) private var colors
    @Environment(\.locomoteServices) private var services

    @State private var network = NetworkSnapshotModel()
    @State private var refreshTask: Task<Void, Never>?

    private var production: Bool { services.mode.isProduction }
    private var markers: [NetworkMarker] { network.markers }

    var body: some View {
        ZStack(alignment: .top) {
            colors.canvas.ignoresSafeArea(edges: .top)
            NetworkMapView(
                markers: markers,
                onBoundsChange: { newBounds in
                    network.setBounds(newBounds)
                    scheduleRefresh()
                }
            )
            .overlay { Color.black.opacity(0.30).allowsHitTesting(false) }
            .ignoresSafeArea(edges: .top)

            ExploreNetworkOverlay(production: production, markers: markers,
                                  loading: network.loading, error: network.error,
                                  expired: network.expired, generatedAt: network.snapshot?.generatedAt)
        }
        .task(id: scenePhase) {
            guard production, scenePhase == .active else { return }
            while !Task.isCancelled {
                let started = Date()
                await refresh()
                let remaining = max(0, 60 - Date().timeIntervalSince(started))
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
            }
        }
        .task(id: scenePhase) {
            guard production, scenePhase == .active else { return }
            while !Task.isCancelled {
                network.tick()
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { stopRefresh() }
        }
        .onDisappear { stopRefresh() }
    }

    // MARK: Data

    private func scheduleRefresh() {
        refreshTask?.cancel()
        guard production, scenePhase == .active else { return }
        refreshTask = Task {
            do { try await Task.sleep(for: .milliseconds(600)) }
            catch { return }
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func refresh() async {
        guard let service = services.railService else { return }
        await network.refresh { requestedBounds in
            try await service.networkTrains(bounds: requestedBounds)
        }
    }

    private func stopRefresh() {
        refreshTask?.cancel()
        network.invalidateRequest()
    }

}

// The production overlay is separately hostable for deterministic layout checks.
// At accessibility sizes its header reserves space above the scrollable stats;
// the enclosing RootView reserves the bottom navigation dock.
struct ExploreNetworkOverlay: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    let production: Bool
    let markers: [NetworkMarker]
    let loading: Bool
    let error: String?
    let expired: Bool
    let generatedAt: Date?

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: Spacing.units(4)) {
                    header
                        .padding(.horizontal, Spacing.units(4))
                        .safeAreaPadding(.top)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    statsCard
                        .padding(.horizontal, Spacing.units(4))
                        .padding(.bottom, 54)
                }
            } else {
                ZStack(alignment: .top) {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                    Text("\(markers.count)")
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    statsContent.padding(Spacing.units(3.5))
                }
                .scrollBounceBehavior(.basedOnSize)
                .accessibilityIdentifier("explore.networkStats")
            } else {
                statsContent.padding(Spacing.units(3.5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GlassSurface(shape: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous), heavy: true)
        }
    }

    private var statsContent: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2)) {
            if production, !markers.isEmpty {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.units(2)))
                    : AnyLayout(HStackLayout(spacing: Spacing.units(2)))) {
                    networkStat("IN VIEW", value: markers.count)
                    networkStat("OBSERVED", value: markers.filter { $0.observed }.count)
                    networkStat("PREDICTED", value: markers.filter { $0.kind == .predicted }.count)
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
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.units(2.5))
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(colors.raised))
    }

    private var statsBody: String {
        if !production {
            return "Connect the licensed gateway to render current trains. Preview mode never manufactures a nationwide live layer."
        }
        if let error = error {
            if expired { return "Previous positions expired and are hidden. \(error)" }
            if generatedAt == nil { return "Network positions unavailable. \(error)" }
            return "Showing the last unexpired snapshot. \(error)"
        }
        if expired { return "Positions expired and are hidden until a fresh network update arrives." }
        return "The visible map refreshes every minute while this screen is active. Positions are observed, map-matched, or explicitly estimated."
    }

    private var updatedLabel: String {
        guard production else { return "WAITING FOR NETWORK UPDATE" }
        if expired { return loading ? "POSITIONS EXPIRED · REFRESHING" : "POSITIONS EXPIRED" }
        if loading { return "REFRESHING NETWORK" }
        guard let updatedAt = generatedAt else { return "WAITING FOR NETWORK UPDATE" }
        let formatter = DateFormatter()
        formatter.timeZone = IndiaDate.timeZone
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "HH:mm"
        return "UPDATED \(formatter.string(from: updatedAt)) IST"
    }

}

// MARK: - Network map (Apple MapKit)

struct NetworkMapView: UIViewRepresentable {
    let markers: [NetworkMarker]
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
        context.coordinator.update(mapView: mapView, markers: markers)
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        private let onBoundsChange: (NetworkBounds) -> Void
        private var annotations: [NetworkAnnotation] = []
        private var lastMarkers: [NetworkMarker] = []
        private var lastBounds = ""

        init(onBoundsChange: @escaping (NetworkBounds) -> Void) {
            self.onBoundsChange = onBoundsChange
        }

        func update(mapView: MKMapView, markers: [NetworkMarker]) {
            guard markers != lastMarkers else { return }
            lastMarkers = markers
            mapView.removeAnnotations(annotations)
            annotations = markers.map { marker in
                NetworkAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude),
                    title: marker.title, subtitle: marker.subtitle, observed: marker.observed
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

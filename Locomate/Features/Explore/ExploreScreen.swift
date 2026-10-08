//
//  ExploreScreen.swift
//  Locomate
//
//  Native network map above the approved shared Explore data sheet.
//  Every position keeps its source, expiry and dated journey action.
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
    @State private var trainList: NetworkTrainListScope?

    let onSelect: (Routes.JourneyDestination) -> Void

    private var production: Bool { services.mode.isProduction }
    private var markers: [NetworkMarker] { network.markers }

    var body: some View {
        OverviewPage { viewport in
            NetworkMapView(
                markers: markers,
                viewportOnScreen: viewport,
                onSelect: openJourney,
                onInspectCluster: { trainList = .cluster($0) },
                onBoundsChange: { newBounds in
                    network.setBounds(newBounds)
                    scheduleRefresh()
                }
            )
        } sheet: {
            ExploreNetworkOverlay(production: production, markers: markers,
                                  loading: network.loading, error: network.error,
                                  expired: network.expired, generatedAt: network.snapshot?.generatedAt,
                                  onShowTrains: { trainList = .all })
        }
        .sheet(item: $trainList) { scope in
            NetworkTrainList(markers: scope.filter(markers), title: scope.title,
                             expired: network.expired, onSelect: openJourney)
                .environment(\.locomoteColors, colors)
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

    private func openJourney(_ markerID: NetworkMarker.ID) {
        guard let destination = network.destination(for: markerID) else { return }
        trainList = nil
        onSelect(destination)
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

// Separately hostable, with the same scrollable sheet at every text size.
struct ExploreNetworkOverlay: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    let production: Bool
    let markers: [NetworkMarker]
    let loading: Bool
    let error: String?
    let expired: Bool
    let generatedAt: Date?
    var onShowTrains: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore")
                        .pageHeading()
                        .foregroundStyle(colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("explore.heading")
                    Text(production ? "The network, live" : "The network, in preview")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)
                    if !production {
                        Text("PREVIEW · NOT LIVE").eyebrow(colors.pair(for: .preview).fg)
                    }
                }
                statsContent
            }
            .padding(22)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityIdentifier("explore.networkStats")
    }

    private var statsContent: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2)) {
            if production, dynamicTypeSize.isAccessibilitySize { viewTrainsButton }
            if production, !markers.isEmpty {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.units(2)))
                    : AnyLayout(HStackLayout(spacing: Spacing.units(2)))) {
                    networkStat("IN VIEW", value: markers.count)
                    networkStat("OBSERVED", value: markers.filter { $0.observed }.count)
                    networkStat("PREDICTED", value: markers.filter { $0.kind == .predicted }.count)
                }
            }
            if production, !dynamicTypeSize.isAccessibilitySize { viewTrainsButton }
            Text("POSITION SOURCES").eyebrow(colors.textTertiary)
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

    private var viewTrainsButton: some View {
        Button(action: onShowTrains) {
            Label("View trains", systemImage: "list.bullet")
                .font(LocomateFont.body)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .foregroundStyle(colors.accentBase)
        .accessibilityIdentifier("explore.viewTrains")
        .accessibilityHint("Opens a list of current train positions and dated journeys.")
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
    var viewportOnScreen: CGRect? = nil
    let onSelect: (NetworkMarker.ID) -> Void
    let onInspectCluster: ([NetworkMarker.ID]) -> Void
    let onBoundsChange: (NetworkBounds) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBoundsChange: onBoundsChange, onSelect: onSelect, onInspectCluster: onInspectCluster)
    }

    func makeUIView(context: Context) -> OverviewMapContainer {
        let surface = OverviewMapContainer(frame: .zero)
        let mapView = surface.mapView
        mapView.delegate = context.coordinator
        context.coordinator.surface = surface
        mapView.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
        mapView.overrideUserInterfaceStyle = .dark
        mapView.showsCompass = false
        mapView.isRotateEnabled = false
        mapView.isPitchEnabled = false
        surface.viewportOnScreen = viewportOnScreen
        surface.onViewportChange = { [weak coordinator = context.coordinator] surface in
            coordinator?.publishBounds(surface)
        }
        return surface
    }

    func updateUIView(_ surface: OverviewMapContainer, context: Context) {
        surface.viewportOnScreen = viewportOnScreen
        context.coordinator.onSelect = onSelect
        context.coordinator.onInspectCluster = onInspectCluster
        context.coordinator.update(mapView: surface.mapView, markers: markers)
    }

    @MainActor final class Coordinator: NSObject, MKMapViewDelegate {
        private let onBoundsChange: (NetworkBounds) -> Void
        var onSelect: (NetworkMarker.ID) -> Void
        var onInspectCluster: ([NetworkMarker.ID]) -> Void
        weak var surface: OverviewMapContainer?
        private var annotations: [NetworkAnnotation] = []
        private var lastMarkers: [NetworkMarker] = []
        private var lastBounds = ""
        private var boundsRevision = 0

        init(onBoundsChange: @escaping (NetworkBounds) -> Void,
             onSelect: @escaping (NetworkMarker.ID) -> Void,
             onInspectCluster: @escaping ([NetworkMarker.ID]) -> Void) {
            self.onBoundsChange = onBoundsChange
            self.onSelect = onSelect
            self.onInspectCluster = onInspectCluster
        }

        func update(mapView: MKMapView, markers: [NetworkMarker]) {
            guard markers != lastMarkers else { return }
            lastMarkers = markers
            mapView.removeAnnotations(annotations)
            annotations = markers.map { marker in
                NetworkAnnotation(marker: marker)
            }
            mapView.addAnnotations(annotations)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if let surface, surface.mapView === mapView { publishBounds(surface) }
        }

        func publishBounds(_ surface: OverviewMapContainer) {
            boundsRevision += 1
            let revision = boundsRevision
            // Publish after the SwiftUI/native layout transaction, and read the
            // current viewport so obsolete resize/pan callbacks cannot win.
            DispatchQueue.main.async { [weak self, weak surface] in
                guard let self, revision == self.boundsRevision,
                      let surface, surface.window != nil,
                      let bounds = surface.visibleNetworkBounds else { return }
                let key = String(format: "%.5f,%.5f,%.5f,%.5f", bounds.west, bounds.south, bounds.east, bounds.north)
                guard key != self.lastBounds else { return }
                self.lastBounds = key
                self.onBoundsChange(bounds)
            }
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
                // The count glyph says it all on the map; the words live in the callout.
                view.titleVisibility = .hidden
                view.subtitleVisibility = .hidden
                cluster.title = "\(cluster.memberAnnotations.count) trains"
                cluster.subtitle = "Choose a train from the list"
                view.accessibilityLabel = cluster.title
                view.accessibilityHint = "Show the callout, then view the trains in this cluster."
                view.rightCalloutAccessoryView = actionButton(symbol: "list.bullet", label: "View \(cluster.memberAnnotations.count) trains")
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
            view.accessibilityHint = "Show the callout, then open this dated journey."
            view.rightCalloutAccessoryView = actionButton(
                symbol: "arrow.right", label: "Open journey for \(train.marker.title), origin date \(train.marker.destination.date)"
            )
            view.canShowCallout = true
            view.clusteringIdentifier = "locomate-trains"
            view.displayPriority = .defaultLow
            view.collisionMode = .circle
            return view
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            if let train = view.annotation as? NetworkAnnotation {
                onSelect(train.marker.id)
            } else if let cluster = view.annotation as? MKClusterAnnotation {
                let ids = cluster.memberAnnotations.compactMap { ($0 as? NetworkAnnotation)?.marker.id }
                if !ids.isEmpty { onInspectCluster(ids) }
            }
        }

        private func actionButton(symbol: String, label: String) -> UIButton {
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: symbol), for: .normal)
            button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
            button.accessibilityLabel = label
            return button
        }
    }
}

final class NetworkAnnotation: NSObject, MKAnnotation {
    let marker: NetworkMarker
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: marker.latitude, longitude: marker.longitude)
    }
    var title: String? { marker.title }
    var subtitle: String? { marker.subtitle }
    var observed: Bool { marker.observed }

    init(marker: NetworkMarker) { self.marker = marker }
}

/// Store membership, not a captured snapshot: a presented list must lose expired
/// entries and pick up current source/time values while it remains on screen.
enum NetworkTrainListScope: Identifiable {
    case all
    case cluster([NetworkMarker.ID])
    var id: String { "network-trains" }
    var title: String {
        if case .cluster = self { return "Trains in cluster" }
        return "Trains on map"
    }
    func filter(_ markers: [NetworkMarker]) -> [NetworkMarker] {
        guard case let .cluster(ids) = self else { return markers }
        let membership = Set(ids)
        return markers.filter { membership.contains($0.id) }
    }
}

struct NetworkTrainList: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locomoteColors) private var colors
    let markers: [NetworkMarker]
    let title: String
    let expired: Bool
    let onSelect: (NetworkMarker.ID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.units(3)) {
                    Text("Origin dates use India Standard Time. Position type, source and update time are shown for each train.")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)
                    if markers.isEmpty {
                        Text(expired ? "Positions expired. This list will update when fresh positions arrive." : "No current train positions in this list. Move the map or wait for a network update.")
                            .font(LocomateFont.body)
                            .foregroundStyle(colors.textPrimary)
                    }
                    ForEach(markers) { marker in
                        VStack(alignment: .leading, spacing: Spacing.units(2)) {
                            Text(marker.title)
                                .font(LocomateFont.headline)
                                .foregroundStyle(colors.textPrimary)
                            Text(marker.subtitle)
                                .font(LocomateFont.caption)
                                .foregroundStyle(colors.textSecondary)
                            Button { onSelect(marker.id) } label: {
                                Label("Open journey", systemImage: "arrow.right")
                                    .font(LocomateFont.body)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .foregroundStyle(colors.accentBase)
                            .accessibilityLabel("Open journey for \(marker.title), origin date \(marker.destination.date)")
                            .accessibilityIdentifier("explore.openJourney.\(marker.id)")
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(Spacing.units(3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(colors.raised, in: RoundedRectangle(cornerRadius: Radius.lg))
                    }
                }
                .padding(Spacing.units(4))
            }
            .accessibilityIdentifier("explore.trainList")
            .background(colors.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

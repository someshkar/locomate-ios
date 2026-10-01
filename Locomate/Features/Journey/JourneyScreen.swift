//
//  JourneyScreen.swift
//  Locomate
//
//  The flagship surface: a persistent full-bleed map with a resizable personal
//  journey sheet. Ported composition from SmartRail
//  `src/screens/Journey/JourneyView.tsx`.
//

import SwiftUI
import MapKit

struct JourneyScreen: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(Preferences.self) private var preferences
    @Environment(\.locomoteServices) private var services

    var request: RootView.JourneyRequest? = nil
    var onOpenSearch: () -> Void = {}

    @State private var model: JourneyModel?
    @State private var sheetPosition = SheetPosition()
    @State private var detentIndex = 1
    @State private var panel: JourneyPanel = .trip
    @State private var setupVisible = false
    @State private var daylight: MapDaylight = MapDaylight(solarElevation: 90, nightAmount: 0, label: .day)
    @State private var message: String?
    @State private var calendarPending = false
    @State private var alertsEnabled = false
    @State private var alertsPending = false
    @State private var journeySaved = false
    @State private var showDataSource = false

    var body: some View {
        GeometryReader { geometry in
            let detents = detents(for: geometry.size.height)
            ZStack(alignment: .top) {
                colors.canvas.ignoresSafeArea()
                map
                mapChrome
                if let model {
                    ResizableSheet(
                        detents: detents,
                        detentIndex: $detentIndex,
                        position: sheetPosition,
                        handle: {
                            if case .loaded(let journey) = model.phase {
                                trainHeader(journey)
                            }
                        },
                        content: {
                            sheetContent(model: model, height: geometry.size.height)
                        }
                    )
                } else if services.mode.isProduction {
                    ResizableSheet(
                        detents: detents,
                        detentIndex: $detentIndex,
                        position: sheetPosition,
                        handle: { emptyHeader },
                        content: { emptyJourneyContent }
                    )
                }
            }
        }
        .sheet(isPresented: $showDataSource) {
            DataSourceSheet(model: model)
        }
        .task { await ensureModel() }
        .onChange(of: request) { _, newValue in
            guard let newValue else { return }
            Task {
                if let model {
                    await model.update(trainNumber: newValue.trainNumber, originDate: newValue.originDate)
                } else {
                    await ensureModel()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .locomoteForeground)) { _ in
            recomputeDaylight()
        }
    }

    // MARK: Model lifecycle

    private func ensureModel() async {
        if model == nil {
            if services.mode.isProduction && request == nil { return }
            let created = JourneyModel(
                trainNumber: request?.trainNumber ?? "12137",
                originDate: request?.originDate ?? IndiaDate.today(),
                service: services.railService,
                cache: services.cache,
                passport: services.passport
            )
            model = created
            await created.load()
            recomputeDaylight()
        }
    }

    private func recomputeDaylight() {
        guard let journey = model?.journey else { return }
        let coordinate: RailCoordinate = {
            if let route = journey.routeCoordinates,
               let point = try? RouteGeometry.coordinate(along: route, progress: journey.position.progress) {
                return point
            }
            return journey.routeCoordinates?.first ?? RailCoordinate(latitude: 22.6, longitude: 79.5)
        }()
        daylight = MapDaylightEngine.compute(at: coordinate, now: Date())
    }

    // MARK: Map

    @ViewBuilder private var map: some View {
        if let journey = model?.journey, let route = journey.routeCoordinates, route.count >= 2 {
            RailMapView(
                route: route,
                progress: journey.position.progress,
                preview: model?.isPreview == true,
                markers: markers(for: journey),
                daylight: daylight,
                lightingMode: preferences.mapLighting,
                sheetVisibleHeight: sheetPosition.visibleHeight
            )
            .id(preferences.mapLighting)
            .overlay {
                Color.black.opacity(preferences.mapLighting == .day ? 0.03 : 0.34)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
        } else {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 22.6, longitude: 79.5),
                span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 20)
            )))
            .mapStyle(.hybrid(elevation: .flat))
            .overlay {
                Color.black.opacity(0.45).allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                if let model, case .loading = model.phase {
                    ProgressView("Loading current train run…")
                        .tint(colors.accentBase)
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textPrimary)
                        .padding(.top, 150)
                }
            }
            .ignoresSafeArea()
        }
    }

    private func markers(for journey: Journey) -> [MapStationMarker] {
        guard let route = journey.routeCoordinates, route.count >= 2 else { return [] }
        return journey.stops.enumerated().compactMap { index, stop in
            guard let coordinate = try? RouteGeometry.coordinate(along: route, progress: stop.progress) else { return nil }
            return MapStationMarker(id: stop.code, coordinate: coordinate, state: stop.state)
        }
    }

    // MARK: Map chrome

    private var mapChrome: some View {
        HStack {
            iconButton("magnifyingglass", label: "Search trains", action: onOpenSearch)
            Spacer()
            if let model {
                StatusPill(
                    label: StatusMapping.journeyModeLabel(model.statusKind),
                    kind: model.statusKind,
                    onGlass: true,
                    pulsing: model.modeInput.map { StatusMapping.isLivePulseAllowed($0) } ?? false
                )
            } else {
                StatusPill(label: "FIND A TRAIN", kind: .scheduled, onGlass: true, pulsing: false)
            }
            Spacer()
            iconButton("ellipsis", label: "Data source details", action: { showDataSource = true })
        }
        .padding(.horizontal, Spacing.units(4))
        .safeAreaPadding(.top)
    }

    private func iconButton(_ system: String, label: String) -> some View {
        iconButton(system, label: label, action: {})
    }

    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        ScaleButton(accessibilityLabel: label, action: action) {
            ZStack {
                GlassSurface(cornerRadius: 22)
                Image(systemName: system)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(colors.textPrimary)
            }
            .frame(width: 44, height: 44)
        }
    }

    // MARK: Sheet content

    private var emptyHeader: some View {
        HStack {
            Text("My Journeys")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-1)
                .foregroundStyle(colors.textPrimary)
            Spacer()
        }
        .padding(.horizontal, Spacing.units(4))
        .padding(.top, 10)
        .padding(.bottom, Spacing.units(3))
    }

    private var emptyJourneyContent: some View {
        VStack(alignment: .leading, spacing: Spacing.units(3)) {
            Text("Every journey starts here.")
                .font(LocomateFont.display)
                .foregroundStyle(colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Find a train and choose its India origin date to see the route, station times and source of every update.")
                .font(LocomateFont.body)
                .foregroundStyle(colors.textSecondary)
            Button(action: onOpenSearch) {
                Label("Find your train", systemImage: "magnifyingglass")
                    .font(LocomateFont.bodyStrong)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.units(3))
            }
            .buttonStyle(.borderedProminent)
            .tint(colors.accentBase)
        }
        .padding(Spacing.units(4))
    }

    @ViewBuilder private func sheetContent(model: JourneyModel, height: CGFloat) -> some View {
        switch model.phase {
        case .idle, .loading:
            ProgressView().tint(colors.accentBase).padding(Spacing.units(6))
        case .failed(let error):
            EmptyState(
                icon: "magnifyingglass",
                title: "Train run unavailable",
                body: "\(model.originDate) · \(error)",
                actionTitle: "Try again",
                onAction: { Task { await model.load() } }
            )
        case .loaded(let journey):
            loadedContent(model: model, journey: journey, height: height)
        }
    }

    @ViewBuilder private func loadedContent(model: JourneyModel, journey: Journey, height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.units(4)) {
                PersonalizedTripCard(
                    journey: journey,
                    plan: model.plan ?? JourneyPlanLogic.default(journey: journey, originDate: model.originDate),
                    mode: model.statusKind,
                    preview: model.isPreview,
                    onEdit: { setupVisible = true }
                )
                if detentIndex == 0 {
                    JourneySections(selected: panel, onChange: { section in panel = section })
                    DataBanner(model: DataReport.banner(DataReportInput(
                        preview: model.isPreview,
                        historicalRoute: model.isPreview,
                        cached: model.isCached,
                        cachedAt: model.cachedAt,
                        error: nil,
                        observedAt: journey.provenance?.observedAt
                    )))
                    switch panel {
                    case .trip: tripPanel(model: model, journey: journey)
                    case .stops: JourneyTimeline(journey: journey, plan: model.plan)
                    case .insights: insightsPanel(model: model, journey: journey)
                    }
                }
                if let message {
                    Text(message)
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textTertiary)
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .padding(.horizontal, Spacing.units(4))
            .padding(.bottom, 190)
        }
        .scrollBounceBehavior(.basedOnSize)
        .sheet(isPresented: $setupVisible) {
            JourneySetupSheet(
                journey: journey,
                originDate: model.originDate,
                initial: model.plan
            ) { plan in
                Task { await model.savePlan(plan) }
                message = "Your boarding and drop-off stops were saved privately on this device."
                Haptics.success()
            }
        }
    }

    private func trainHeader(_ journey: Journey) -> some View {
        HStack(spacing: Spacing.units(3)) {
            Text("My Journeys")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .tracking(-1)
                .foregroundStyle(colors.textPrimary)
            Spacer(minLength: 0)
            iconButton(detentIndex == 0 ? "chevron.up" : "chevron.down",
                       label: detentIndex == 0 ? "Show more map" : "Expand journey details",
                       action: {
                           withAnimation(Motion.animation(Motion.sheet, reduceMotion: reduceMotion)) {
                               detentIndex = detentIndex == 0 ? 2 : 0
                           }
                       })
            iconButton("arrow.up.right", label: "Edit your journey", action: { setupVisible = true })
        }
        .padding(.horizontal, Spacing.units(4))
        .padding(.top, 10)
        .padding(.bottom, Spacing.units(3))
    }

    // MARK: Actions

    private func addToCalendar(model: JourneyModel, journey: Journey) {
        calendarPending = true
        let result = JourneyCalendarService.add(journey: journey, originDate: model.originDate, plan: model.plan)
        calendarPending = false
        switch result {
        case .saved:
            message = "Calendar event opened."
            Haptics.confirm()
        case .cancelled:
            message = "Calendar event was not added."
        case .unavailable:
            message = "Calendar is unavailable on this device."
        }
    }

    private func toggleAlerts(model: JourneyModel, journey: Journey) {
        guard !model.isPreview else {
            message = "Alerts require a production journey and are never generated from preview data."
            Haptics.warn()
            return
        }
        alertsPending = true
        alertsEnabled.toggle()
        alertsEnabled ? Haptics.success() : Haptics.warn()
        message = alertsEnabled
            ? "Alerts are on for \(journey.trainNumber)."
            : "Alerts are off for \(journey.trainNumber)."
        alertsPending = false
    }

    private func share(model: JourneyModel, journey: Journey) {
        let plan = model.plan ?? JourneyPlanLogic.default(journey: journey, originDate: model.originDate)
        let link = (try? Routes.journeyURL(trainNumber: journey.trainNumber, date: model.originDate))?.absoluteString ?? ""
        let text = "\(journey.trainNumber) \(journey.trainName): \(plan.boarding.code) → \(plan.alighting.code). \(link)"
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var controller = root
        while let presented = controller.presentedViewController { controller = presented }
        if let popover = activity.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        }
        controller.present(activity, animated: true)
    }

    private func formattedDate(_ originDate: String?) -> String {
        guard let originDate else { return "" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = IndiaDate.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: originDate) else { return originDate }
        let display = DateFormatter()
        display.timeZone = IndiaDate.timeZone
        display.locale = Locale(identifier: "en_IN")
        display.dateFormat = "d MMM"
        return display.string(from: date)
    }

    @ViewBuilder private func tripPanel(model: JourneyModel, journey: Journey) -> some View {
        NextStopStat(journey: journey, originDate: model.originDate)
        JourneyActions(
            alertsEnabled: alertsEnabled,
            alertsPending: alertsPending,
            calendarPending: calendarPending,
            journeySaved: journeySaved,
            onCalendar: { addToCalendar(model: model, journey: journey) },
            onSave: { Task { message = await model.saveToPassport(); journeySaved = true; Haptics.success() } },
            onShare: { share(model: model, journey: journey) },
            onToggleAlerts: { toggleAlerts(model: model, journey: journey) }
        )
    }

    @ViewBuilder private func insightsPanel(model: JourneyModel, journey: Journey) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(2)) {
                Text("Reliability history").eyebrow(colors.textTertiary)
                Text(model.isPreview
                     ? "Reliability history requires a production journey. Preview data is never used to estimate real performance."
                     : "Destination-arrival reliability appears here when the gateway has materialised history for this service.")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
            }
        }
        RotationIntelligenceCard(
            operations: model.operations,
            trainNumber: journey.trainNumber,
            enabled: !model.isPreview
        )
    }

    private func detents(for height: CGFloat) -> [CGFloat] {
        [72, min(height * 0.48, height - 200), max(320, height - 280)]
    }
}

enum JourneyPanel: String, CaseIterable, Identifiable {
    case trip, stops, insights
    var id: String { rawValue }
    var label: String {
        switch self {
        case .trip: return "Trip"
        case .stops: return "Stops"
        case .insights: return "Insights"
        }
    }
}

extension Notification.Name {
    static let locomoteForeground = Notification.Name("locomote.foreground")
}

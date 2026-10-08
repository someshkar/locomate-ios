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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(Preferences.self) private var preferences
    @Environment(\.locomoteServices) private var services

    var request: RootView.JourneyRequest? = nil
    var onOpenSearch: () -> Void = {}

    @State private var model: JourneyModel?
    @State private var modelRequest: RootView.JourneyRequest?
    @State private var sheetPosition = SheetPosition()
    @State private var detentIndex = 1
    @State private var panel: JourneyPanel = .trip
    @State private var setupVisible = false
    @State private var daylight: MapDaylight = MapDaylight(solarElevation: 90, nightAmount: 0, label: .day)
    @State private var message: String?
    @State private var calendarPending = false
    @State private var liveCardEnabled = false
    @State private var liveCardPending = false
    @State private var showPhysicalSightings = false
    @State private var showJourneyAlerts = false
    @State private var journeySaved = false
    @State private var showDataSource = false
    @State private var mapCommand: RailMapCommand?

    var body: some View {
        GeometryReader { geometry in
            let detents = detents(for: geometry.size.height)
            ZStack(alignment: .top) {
                colors.canvas.ignoresSafeArea(edges: .top)
                map(sheetTopOnScreen: geometry.frame(in: .global).minY + sheetPosition.topEdge,
                    attributionTopOnScreen: geometry.frame(in: .global).minY + detents[1])
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
        .task(id: RefreshContext(request: request, phase: scenePhase)) {
            guard scenePhase == .active else { return }
            await keepJourneyCurrent()
        }
        .task(id: ClockContext(phase: scenePhase, deadline: model?.nextEvidenceDeadline)) {
            guard scenePhase == .active, let model else { return }
            model.refreshClock()
            guard let deadline = model.nextEvidenceDeadline else { return }
            do { try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow))) }
            catch { return }
            guard !Task.isCancelled else { return }
            model.refreshClock()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { model?.cancelLoad() }
        }
        .onDisappear { model?.cancelLoad() }
        .onChange(of: preferences.contributionsEnabled) { _, _ in
            Task { await reconcileContribution() }
        }
        .onChange(of: preferences.backgroundLocationEnabled) { _, _ in
            Task { await reconcileContribution() }
        }
    }

    // MARK: Model lifecycle

    private struct RefreshContext: Equatable {
        let request: RootView.JourneyRequest?
        let phase: ScenePhase
    }
    private struct ClockContext: Equatable {
        let phase: ScenePhase
        let deadline: Date?
    }

    private func keepJourneyCurrent() async {
        if services.mode.isProduction && request == nil { return }
        var loadedSelection = false
        if model == nil {
            model = JourneyModel(
                trainNumber: request?.trainNumber ?? "12137",
                originDate: request?.originDate ?? IndiaDate.today(),
                service: services.railService,
                cache: services.cache,
                passport: services.passport,
                liveActivity: services.liveActivity,
                savedJourney: request?.savedJourney
            )
            modelRequest = request
        } else if modelRequest != request, let request, let model {
            services.contribution.stop()
            modelRequest = request
            await model.update(trainNumber: request.trainNumber, originDate: request.originDate,
                               savedJourney: request.savedJourney)
            loadedSelection = true
        }
        guard !Task.isCancelled, let model else { return }
        model.refreshClock()
        if loadedSelection { await didRefreshJourney() }
        if services.mode.isProduction {
            await model.runActiveRefresh(refreshImmediately: !loadedSelection, didRefresh: didRefreshJourney)
        } else {
            if !loadedSelection { await model.load() }
            guard !Task.isCancelled else { return }
            await didRefreshJourney()
        }
    }

    private func didRefreshJourney() async {
        guard !Task.isCancelled, let model else { return }
        liveCardEnabled = model.journey.map { model.isLiveActivityRunning(for: $0.id) } ?? false
        recomputeDaylight()
        await reconcileContribution()
    }

    private func reconcileContribution() async {
        guard request?.allowsContribution(currentActivationRevision: services.contributionActivationRevision) != false,
              preferences.contributionsEnabled, services.railService != nil,
              let model, !model.isPreview, !model.isCached,
              let journey = model.journey, journey.completion < 1,
              ContributionObservation.isWithinRunWindow(originDate: model.originDate,
                  departureTime: journey.departureTime,
                  durationMinutes: journey.scheduledDurationMinutes),
              let route = journey.routeCoordinates, route.count >= 2 else {
            services.contribution.stop()
            return
        }
        await services.contribution.start(runId: journey.id, route: route,
            background: preferences.backgroundLocationEnabled, service: services.railService,
            stopAt: ContributionObservation.runWindowEnd(originDate: model.originDate,
                departureTime: journey.departureTime, durationMinutes: journey.scheduledDurationMinutes))
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

    @ViewBuilder private func map(sheetTopOnScreen: Double, attributionTopOnScreen: Double) -> some View {
        if let journey = model?.journey, let route = journey.routeCoordinates, route.count >= 2 {
            RailMapView(
                journeyID: mapJourneyID,
                route: route,
                progress: journey.position.progress,
                positionDisplay: model?.positionDisplay ?? .hidden,
                markers: markers(for: journey),
                daylight: daylight,
                lightingMode: preferences.mapLighting,
                sheetVisibleHeight: sheetPosition.visibleHeight,
                cameraCommand: mapCommand,
                sheetTopOnScreen: sheetTopOnScreen,
                attributionTopOnScreen: attributionTopOnScreen,
                operationalRuns: [model?.operations?.previous, model?.operations?.current, model?.operations?.next].compactMap { $0 }
            )
            .overlay {
                Color.black.opacity(0.03 + 0.31 * MapLightingPresentation.nightAmount(mode: preferences.mapLighting, daylight: daylight))
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .top)
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
            .ignoresSafeArea(edges: .top)
        }
    }

    private func markers(for journey: Journey) -> [MapStationMarker] {
        guard let route = journey.routeCoordinates, route.count >= 2 else { return [] }
        return journey.stops.enumerated().compactMap { index, stop in
            guard let coordinate = try? RouteGeometry.coordinate(along: route, progress: stop.progress) else { return nil }
            return MapStationMarker(id: stop.code, coordinate: coordinate, name: stop.name, state: stop.state)
        }
    }

    // MARK: Map chrome

    private var mapChrome: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                iconButton("scope", label: "Fit journey route", action: {
                    mapCommand = RailMapCommand(journeyID: mapJourneyID, target: .route)
                }).disabled(model?.journey?.routeCoordinates?.count ?? 0 < 2)
                iconButton("mappin", label: positionFocusLabel, action: {
                    mapCommand = RailMapCommand(journeyID: mapJourneyID, target: .position)
                }).disabled(model?.positionDisplay == nil || model?.positionDisplay == .hidden
                    || (model?.journey?.routeCoordinates?.count ?? 0) < 2)
            }
        }
        .padding(.horizontal, Spacing.units(4))
        .padding(.top, 56)
        .safeAreaPadding(.top)
    }

    private var mapJourneyID: String {
        "\(model?.journey?.trainNumber ?? "")|\(model?.originDate ?? "")|\(model?.isPreview ?? false)"
    }

    private var positionFocusLabel: String {
        switch model?.positionDisplay ?? .hidden {
        case .preview: "Show historical sample position"
        case .observed: "Show observed train position"
        case .stale: "Show last known train position"
        case .hidden: "Train position unavailable"
        }
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
                .pageHeading()
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
                onAction: { Task { await model.load(); await reconcileContribution() } }
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
                    cached: model.isCached,
                    expanded: detentIndex == 0,
                    onEdit: { setupVisible = true }
                )
                if let status = model.liveActivityRegistrationMessage {
                    Text(status).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("liveActivity.registrationStatus")
                }
                if let notice = model.planNotice {
                    Text(notice)
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.pair(for: .stale).fg)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if detentIndex == 0 {
                    JourneySections(selected: panel, onChange: { section in panel = section })
                    DataBanner(model: DataReport.banner(DataReportInput(
                        preview: model.isPreview,
                        historicalRoute: model.isPreview,
                        cached: model.isCached,
                        cachedAt: model.cachedAt,
                        error: model.refreshError,
                        observedAt: journey.provenance?.observedAt
                    )))
                    ScaleButton(accessibilityLabel: "Data source details", action: { showDataSource = true }) {
                        Label("About this data", systemImage: "info.circle")
                            .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    }
                    switch panel {
                    case .trip: tripPanel(model: model, journey: journey)
                    case .stops: JourneyTimeline(journey: journey, plan: model.plan, cached: model.isCached, preview: model.isPreview)
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
            .padding(.horizontal, Spacing.units(5.5))
            .padding(.bottom, 190)
            .contentShape(Rectangle())
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
        .sheet(isPresented: $showJourneyAlerts) {
            JourneyAlertsSheet(journey: journey, originDate: model.originDate,
                               available: !model.isPreview && !model.isCached)
                .id(journey.id)
        }
    }

    private func trainHeader(_ journey: Journey) -> some View {
        (dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: Spacing.units(3)))) {
            Text("My Journeys")
                .pageHeading()
                .foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            HStack(spacing: Spacing.units(3)) {
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

    private func toggleLiveCard(model: JourneyModel, journey: Journey) {
        guard !model.isPreview, !model.isCached else {
            message = "A current production journey is required for a Lock Screen card."
            Haptics.warn()
            return
        }
        guard !liveCardPending else { return }
        liveCardPending = true
        Task { @MainActor in
            defer { liveCardPending = false }
            if liveCardEnabled {
                await model.endLiveActivity()
                guard model.journey?.id == journey.id else { return }
                liveCardEnabled = false
                message = "Lock Screen card is off for \(journey.trainNumber)."
                Haptics.warn()
            } else {
                let started = await model.startLiveActivity()
                guard model.journey?.id == journey.id else { return }
                liveCardEnabled = started
                message = started
                    ? "Lock Screen card shows \(journey.trainNumber)'s next-stop timing. Remote updates connect automatically."
                    : "A current delay and Live Activities access in iOS Settings are required."
                if started { Haptics.success() } else { Haptics.warn() }
            }
        }
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
        NextStopStat(journey: journey, originDate: model.originDate, plan: model.plan,
                     cached: model.isCached, preview: model.isPreview)
        JourneyActions(
            liveCardEnabled: liveCardEnabled,
            liveCardPending: liveCardPending,
            calendarPending: calendarPending,
            journeySaved: journeySaved,
            onCalendar: { addToCalendar(model: model, journey: journey) },
            onSave: { Task { message = await model.saveToPassport(); journeySaved = true; Haptics.success() } },
            onShare: { share(model: model, journey: journey) },
            onToggleLiveCard: { toggleLiveCard(model: model, journey: journey) }
        )
        JourneyAlertsSummary(journey: journey, available: !model.isPreview && !model.isCached) {
            showJourneyAlerts = true
        }
    }

    @ViewBuilder private func insightsPanel(model: JourneyModel, journey: Journey) -> some View {
        ReliabilityHistoryCard(trainNumber: journey.trainNumber, originDate: model.originDate,
                               preview: model.isPreview)
        PhysicalChainCard(chain: model.physicalChain, enabled: !model.isPreview && !model.isCached) {
            showPhysicalSightings = true
        }.sheet(isPresented: $showPhysicalSightings) { PhysicalSightingSheet(model: model) }
        RotationIntelligenceCard(
            operations: model.operations,
            trainNumber: journey.trainNumber,
            enabled: !model.isPreview,
            onFocus: { run in
                guard run.geometry.coordinates.count >= 2 else { return }
                mapCommand = RailMapCommand(journeyID: mapJourneyID, target: .operational(run.geometry.coordinates))
            }
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

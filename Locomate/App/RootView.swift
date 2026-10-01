//
//  RootView.swift
//  Locomate
//
//  App shell: resolves the theme, hosts the four primary surfaces behind the
//  floating bottom dock, and routes cross-tab navigation (search → journey,
//  network train → journey).
//

import SwiftUI

public struct RootView: View {
    @Environment(\.locomoteServices) private var services
    @State private var pushBridge = JourneyAlertPushBridge.shared
    @Environment(Preferences.self) private var preferences
    @State private var tab: LocomateTab = .journey
    @State private var pendingJourney: JourneyRequest?
    @State private var searchPresented = false
    @State private var restorationAttempted = false

    public init() {}

    public struct JourneyRequest: Equatable, Sendable {
        public let trainNumber: String
        public let originDate: String
        public let restored: Bool
        public let contributionActivationRevision: Int
        public let savedJourney: SavedJourney?
        public init(trainNumber: String, originDate: String, restored: Bool = false,
                    contributionActivationRevision: Int = 0, savedJourney: SavedJourney? = nil) {
            self.trainNumber = trainNumber
            self.originDate = originDate
            self.restored = restored
            self.contributionActivationRevision = contributionActivationRevision
            self.savedJourney = savedJourney
        }

        func allowsContribution(currentActivationRevision: Int) -> Bool {
            !restored || currentActivationRevision > contributionActivationRevision
        }
    }

    private var colors: LocomateColors {
        LocomoteThemeResolver.colors(dark: preferences.dark)
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            colors.canvas.ignoresSafeArea()

            Group {
                switch tab {
                case .journey:
                    JourneyScreen(request: pendingJourney, onOpenSearch: { switchTab(.search) })
                case .explore:
                    ExploreScreen(onSelect: { destination in
                        selectJourney(destination)
                    })
                case .passport:
                    PassportScreen(onOpenSearch: { switchTab(.search) }, onOpenJourney: { saved in
                        guard let destination = PassportReopening.destination(for: saved, production: services.mode.isProduction) else { return }
                        selectJourney(destination, savedJourney: saved)
                    })
                case .search:
                    SearchScreen(onSelect: { train, date in
                        selectJourney(.init(trainNumber: train.number, date: date))
                    })
                }
            }
            .environment(\.locomoteColors, colors)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomDock(active: tab, onChange: switchTab)
                .frame(maxWidth: 330)
                .environment(\.locomoteColors, colors)
                .padding(.horizontal, Spacing.units(5))
                .padding(.vertical, Spacing.units(2))
                .frame(maxWidth: .infinity)
                .background(colors.canvas)
        }
        .environment(\.locomoteColors, colors)
        .animation(Motion.fadeNormal, value: preferences.dark)
        .sheet(isPresented: $searchPresented) {
            SearchScreen(onSelect: { train, date in
                selectJourney(.init(trainNumber: train.number, date: date))
            })
            .environment(\.locomoteColors, colors)
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.ultraThinMaterial)
        }
        .task { restoreJourneyIfNeeded() }
        .onChange(of: pushBridge.pendingPayload) { _, _ in consumeNotificationRoute() }
        .onOpenURL { url in
            // Deep links: locomate://journeys/{trainNumber}?date=yyyy-MM-dd
            guard let destination = Routes.parse(url) else { return }
            selectJourney(destination)
        }
    }

    private func consumeNotificationRoute() {
        guard let payload = pushBridge.pendingPayload else { return }
        pushBridge.pendingPayload = nil
        guard services.journeyAlerts.accepts(payload, presenting: false),
              let destination = Routes.parse(payload.url) else { return }
        selectJourney(destination)
    }

    private func selectJourney(_ destination: Routes.JourneyDestination, savedJourney: SavedJourney? = nil) {
        guard !PrivacyDeletionLatch.isPending,
              Routes.isValidTrainNumber(destination.trainNumber), Routes.isValidCalendarDate(destination.date) else { return }
        pendingJourney = JourneyRequest(trainNumber: destination.trainNumber, originDate: destination.date, savedJourney: savedJourney)
        try? services.selectedJourney.save(destination)
        switchTab(.journey)
    }

    private func restoreJourneyIfNeeded() {
        guard !restorationAttempted else { return }
        restorationAttempted = true
        guard pendingJourney == nil else { return }
        consumeNotificationRoute()
        // A URL/search/notification delivered before this task wins. This tiny
        // read is synchronous, so no late restore can overwrite a newer route.
        guard pendingJourney == nil, let saved = services.selectedJourney.load() else { return }
        pendingJourney = JourneyRequest(trainNumber: saved.trainNumber, originDate: saved.date, restored: true,
                                        contributionActivationRevision: services.contributionActivationRevision)
    }

    private func switchTab(_ newTab: LocomateTab) {
        if newTab == .search {
            searchPresented = true
            return
        }
        searchPresented = false
        withAnimation(Motion.fadeNormal) { tab = newTab }
    }
}

/// Resolves semantic colors from the persisted dark preference (which is
/// independent of the system appearance and of the map's day/night treatment).
enum LocomoteThemeResolver {
    static func colors(dark: Bool) -> LocomateColors {
        LocomateTheme.colors(dark: dark)
    }
}

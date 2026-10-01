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

    public init() {}

    public struct JourneyRequest: Equatable, Sendable {
        public let trainNumber: String
        public let originDate: String
        public init(trainNumber: String, originDate: String) {
            self.trainNumber = trainNumber
            self.originDate = originDate
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
                        pendingJourney = JourneyRequest(trainNumber: destination.trainNumber, originDate: destination.date)
                        switchTab(.journey)
                    })
                case .passport:
                    PassportScreen(onOpenSearch: { switchTab(.search) })
                case .search:
                    SearchScreen(onSelect: { train, date in
                        pendingJourney = JourneyRequest(trainNumber: train.number, originDate: date)
                        switchTab(.journey)
                    })
                }
            }
            .environment(\.locomoteColors, colors)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomDock(active: tab, onChange: switchTab)
                .environment(\.locomoteColors, colors)
                .padding(.horizontal, Spacing.units(3))
                .padding(.vertical, Spacing.units(2))
                .background(colors.canvas)
        }
        .environment(\.locomoteColors, colors)
        .animation(Motion.fadeNormal, value: preferences.dark)
        .sheet(isPresented: $searchPresented) {
            SearchScreen(onSelect: { train, date in
                pendingJourney = JourneyRequest(trainNumber: train.number, originDate: date)
                switchTab(.journey)
            })
            .environment(\.locomoteColors, colors)
            .presentationDetents([.fraction(0.72), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(.ultraThinMaterial)
        }
        .task { consumeNotificationRoute() }
        .onChange(of: pushBridge.pendingPayload) { _, _ in consumeNotificationRoute() }
        .onOpenURL { url in
            // Deep links: locomate://journeys/{trainNumber}?date=yyyy-MM-dd
            guard let destination = Routes.parse(url) else { return }
            pendingJourney = JourneyRequest(
                trainNumber: destination.trainNumber,
                originDate: destination.date
            )
            switchTab(.journey)
        }
    }

    private func consumeNotificationRoute() {
        guard let payload = pushBridge.pendingPayload else { return }
        pushBridge.pendingPayload = nil
        guard services.journeyAlerts.accepts(payload, presenting: false),
              let destination = Routes.parse(payload.url) else { return }
        pendingJourney = JourneyRequest(trainNumber: destination.trainNumber, originDate: destination.date)
        switchTab(.journey)
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

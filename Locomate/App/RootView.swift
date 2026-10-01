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
                    ExploreScreen()
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

            BottomDock(active: tab, onChange: switchTab)
                .environment(\.locomoteColors, colors)
                .padding(.horizontal, Spacing.units(3))
                .padding(.bottom, Spacing.units(2))
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

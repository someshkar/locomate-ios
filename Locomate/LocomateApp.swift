import SwiftUI

@main
struct LocomateApp: App {
    var body: some Scene {
        WindowGroup { RootView() }
    }
}

enum Tab { case journeys, explore, passport }

struct RootView: View {
    @State private var tab: Tab = .journeys
    @State private var searchPresented = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // Active screen sits above the shared map.
            Group {
                switch tab {
                case .journeys: JourneyView()
                case .explore:  ExploreView()
                case .passport: PassportView()
                }
            }
            .allowsHitTesting(true)

            CapsuleNavBar(tab: $tab, onSearch: { searchPresented = true })
                .padding(.bottom, 10)
        }
        .sheet(isPresented: $searchPresented) { SearchSheet() }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
    }
}

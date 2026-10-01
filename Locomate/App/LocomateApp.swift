import SwiftUI
import UIKit

@main
struct LocomateApp: App {
    @State private var preferences = Preferences()
    @State private var services = LocomoteServices.live()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(preferences)
                .environment(\.locomoteServices, services)
                .preferredColorScheme(preferences.dark ? .dark : .light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        NotificationCenter.default.post(name: .locomoteForeground, object: nil)
                    }
                }
        }
    }
}

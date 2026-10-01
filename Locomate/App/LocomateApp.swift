import SwiftUI
import UIKit

@main
struct LocomateApp: App {
    @State private var preferences = Preferences()
    @State private var services = LocomoteServices.live()
    @State private var dataRevision = 0
    @State private var showPartialDeletionAlert = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .id(dataRevision)
                .task { try? await services.flushPendingConsentEvidence() }
                .environment(preferences)
                .environment(\.locomoteServices, services)
                .preferredColorScheme(preferences.dark ? .dark : .light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        NotificationCenter.default.post(name: .locomoteForeground, object: nil)
                        Task { try? await services.flushPendingConsentEvidence() }
                    } else if phase == .background && !preferences.backgroundLocationEnabled {
                        services.contribution.stop()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .locomotePrivacyReset)) { notification in
                    services = LocomoteServices.live()
                    dataRevision += 1
                    showPartialDeletionAlert = notification.userInfo?["complete"] as? Bool == false
                }
                .alert("Data deletion needs attention", isPresented: $showPartialDeletionAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("The gateway record was deleted, but some device data could not be erased. Reinstall Locomate to remove any remaining local files.")
                }
        }
    }
}

extension Notification.Name {
    static let locomotePrivacyReset = Notification.Name("locomote.privacy-reset")
}

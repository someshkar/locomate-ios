import SwiftUI

struct JourneyAlertsSettings: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.locomoteServices) private var services
    @State private var showStopConfirmation = false
    @State private var working = false
    @State private var message: String?

    private var busy: Bool { working || services.journeyAlerts.isBusy }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(3)) {
                Text("Journey alerts").eyebrow(colors.textTertiary)
                Text("Manage notifications for the train runs you chose. Alert settings are separate from your Lock Screen Live card.")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
                if services.journeyAlerts.subscriptions.isEmpty {
                    Text(services.mode.isProduction
                         ? "No journey alerts enabled. Open a train journey to choose your updates."
                         : "Journey alerts are unavailable in historical preview.")
                        .font(LocomateFont.body)
                        .foregroundStyle(colors.textSecondary)
                }
                ForEach(services.journeyAlerts.subscriptions, id: \.runId) { subscription in
                    subscriptionRow(subscription)
                }
                if let message = message ?? services.journeyAlerts.message {
                    Text(message)
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)
                        .accessibilityIdentifier("settings.journeyAlerts.message")
                }
                if services.mode.isProduction {
                    LocomateButton(busy ? "Updating…" : "Refresh and retry pending changes",
                                   systemImage: "arrow.clockwise", style: .secondary, fullWidth: true) {
                        Task { await refresh() }
                    }
                    .disabled(busy)
                }
                if services.journeyAlerts.subscriptions.contains(where: { $0.enabled }) {
                    Button("Stop all journey alerts", role: .destructive) {
                        showStopConfirmation = true
                    }
                    .font(LocomateFont.bodyStrong)
                    .buttonStyle(AccessibleTextButtonStyle())
                    .disabled(busy)
                }
                Button("Open notification settings") {
                    JourneyAlertPresentation.openSystemSettings()
                }
                .font(LocomateFont.bodyStrong)
                .buttonStyle(AccessibleTextButtonStyle())
            }
            .tint(colors.accentBase)
        }
        .task { await services.journeyAlerts.refresh() }
        .confirmationDialog("Stop all journey alerts?", isPresented: $showStopConfirmation,
                            titleVisibility: .visible) {
            Button("Stop all alerts", role: .destructive) {
                Task { await stopAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops alerts for every subscribed train run. If the service cannot be reached, the stop request stays on this device for retry.")
        }
    }

    private func subscriptionRow(_ subscription: JourneyAlertSubscription) -> some View {
        VStack(alignment: .leading, spacing: Spacing.units(2)) {
            Divider().overlay(colors.borderSubtle)
            Text("\(subscription.trainNumber) · \(subscription.serviceDate)")
                .font(LocomateFont.bodyStrong)
                .foregroundStyle(colors.textPrimary)
            Text(JourneyAlertPresentation.status(subscription))
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textSecondary)
            Text(JourneyAlertChannel.allCases.filter { subscription.channels.contains($0) }
                .map(\.label).joined(separator: ", "))
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textTertiary)
            if let hours = subscription.quietHours {
                Text("Quiet hours \(String(format: "%02d:00", hours.startHour))–\(String(format: "%02d:00", hours.endHour)) · \(hours.timezone.replacingOccurrences(of: "_", with: " "))")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textTertiary)
            }
            if subscription.pending && !subscription.enabled {
                Text("Notifications may still arrive until the service confirms the stop request.")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.units(4)) { rowActions(subscription) }
                VStack(alignment: .leading, spacing: Spacing.units(1)) { rowActions(subscription) }
            }
        }
    }

    @ViewBuilder private func rowActions(_ subscription: JourneyAlertSubscription) -> some View {
        Button("Open journey") {
            guard let url = try? Routes.journeyURL(trainNumber: subscription.trainNumber,
                                                 date: subscription.serviceDate) else { return }
            UIApplication.shared.open(url)
        }
        .font(LocomateFont.bodyStrong)
        .buttonStyle(AccessibleTextButtonStyle())
        if subscription.enabled {
            Button("Stop alerts", role: .destructive) {
                Task { await stop(subscription.runId) }
            }
            .font(LocomateFont.bodyStrong)
            .buttonStyle(AccessibleTextButtonStyle())
            .disabled(busy)
        }
    }

    private func refresh() async {
        guard !busy else { return }
        working = true
        message = nil
        await services.journeyAlerts.refresh()
        working = false
    }

    private func stop(_ runId: String) async {
        guard !busy else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            try await services.journeyAlerts.disable(runId: runId)
            message = services.journeyAlerts.message
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? "The service could not confirm that alerts stopped. Retry the pending request."
        }
    }

    private func stopAll() async {
        guard !busy else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            try await services.journeyAlerts.disableAll()
            message = services.journeyAlerts.message
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? "The service could not confirm that all alerts stopped. Retry the pending requests."
        }
    }
}

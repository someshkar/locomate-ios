import SwiftUI

struct JourneyAlertsSummary: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.locomoteServices) private var services

    let journey: Journey
    let available: Bool
    let onOpen: () -> Void

    private var subscription: JourneyAlertSubscription? {
        services.journeyAlerts.subscriptions.first {
            JourneyAlertIdentity.normalize($0.runId) == JourneyAlertIdentity.normalize(journey.id)
        }
    }

    var body: some View {
        ListRow(icon: "bell.badge", title: "Journey alerts", meta: summary, onPress: onOpen) {
            Image(systemName: "chevron.right")
                .foregroundStyle(colors.textTertiary)
                .accessibilityHidden(true)
        }
        .accessibilityValue(summary)
        .accessibilityIdentifier("journeyAlerts.open")
    }

    private var summary: String {
        if PrivacyDeletionLatch.isPending { return "Stopped while data deletion is pending." }
        if let subscription { return JourneyAlertPresentation.status(subscription) }
        return available
            ? "Choose updates for this train and date."
            : "A current production journey is required."
    }
}

struct JourneyAlertsSheet: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.locomoteServices) private var services
    @Environment(\.dismiss) private var dismiss

    let journey: Journey
    let originDate: String
    let available: Bool

    @State private var channels = Set(JourneyAlertChannel.allCases)
    @State private var quietHoursEnabled = false
    @State private var startHour = 22
    @State private var endHour = 7
    @State private var timezone = TimeZone.current.identifier
    @State private var message: String?
    @State private var working = false

    private var subscription: JourneyAlertSubscription? {
        services.journeyAlerts.subscriptions.first {
            JourneyAlertIdentity.normalize($0.runId) == JourneyAlertIdentity.normalize(journey.id)
        }
    }

    private var busy: Bool { working || services.journeyAlerts.isBusy }
    private var valid: Bool { !channels.isEmpty && (!quietHoursEnabled || startHour != endHour) }
    private var active: Bool {
        guard let subscription else { return false }
        return subscription.enabled && subscription.expiresAt > Date()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.units(4)) {
                    introduction
                    if let subscription {
                        statusCard(subscription)
                    }
                    if available {
                        channelControls
                        quietHoursControls
                        consentControls
                    } else {
                        Text("Alerts need a current journey from the production service. Historical previews and cached journeys cannot enable new alerts.")
                            .font(LocomateFont.body)
                            .foregroundStyle(colors.textSecondary)
                    }
                    if let message = message ?? services.journeyAlerts.message {
                        Text(message)
                            .font(LocomateFont.caption)
                            .foregroundStyle(colors.textSecondary)
                            .accessibilityIdentifier("journeyAlerts.message")
                    }
                    if subscription?.pending == true {
                        LocomateButton("Retry pending change", systemImage: "arrow.clockwise",
                                       style: .secondary, fullWidth: true) {
                            Task { await retry() }
                        }
                        .disabled(busy)
                    }
                    Button("Open notification settings") {
                        JourneyAlertPresentation.openSystemSettings()
                    }
                    .font(LocomateFont.bodyStrong)
                    .buttonStyle(AccessibleTextButtonStyle())
                }
                .padding(Spacing.units(4))
            }
            .background(colors.canvas)
            .navigationTitle("Journey alerts")
            .navigationBarTitleDisplayMode(.inline)
            .tint(colors.accentBase)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(LocomateFont.bodyStrong)
                        .foregroundStyle(colors.onAccent)
                        .buttonStyle(.borderedProminent)
                        .tint(colors.accentBase)
                }
            }
        }
        .task {
            if let subscription {
                channels = subscription.channels
                if let quietHours = subscription.quietHours {
                    quietHoursEnabled = true
                    startHour = quietHours.startHour
                    endHour = quietHours.endHour
                    timezone = quietHours.timezone
                }
            }
            await services.journeyAlerts.refresh()
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2)) {
            Text("\(journey.trainNumber) · \(journey.trainName)")
                .font(LocomateFont.bodyStrong)
                .foregroundStyle(colors.textPrimary)
            Text("Origin date · \(originDate)")
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textSecondary)
            Text("Get notifications for changes to this train run, even when Locomate is closed. Choose the updates you want.")
                .font(LocomateFont.body)
                .foregroundStyle(colors.textSecondary)
        }
    }

    private func statusCard(_ subscription: JourneyAlertSubscription) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(2)) {
                Text(JourneyAlertPresentation.status(subscription))
                    .font(LocomateFont.bodyStrong)
                    .foregroundStyle(colors.textPrimary)
                    .accessibilityIdentifier("journeyAlerts.status")
                if subscription.pending {
                    Text(subscription.enabled
                         ? "The service has not confirmed this choice yet. Alerts may not arrive until it reconnects."
                         : "The stop request is saved on this device. Notifications may still arrive until the service confirms it.")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)
                } else if active {
                    Text("Ends automatically \(subscription.expiresAt.formatted(date: .abbreviated, time: .shortened)).")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)
                }
                if subscription.enabled {
                    Button("Stop alerts for this journey", role: .destructive) {
                        Task { await stop() }
                    }
                    .buttonStyle(AccessibleTextButtonStyle())
                    .disabled(busy)
                }
            }
        }
    }

    private var channelControls: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(3)) {
                Text("Notify me about").eyebrow(colors.textTertiary)
                ForEach(JourneyAlertChannel.allCases, id: \.self) { channel in
                    Toggle(isOn: Binding(
                        get: { channels.contains(channel) },
                        set: { selected in
                            if selected { channels.insert(channel) }
                            else { channels.remove(channel) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(channel.label)
                                .font(LocomateFont.bodyStrong)
                                .foregroundStyle(colors.textPrimary)
                            Text(JourneyAlertPresentation.detail(channel))
                                .font(LocomateFont.caption)
                                .foregroundStyle(colors.textSecondary)
                        }
                    }
                    .tint(colors.accentBase)
                    .accessibilityIdentifier("journeyAlerts.channel.\(channel.rawValue)")
                }
                if channels.isEmpty {
                    Text("Choose at least one update.")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.pair(for: .error).fg)
                }
            }
        }
        .disabled(busy)
    }

    private var quietHoursControls: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(3)) {
                Toggle("Quiet hours", isOn: $quietHoursEnabled)
                    .font(LocomateFont.bodyStrong)
                    .foregroundStyle(colors.textPrimary)
                    .tint(colors.accentBase)
                    .accessibilityIdentifier("journeyAlerts.quietHours")
                Text("Alerts during quiet hours are skipped. Hours follow the time zone you choose.")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
                if quietHoursEnabled {
                    hourPicker("From", selection: $startHour)
                    hourPicker("Until", selection: $endHour)
                    NavigationLink {
                        JourneyAlertTimeZonePicker(selection: $timezone)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Time zone")
                            Spacer()
                            Text(timezone.replacingOccurrences(of: "_", with: " "))
                                .multilineTextAlignment(.trailing)
                        }
                        .font(LocomateFont.caption)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    if startHour == endHour {
                        Text("Choose different start and end hours.")
                            .font(LocomateFont.caption)
                            .foregroundStyle(colors.pair(for: .error).fg)
                    }
                }
            }
        }
        .disabled(busy)
    }

    private func hourPicker(_ label: String, selection: Binding<Int>) -> some View {
        Picker(label, selection: selection) {
            ForEach(0..<24) { hour in
                Text(String(format: "%02d:00", hour)).tag(hour)
            }
        }
        .pickerStyle(.menu)
        .font(LocomateFont.body)
        .foregroundStyle(colors.textPrimary)
        .buttonStyle(AccessibleTextButtonStyle())
    }

    private var consentControls: some View {
        VStack(alignment: .leading, spacing: Spacing.units(3)) {
            Text(JourneyAlertConsent.notice)
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textSecondary)
            LocomateButton(busy ? "Saving…" : (active ? "Agree and save choices" : "Agree and enable alerts"),
                           systemImage: "bell.badge", fullWidth: true) {
                Task { await save() }
            }
            .disabled(!valid || busy || (subscription?.pending == true && subscription?.enabled == false))
            .accessibilityIdentifier("journeyAlerts.enable")
        }
    }

    private func save() async {
        guard !busy, valid, available else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            let quietHours = quietHoursEnabled
                ? JourneyAlertQuietHours(startHour: startHour, endHour: endHour, timezone: timezone) : nil
            try await services.journeyAlerts.enable(journey: journey, channels: channels, quietHours: quietHours)
            message = services.journeyAlerts.message
            Haptics.confirm()
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? "The service could not confirm your alert choices. Check the status above and retry."
            Haptics.warn()
        }
    }

    private func stop() async {
        guard !busy else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            try await services.journeyAlerts.disable(runId: journey.id)
            message = services.journeyAlerts.message
        } catch {
            message = (error as? LocalizedError)?.errorDescription
                ?? "The service could not confirm that alerts stopped. Check the status above and retry."
        }
    }

    private func retry() async {
        guard !busy else { return }
        working = true
        message = nil
        await services.journeyAlerts.refresh()
        working = false
    }
}

struct JourneyAlertTimeZonePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: String
    @State private var search = ""

    private var timezones: [String] {
        let identifiers = Set(TimeZone.knownTimeZoneIdentifiers + [selection]).sorted()
        guard !search.isEmpty else { return identifiers }
        return identifiers.filter {
            $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List(timezones, id: \.self) { timezone in
            Button {
                selection = timezone
                dismiss()
            } label: {
                HStack {
                    Text(timezone.replacingOccurrences(of: "_", with: " "))
                    Spacer()
                    if timezone == selection {
                        Image(systemName: "checkmark").accessibilityHidden(true)
                    }
                }
            }
            .accessibilityAddTraits(timezone == selection ? .isSelected : [])
        }
        .searchable(text: $search, prompt: "Search city or region")
        .navigationTitle("Time zone")
    }
}

enum JourneyAlertPresentation {
    static func status(_ subscription: JourneyAlertSubscription) -> String {
        if subscription.pending {
            return subscription.enabled ? "Alert choices pending" : "Stop request pending"
        }
        if !subscription.enabled { return "Alerts off" }
        if subscription.expiresAt <= Date() { return "Alerts expired" }
        return "Alerts on · \(subscription.channels.count) update types"
    }

    static func detail(_ channel: JourneyAlertChannel) -> String {
        switch channel.rawValue {
        case "position": return "When the observed station changes."
        case "delay": return "When the reported delay changes by 5 minutes or more."
        case "platform": return "When an updated platform is reported."
        case "departure": return "Reported departures from stations on this run."
        case "arrival": return "Reported arrivals at stations on this run."
        default: return "Updates for this journey."
        }
    }

    @MainActor static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

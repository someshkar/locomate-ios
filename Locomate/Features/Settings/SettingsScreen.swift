//
//  SettingsScreen.swift
//  Locomate
//
//  Appearance, privacy and data health — ported from SmartRail
//  `src/screens/Settings/SettingsView.tsx`. The dark/light switch animates its
//  track colour and thumb; the map lighting control persists independently.
//

import SwiftUI

struct SettingsScreen: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locomoteServices) private var services
    @Environment(Preferences.self) private var preferences
    @State private var preparingExport = false
    @State private var deletingData = false
    @State private var showDeleteConfirmation = false
    @State private var showShareSheet = false
    @State private var exportedFile: URL?
    @State private var privacyMessage: String?

    let onBack: (() -> Void)?

    var body: some View {
        @Bindable var preferences = preferences

        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.units(4)) {
                SectionHeader(
                    eyebrow: nil,
                    title: "Settings",
                    meta: "Appearance, privacy and data health"
                ) {
                    if let onBack {
                        iconButton("chevron.left", label: "Back to Rail Passport", action: onBack)
                    }
                }

                darkModeRow
                dataSourceRow
                mapLightingRow
                JourneyAlertsSettings()
                ContributionSettings()
                privacyDataRow

                LocomateButton("Open official NTES", systemImage: "globe", action: {
                    if let url = URL(string: "https://enquiry.indianrail.gov.in/mntes/") {
                        UIApplication.shared.open(url)
                    }
                })
            }
            .padding(Spacing.units(4.5))
            .padding(.bottom, 140)
        }
        .background(colors.canvas.ignoresSafeArea())
        .confirmationDialog("Delete all Locomate data?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete server and device data", role: .destructive) {
                Task { await deletePrivacyData() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your gateway installation, saved journeys, cached runs, and pending observations. It cannot be undone.")
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            if let exportedFile { try? FileManager.default.removeItem(at: exportedFile) }
            exportedFile = nil
        }) {
            if let exportedFile { PrivacyShareSheet(url: exportedFile) }
        }
    }

    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        ScaleButton(accessibilityLabel: label, action: action) {
            ZStack {
                Circle().fill(colors.elevated)
                Circle().strokeBorder(colors.borderSubtle, lineWidth: 0.75)
                Image(systemName: system)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(colors.textPrimary)
            }
            .frame(width: 44, height: 44)
        }
    }

    // MARK: Rows

    private var darkModeRow: some View {
        AnimatedListRow(
            icon: preferences.dark ? "moon.fill" : "sun.max.fill",
            title: "Dark mode",
            meta: preferences.dark ? "On · tap to switch" : "Off · tap to switch",
            onPress: {
                Haptics.select()
                withAnimation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion)) {
                    preferences.dark.toggle()
                }
            }
        ) {
            AnimatedSwitch(isOn: preferences.dark)
        }
    }

    private var dataSourceRow: some View {
        let production = services.mode.isProduction
        return ListRow(
            icon: "cylinder.split.1x2.fill",
            title: "Rail data source",
            meta: production ? "Production API configured" : "Open historical snapshot only"
        )
    }

    private var mapLightingRow: some View {
        @Bindable var preferences = preferences
        return VStack(alignment: .leading, spacing: Spacing.units(2)) {
            Text("Map lighting").eyebrow(colors.textTertiary)
            Picker("Map lighting", selection: $preferences.mapLighting) {
                ForEach(Preferences.MapLighting.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text("Automatic follows the sun at the train's position. This is independent of your app appearance.")
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textTertiary)
        }
        .padding(Spacing.units(4))
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
    }

    private var privacyDataRow: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2.5)) {
            Text("YOUR DATA").eyebrow(colors.textTertiary)
            Text("Export your gateway record and this device's saved journeys, pending observations, and cached runs across data sources. The file can contain location and session tokens; share it only with a destination you trust.")
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textSecondary)
            LocomateButton(preparingExport ? "Preparing export…" : "Export my data",
                           systemImage: "square.and.arrow.up", style: .secondary,
                           fullWidth: true) {
                Task { await exportPrivacyData() }
            }
            .disabled(preparingExport || deletingData)
            LocomateButton(deletingData ? "Deleting data…" : "Delete my data",
                           systemImage: "trash", style: .secondary, fullWidth: true) {
                showDeleteConfirmation = true
            }
            .disabled(preparingExport || deletingData)
            if let privacyMessage {
                Text(privacyMessage).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            }
        }
        .padding(Spacing.units(4))
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
    }

    private func exportPrivacyData() async {
        guard !preparingExport && !deletingData else { return }
        preparingExport = true
        privacyMessage = nil
        defer { preparingExport = false }
        do {
            exportedFile = try await services.exportPrivacyData(preferences: preferences)
            showShareSheet = true
        } catch {
            privacyMessage = (error as? APIError)?.message ?? "Could not prepare your data export. Try again."
        }
    }

    private func deletePrivacyData() async {
        guard !preparingExport && !deletingData else { return }
        deletingData = true
        privacyMessage = nil
        defer { deletingData = false }
        do {
            let complete = try await services.deletePrivacyData(preferences: preferences)
            NotificationCenter.default.post(name: .locomotePrivacyReset, object: nil,
                                            userInfo: ["complete": complete])
        } catch {
            privacyMessage = "Could not delete your data. Saved data remains on this device. Start the Live card again if needed."
        }
    }
}

private struct PrivacyShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Animated switch

/// Track colour interpolates and the thumb slides with a snappy spring.
struct AnimatedSwitch: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? colors.accentBase : Color(hex: 0xCED2CD))
                .frame(width: 46, height: 26)
            Circle()
                .fill(isOn ? Palette.ink900 : Palette.white)
                .frame(width: 20, height: 20)
                .padding(3)
        }
        .animation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion), value: isOn)
        .accessibilityHidden(true)
    }
}

/// A list row with a trailing accessory and a pressable body.
struct AnimatedListRow<Trailing: View>: View {
    @Environment(\.locomoteColors) private var colors
    let icon: String
    let title: String
    let meta: String?
    let onPress: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        ScaleButton(accessibilityLabel: title, haptic: false, action: onPress) {
            HStack(spacing: Spacing.units(3)) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(colors.accentBase)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(LocomateFont.bodyStrong).foregroundStyle(colors.textPrimary)
                    if let meta {
                        Text(meta).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    }
                }
                Spacer(minLength: Spacing.units(3))
                trailing()
            }
            .padding(.horizontal, Spacing.units(4))
            .padding(.vertical, Spacing.units(3.5))
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(colors.elevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
        }
    }
}

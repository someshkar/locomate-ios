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
                ContributionSettings()

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

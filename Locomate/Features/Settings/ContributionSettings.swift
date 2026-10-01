//
//  ContributionSettings.swift
//  Locomate
//
//  Community contribution consent — ported from SmartRail
//  `src/components/ContributionSettings.tsx` + `src/privacy/consent.ts`.
//
//  Rules preserved: explicit versioned consent, foreground and background are
//  separate choices, background requires foreground, and revocation wipes the
//  local queue immediately.
//

import SwiftUI

struct ContributionSettings: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(Preferences.self) private var preferences
    @Environment(\.locomoteServices) private var services

    @State private var showRevokeConfirm = false
    @State private var showGrantConfirm = false
    @State private var consentBusy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2.5)) {
            HStack {
                Text("Community contribution").eyebrow(colors.textTertiary)
                Spacer()
                Text("v\(Consent.version)")
                    .font(LocomateFont.data)
                    .foregroundStyle(colors.textTertiary)
            }

            ContributionToggle(
                icon: "location.fill",
                title: "Contribute while using the app",
                meta: services.railService == nil
                    ? "A production rail gateway is required. Historical previews are excluded."
                    : "Share a location observation only for a current journey you open.",
                isOn: preferences.contributionsEnabled,
                disabled: services.railService == nil || consentBusy,
                onChange: { enabled in
                    if enabled { showGrantConfirm = true }
                    else { showRevokeConfirm = true }
                }
            )

            ContributionToggle(
                icon: "location.circle",
                title: "Continue in the background",
                meta: preferences.contributionsEnabled
                    ? "Keep contributing while the app is in the background or the screen is off."
                    : "Enable foreground contribution first.",
                isOn: preferences.backgroundLocationEnabled,
                disabled: !preferences.contributionsEnabled || consentBusy,
                onChange: { enabled in
                    withAnimation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion)) {
                        preferences.backgroundLocationEnabled = enabled
                    }
                    services.contribution.updateBackground(enabled)
                    message = enabled
                        ? "Background contribution will continue while a current journey is active."
                        : "Background contribution is off."
                }
            )

            Text("Onboard positions are optional. No name, phone, PNR, coach or seat is sent with a location observation. Raw gateway observations expire after 24 hours; independent evidence is required before a contributor can raise confidence.")
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textTertiary)

            if preferences.contributionsEnabled {
                ScaleButton(accessibilityLabel: "Revoke consent and delete local observations", action: {
                    showRevokeConfirm = true
                }) {
                    Text("Revoke consent and delete local observations")
                        .font(LocomateFont.bodyStrong)
                        .foregroundStyle(colors.pair(for: .error).fg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(colors.pair(for: .error).bg))
                }
            }

            if preferences.contributionsEnabled {
                Text("\(services.contribution.queuedCount) observation(s) queued on this device")
                    .font(LocomateFont.data)
                    .foregroundStyle(colors.textTertiary)
            }

            if let message {
                Text(message)
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .padding(Spacing.units(4))
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
        .confirmationDialog("Enable community contribution?", isPresented: $showGrantConfirm,
                            titleVisibility: .visible) {
            Button("I consent and enable") {
                consentBusy = true
                Task { @MainActor in
                    defer { consentBusy = false }
                    do {
                        try await services.grantContributionConsent(preferences: preferences)
                        message = "Consent recorded. Only a current journey you open can start collection."
                        Haptics.success()
                    } catch {
                        message = "Consent could not be recorded with the gateway. No location collection was enabled."
                        Haptics.warn()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Consent.notice)
        }
        .confirmationDialog(
            "Revoke consent?",
            isPresented: $showRevokeConfirm,
            titleVisibility: .visible
        ) {
            Button("Revoke and delete", role: .destructive) {
                Haptics.warn()
                var withdrawalSaved = false
                withAnimation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion)) {
                    withdrawalSaved = services.revokeContributionConsent(preferences: preferences)
                }
                message = withdrawalSaved
                    ? "Collection stopped and local observations deleted. Sending withdrawal to the gateway…"
                    : "Collection stopped here, but the withdrawal could not be saved. Please retry while online."
                guard withdrawalSaved else { return }
                Task { @MainActor in
                    do {
                        try await services.flushPendingConsentEvidence()
                        message = "Consent withdrawn on this device and the gateway."
                    } catch {
                        message = "Collection stopped here. Gateway withdrawal is saved for retry when online."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This immediately stops collection and erases queued observations from this device.")
        }
    }
}

private struct ContributionToggle: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let title: String
    let meta: String
    let isOn: Bool
    var disabled = false
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: Spacing.units(3)) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(disabled ? colors.textTertiary : colors.accentBase)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LocomateFont.bodyStrong)
                    .foregroundStyle(disabled ? colors.textTertiary : colors.textPrimary)
                Text(meta).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            }
            Spacer(minLength: Spacing.units(2))
            AnimatedSwitch(isOn: isOn)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !disabled else { return }
            onChange(!isOn)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(disabled ? "Unavailable. " + meta : (isOn ? "On" : "Off"))
        .accessibilityAddTraits(.isButton)
        .disabled(disabled)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

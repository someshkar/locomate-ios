//
//  PassportScreen.swift
//  Locomate
//
//  Private travel history — ported from SmartRail
//  `src/screens/Passport/PassportView.tsx` + `PassportHeroCard`.
//  Coach and seat are never persisted. Settings are pushed from here.
//

import SwiftUI

struct PassportScreen: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.locomoteServices) private var services
    let onOpenSearch: () -> Void

    @State private var journeys: [SavedJourney] = []
    @State private var showSettings = false
    @State private var loaded = false

    private var stats: PassportStats { Passport.summarize(journeys) }

    var body: some View {
        Group {
            if showSettings {
                SettingsScreen(onBack: { showSettings = false })
            } else {
                content
            }
        }
        .task {
            guard !loaded else { return }
            journeys = await services.passport.load()
            loaded = true
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.units(4)) {
                SectionHeader(
                    eyebrow: "THE PLACES YOU GO",
                    title: "Passport",
                    meta: "Saved rail runs, private on this device."
                ) {
                    iconButton("gearshape", label: "Open settings") { showSettings = true }
                }

                if !journeys.isEmpty {
                    PassportHeroCard(stats: stats, previewCount: journeys.filter { $0.preview == true }.count)
                    journeyList
                } else if loaded {
                    emptyState
                }
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

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Spacing.units(6)) {
            HStack(spacing: Spacing.units(3.5)) {
                Circle().fill(colors.accentBase).frame(width: 10, height: 10)
                Rectangle().fill(colors.accentLine).frame(height: 2)
                Image(systemName: "tram.fill")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(colors.accentBase)
                Rectangle().fill(colors.accentLine).frame(height: 2)
                Circle().strokeBorder(colors.accentBase, lineWidth: 2).frame(width: 10, height: 10)
            }
            .padding(Spacing.units(6))
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(colors.accentWash))

            VStack(alignment: .leading, spacing: Spacing.units(2)) {
                Text("A thousand places.\nYour first page.")
                    .font(LocomateFont.display)
                    .tracking(-1.4)
                    .foregroundStyle(colors.textPrimary)
                Text("Save a journey to start your rail passport. Your routes, kilometres and memories, collected in one place.")
                    .font(LocomateFont.body)
                    .foregroundStyle(colors.textSecondary)
            }
            LocomateButton("Find your next train", fullWidth: true, action: onOpenSearch)
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").font(.system(size: 13))
                Text("Stored on this device. No account needed.")
                    .font(LocomateFont.caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(colors.textSecondary)
        }
        .padding(Spacing.units(6))
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
    }

    private var journeyList: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2.5)) {
            Text("Saved journeys").eyebrow(colors.textTertiary)
            ForEach(Array(journeys.enumerated()), id: \.element.id) { index, journey in
                StaggerIn(index: index) {
                    SavedJourneyRow(journey: journey) {
                        Task { await remove(journey) }
                    }
                }
            }
        }
    }

    private func remove(_ journey: SavedJourney) async {
        Haptics.warn()
        var current = await services.passport.load()
        current.removeAll { $0.id == journey.id }
        await services.passport.save(current)
        withAnimation(Motion.card) { journeys = current }
    }
}

// MARK: - Hero stats

struct PassportHeroCard: View {
    @Environment(\.locomoteColors) private var colors
    let stats: PassportStats
    let previewCount: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(4)) {
                Text("SAVED RUNS · AS OF TODAY").eyebrow(colors.textTertiary)
                HStack(alignment: .top, spacing: Spacing.units(4)) {
                    Stat(label: "Saved runs", value: "\(stats.trips)")
                    Stat(label: "Route km", value: "\(Int(stats.distanceKm.rounded()))")
                    Stat(label: "Routes", value: "\(stats.uniqueRoutes)")
                }
                Text("Distance in saved runs, not verified travel history.\(previewCount > 0 ? " \(previewCount) route preview\(previewCount == 1 ? " is" : "s are") excluded." : "")")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
                Divider().overlay(colors.borderSubtle)
                HStack(alignment: .top, spacing: Spacing.units(4)) {
                    Stat(label: "Stations", value: "\(stats.uniqueStations)")
                    Stat(label: "Trains", value: "\(stats.uniqueTrains)")
                    Stat(label: "Scheduled",
                         value: "\(stats.minutes / 60)", unit: "h")
                }
                if let top = stats.routeFrequency.first {
                    Text("Most saved: \(top.originCode) → \(top.destinationCode) · \(top.trips) \(top.trips == 1 ? "run" : "runs")")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct SavedJourneyRow: View {
    @Environment(\.locomoteColors) private var colors
    let journey: SavedJourney
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.units(3)) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Spacing.units(2)) {
                    Text(journey.trainNumber)
                        .font(LocomateFont.data)
                        .monospacedDigit()
                        .foregroundStyle(colors.accentBase)
                    Text(journey.trainName)
                        .font(LocomateFont.bodyStrong)
                        .foregroundStyle(colors.textPrimary)
                        .lineLimit(1)
                }
                Text("\(journey.originCode) → \(journey.destinationCode) · \(journey.originDate)")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
                if journey.preview != false {
                    Text(journey.preview == true ? "PREVIEW · NOT LIVE" : "LEGACY · SOURCE UNVERIFIED")
                        .eyebrow(colors.pair(for: .preview).fg)
                }
                HStack(spacing: Spacing.units(2.5)) {
                    Text("\(Int(journey.distanceKm.rounded())) km")
                    Text(durationLabel(journey.minutes))
                }
                .font(LocomateFont.micro)
                .monospacedDigit()
                .foregroundStyle(colors.textTertiary)
            }
            Spacer(minLength: 0)
            ScaleButton(accessibilityLabel: "Remove saved journey", action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(colors.pair(for: .error).fg)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(Spacing.units(4))
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
        .accessibilityElement(children: .contain)
    }

    private func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
}

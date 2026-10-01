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
    var onOpenJourney: (SavedJourney) -> Void = { _ in }

    @State private var journeys: [SavedJourney] = []
    @State private var showSettings = false
    @State private var loaded = false
    @State private var period = PassportPeriod.allTime

    private var visibleJourneys: [SavedJourney] { period.filter(journeys) }
    private var stats: PassportStats { Passport.summarize(visibleJourneys) }
    private var years: [Int] { PassportPeriod.years(in: journeys) }

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
        .onChange(of: years) { _, available in
            if case .year(let selected) = period, !available.contains(selected) { period = .allTime }
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
                    PassportPeriodPicker(years: years, selection: $period)
                    PassportHeroCard(stats: stats, previewCount: visibleJourneys.filter { $0.preview == true }.count,
                                     periodLabel: period.label)
                    journeyList
                } else if loaded {
                    emptyState
                }
            }
            .padding(Spacing.units(4.5))
            .padding(.bottom, 140)
        }
        .background(colors.canvas.ignoresSafeArea())
        .accessibilityIdentifier("passport.content")
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
                    .fixedSize(horizontal: false, vertical: true)
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
            Text("\(period.label) saved journeys").eyebrow(colors.textTertiary)
            ForEach(Array(visibleJourneys.enumerated()), id: \.element.id) { index, journey in
                StaggerIn(index: index) {
                    SavedJourneyRow(journey: journey,
                        canOpen: PassportReopening.destination(for: journey, production: services.mode.isProduction) != nil,
                        onOpen: { onOpenJourney(journey) },
                        onDelete: { Task { await remove(journey) } })
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

/// A run belongs to the year of its train's India origin date, not the year it
/// was saved. Previews and legacy source-unknown entries stay in All-Time only.
enum PassportPeriod: Equatable, Hashable {
    case allTime
    case year(Int)

    var label: String {
        switch self {
        case .allTime: "All-Time"
        case .year(let year): String(year)
        }
    }

    static func years(in journeys: [SavedJourney]) -> [Int] {
        Array(Set(journeys.compactMap(year))).sorted(by: >)
    }

    func filter(_ journeys: [SavedJourney]) -> [SavedJourney] {
        guard case .year(let selected) = self else { return journeys }
        return journeys.filter { Self.year($0) == selected }
    }

    private static func year(_ journey: SavedJourney) -> Int? {
        guard journey.preview == false, Routes.isValidCalendarDate(journey.originDate) else { return nil }
        return Int(journey.originDate.prefix(4))
    }
}

struct PassportPeriodPicker: View {
    @Environment(\.locomoteColors) private var colors
    let years: [Int]
    @Binding var selection: PassportPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Train origin year").font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([PassportPeriod.allTime] + years.map(PassportPeriod.year), id: \.self) { period in
                        Button {
                            guard selection != period else { return }
                            Haptics.select()
                            selection = period
                        } label: {
                            Text(period.label)
                                .font(LocomateFont.bodyStrong)
                                .fixedSize()
                                .padding(.horizontal, 16)
                                .frame(minHeight: 44)
                                .foregroundStyle(selection == period ? colors.accentBase : colors.textSecondary)
                                .background(selection == period ? colors.accentWash : colors.elevated, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("passport.period.\(period.label)")
                        .accessibilityAddTraits(selection == period ? .isSelected : [])
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("passport.periods")
        }
    }
}

// MARK: - Hero stats

struct PassportHeroCard: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let stats: PassportStats
    let previewCount: Int
    var periodLabel = "All-Time"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.units(3)) {
            Text("SAVED RUNS · \(periodLabel)").eyebrow(colors.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(Int(stats.distanceKm.rounded()).formatted())
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text("km")
                    .font(LocomateFont.title)
            }
            .foregroundStyle(colors.textPrimary)
            Text("Distance in saved runs, not verified travel history.\(previewCount > 0 ? " \(previewCount) route preview\(previewCount == 1 ? " is" : "s are") excluded." : "")")
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textSecondary)
            Divider().overlay(colors.borderSubtle)
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.units(3)))
                : AnyLayout(HStackLayout(spacing: Spacing.units(2)))) {
                metric("SAVED RUNS", value: "\(stats.trips)")
                metric("SCHEDULED", value: durationLabel)
                metric("STATIONS", value: "\(stats.uniqueStations)")
            }
            if let top = stats.routeFrequency.first {
                Text("Most saved: \(top.originCode) → \(top.destinationCode) · \(top.trips) \(top.trips == 1 ? "run" : "runs")")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textTertiary)
            }
        }
        .padding(Spacing.units(5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(colors.elevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.violet400.opacity(0.18), colors.accentWash],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
        .accessibilityElement(children: .contain)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow(colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("passport.metric.\(label)")
            Text(value).font(LocomateFont.title).monospacedDigit().foregroundStyle(colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var durationLabel: String {
        guard stats.minutes > 0 else { return "—" }
        let hours = stats.minutes / 60
        let minutes = stats.minutes % 60
        return hours == 0 ? "\(minutes)m" : (minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m")
    }
}

private struct SavedJourneyRow: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let journey: SavedJourney
    let canOpen: Bool
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.units(3)) {
            VStack(alignment: .leading, spacing: 4) {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.units(2)))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.units(2)))) {
                    Text(journey.trainNumber)
                        .font(LocomateFont.data)
                        .monospacedDigit()
                        .foregroundStyle(colors.accentBase)
                    Text(journey.trainName)
                        .font(LocomateFont.bodyStrong)
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("passport.name.\(journey.id)")
                }
                Text("\(journey.originCode) → \(journey.destinationCode) · \(journey.originDate)")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if journey.preview != false {
                    Text(journey.preview == true ? "PREVIEW · NOT LIVE" : "LEGACY · SOURCE UNVERIFIED")
                        .eyebrow(colors.pair(for: .preview).fg)
                }
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.units(1)))
                    : AnyLayout(HStackLayout(spacing: Spacing.units(2.5)))) {
                    Text("\(Int(journey.distanceKm.rounded())) km")
                    Text(durationLabel(journey.minutes))
                }
                .font(LocomateFont.micro)
                .monospacedDigit()
                .foregroundStyle(colors.textTertiary)
            }
            HStack(alignment: .center, spacing: 16) {
                Button(action: onOpen) {
                    Label("Open journey", systemImage: "arrow.up.right")
                        .font(LocomateFont.bodyStrong)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(canOpen ? colors.accentBase : colors.textTertiary)
                .disabled(!canOpen)
                .accessibilityLabel("Open saved journey \(journey.trainNumber), \(journey.trainName), \(journey.originDate)")
                .accessibilityIdentifier("passport.open.\(journey.id)")
                ScaleButton(accessibilityLabel: "Remove saved journey \(journey.trainNumber), \(journey.originDate)", action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(colors.pair(for: .error).fg)
                        .frame(width: 44, height: 44)
                }
                .accessibilityIdentifier("passport.remove.\(journey.id)")
            }
            if !canOpen {
                Text("This saved entry has no verified dated route for the current data source.")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Spacing.units(4))
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
        .accessibilityElement(children: .contain)
    }

    private func durationLabel(_ minutes: Int) -> String {
        guard minutes > 0 else { return "Duration unavailable" }
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
}

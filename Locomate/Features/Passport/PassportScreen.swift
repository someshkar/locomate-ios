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
    private var indiaYear: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return calendar.component(.year, from: Date())
    }
    private var thisYearStats: PassportStats {
        Passport.summarize(PassportPeriod.year(indiaYear).filter(journeys))
    }

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
        OverviewPage(sheetStyle: .passport) { _ in
            PassportNightBackdrop()
        } sheet: {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.units(4)) {
                    HStack(alignment: .top) {
                        Text("Passport")
                            .pageHeading(.passport)
                            .foregroundStyle(colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        iconButton("gearshape", label: "Open settings") { showSettings = true }
                    }
                    Text("Saved rail runs, private on this device.")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)

                    if !journeys.isEmpty {
                        PassportPeriodPicker(years: years, selection: $period)
                        PassportHeroCard(stats: stats, previewCount: visibleJourneys.filter { $0.preview == true }.count,
                                         periodLabel: period.label)
                        if period == .allTime, thisYearStats.trips > 0 {
                            thisYearTeaser
                        }
                        journeyList
                    } else if loaded {
                        emptyState
                    }
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .accessibilityIdentifier("passport.content")
        }
    }

    private var thisYearTeaser: some View {
        let current = thisYearStats
        let summary = current.distanceKm > 0
            ? "\(Int(current.distanceKm.rounded()).formatted()) km · \(current.trips) saved \(current.trips == 1 ? "run" : "runs")"
            : "\(current.trips) saved \(current.trips == 1 ? "run" : "runs") · distance unavailable"
        return Button {
            Haptics.select()
            period = .year(indiaYear)
        } label: {
            HStack(spacing: Spacing.units(3)) {
                VStack(alignment: .leading, spacing: Spacing.units(1)) {
                    Text("THIS YEAR — " + String(indiaYear)).eyebrow(colors.textTertiary)
                    Text(summary)
                        .font(LocomateFont.bodyStrong)
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
            }
            .padding(Spacing.units(3.5))
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(colors.elevated.opacity(0.68)))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(indiaYear) saved runs")
        .accessibilityValue(summary)
        .accessibilityIdentifier("passport.thisYear")
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
                Text("A thousand places. Your first page.")
                    .font(LocomateFont.display)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
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

/// The Passport summary has no verified route geometry; its canvas uses an illustrative
/// night view of India rather than a live, tappable map.
private struct PassportNightBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            Image("PassportNightMap")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [Color(hex: 0x05060C).opacity(0.05),
                                 Color(hex: 0x06070E).opacity(0.60),
                                 Color(hex: 0x080912).opacity(0.99)],
                        startPoint: .top, endPoint: .bottom)
                }
                .overlay {
                    Canvas { context, size in
                        let x = size.width / 390
                        let y = size.height / 844
                        var orbit = Path()
                        orbit.move(to: CGPoint(x: 110 * x, y: 110 * y))
                        orbit.addQuadCurve(to: CGPoint(x: 300 * x, y: 130 * y),
                                           control: CGPoint(x: 210 * x, y: 60 * y))
                        context.stroke(orbit, with: .color(Color(hex: 0xAFA0FF).opacity(0.35)), lineWidth: 1)
                        let hub = CGPoint(x: 205 * x, y: 170 * y)
                        context.fill(Path(ellipseIn: CGRect(x: hub.x - 8, y: hub.y - 8,
                                                           width: 16, height: 16)),
                                     with: .color(Color(hex: 0xAFA0FF).opacity(0.5)))
                        context.stroke(Path(ellipseIn: CGRect(x: hub.x - 16, y: hub.y - 16,
                                                             width: 32, height: 32)),
                                       with: .color(Color(hex: 0xAFA0FF).opacity(0.25)), lineWidth: 1)
                    }
                }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
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
                                .foregroundStyle(selection == period ? colors.textPrimary : colors.textSecondary)
                                .background(colors.textPrimary.opacity(selection == period ? 0.12 : 0.05), in: Capsule())
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
    @ScaledMetric(relativeTo: .largeTitle) private var distanceSize: CGFloat = 56
    @ScaledMetric(relativeTo: .headline) private var unitSize: CGFloat = 22
    @ScaledMetric(relativeTo: .headline) private var metricSize: CGFloat = 20
    private let primary = Color.white
    private let secondary = Color(hex: 0xCDBAF6)
    private let heroLabel = Color(hex: 0xBEACF1)
    let stats: PassportStats
    let previewCount: Int
    var periodLabel = "All-Time"

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.units(3)) {
            Text("SAVED RUNS · \(periodLabel)").eyebrow(heroLabel)
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))) {
                Text(Int(stats.distanceKm.rounded()).formatted())
                    .font(dynamicTypeSize.isAccessibilitySize ? .system(.largeTitle, weight: .heavy)
                          : .system(size: distanceSize, weight: .heavy))
                    .tracking(-2)
                    .fixedSize(horizontal: false, vertical: true)
                    .monospacedDigit()
                Text("km")
                    .font(.system(size: unitSize, weight: .bold))
                    .foregroundStyle(secondary)
            }
            .foregroundStyle(primary)
            Text("Distance in saved runs, not verified travel history.\(previewCount > 0 ? " \(previewCount) route preview\(previewCount == 1 ? " is" : "s are") excluded." : "")")
                .font(LocomateFont.caption)
                .foregroundStyle(secondary)
            Divider().overlay(heroLabel.opacity(0.18))
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
                    .foregroundStyle(heroLabel)
            }
        }
        .padding(Spacing.units(5))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x17123A), Color(hex: 0x100D28), Color(hex: 0x0A0A1C)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(heroLabel.opacity(0.22), lineWidth: 1)
                }
        }
        .shadow(color: Color(hex: 0x28085A).opacity(0.35), radius: 20, y: 10)
        .accessibilityElement(children: .contain)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).eyebrow(heroLabel)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("passport.metric.\(label)")
            Text(value).font(.system(size: metricSize, weight: .heavy)).monospacedDigit().foregroundStyle(primary)
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

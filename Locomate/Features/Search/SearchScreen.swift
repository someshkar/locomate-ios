//
//  SearchScreen.swift
//  Locomate
//
//  Train search with a quick-date picker — ported from SmartRail
//  `src/screens/Search/SearchView.tsx`.
//  Debounced (350ms) query, 7-day origin-date strip, honest mode notice,
//  editorial empty/no-result/error states, staggered result entrances.
//

import SwiftUI

struct SearchScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.locomoteServices) private var services
    @Environment(Preferences.self) private var preferences
    var onSelect: (TrainSearchResult, String) -> Void = { _, _ in }

    @State private var query = ""
    @State private var results: [TrainSearchResult] = []
    @State private var resultQuery = ""
    @State private var loading = false
    @State private var error: String?
    @State private var selectedDate = IndiaDate.today()
    @State private var calendarDraft = Date()
    @State private var showsCalendar = false
    @State private var recentNotice: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool
    @ScaledMetric(relativeTo: .body) private var fieldSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var subtitleSize: CGFloat = 13.5

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var production: Bool { services.mode.isProduction }
    private var currentResults: [TrainSearchResult] { resultQuery == normalizedQuery ? results : [] }
    private var currentError: String? { resultQuery == normalizedQuery ? error : nil }

    private var quickDates: [String] {
        let today = IndiaDate.today()
        return (-1...5).compactMap { try? IndiaDate.addDays(today, $0) }
    }

    var body: some View {
        OverviewPage(hidesMap: isFieldFocused) { viewport in
            PassportMapBackdrop(viewportOnScreen: viewport)
        } sheet: {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.units(4)) {
                    intro
                    searchField
                    dateStrip
                    if !production { snapshotNotice }
                    if normalizedQuery.isEmpty { recentList }
                    if let error = currentError {
                        EmptyState(icon: "wifi.exclamationmark",
                                   title: "Couldn't reach the railway feed",
                                   body: error,
                                   actionTitle: "Try again",
                                   onAction: { runSearch(immediate: true) })
                    }
                    if !loading && currentError == nil && normalizedQuery.count >= 2 && currentResults.isEmpty {
                        EmptyState(icon: "magnifyingglass",
                                   title: "No trains found",
                                   body: "Try a five-digit train number or part of the train's name.")
                    }
                    resultList
                }
                .padding(Spacing.units(5))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: query) { _, _ in runSearch() }
        .onDisappear { searchTask?.cancel() }
        .sheet(isPresented: $showsCalendar) { originDateCalendar }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Search")
                .pageHeading()
                .foregroundStyle(colors.textPrimary)
            Text("Find trains by name or number")
                .font(.system(size: subtitleSize))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            NavigationGlyph(tab: .search, side: 20).foregroundStyle(colors.textTertiary)
            TextField(dynamicTypeSize.isAccessibilitySize ? "Train" : "Train name or number", text: $query)
                .focused($isFieldFocused)
                .font(.system(size: fieldSize, weight: .medium))
                .foregroundStyle(colors.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search trains")
                .onSubmit { isFieldFocused = false }
            if loading {
                ProgressView().controlSize(.small).tint(colors.accentBase)
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(colors.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(colors.dark && !reduceTransparency ? Palette.white.opacity(0.05) : colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(colors.dark ? Palette.white.opacity(0.09) : colors.borderSubtle, lineWidth: 1))
    }

    private var dateStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2)) {
            dateHeaderLayout {
                Text("Origin date").eyebrow(colors.textTertiary)
                if production {
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Button {
                        isFieldFocused = false
                        calendarDraft = (try? IndiaDate.instant(originDate: selectedDate, time: "12:00")) ?? Date()
                        showsCalendar = true
                    } label: {
                        Label(selectedDateLabel, systemImage: "calendar")
                            .font(LocomateFont.caption)
                            .foregroundStyle(colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .background(colors.elevated, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .accessibilityLabel("Choose origin date")
                    .accessibilityValue(selectedDate)
                    .accessibilityIdentifier("search.originDate.calendar")
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.units(2)) {
                    ForEach(quickDates, id: \.self) { date in
                        dateChip(date)
                    }
                }
                .padding(.horizontal, 2)
            }
            Text("The origin date is the day the train starts in India — overnight runs may reach your station the next day.")
                .font(LocomateFont.caption)
                .foregroundStyle(colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dateHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    private var selectedDateLabel: String {
        guard let date = try? IndiaDate.instant(originDate: selectedDate, time: "12:00") else { return selectedDate }
        let formatter = DateFormatter()
        formatter.calendar = IndiaDate.calendar
        formatter.timeZone = IndiaDate.timeZone
        formatter.locale = Locale(identifier: "en_IN")
        formatter.dateFormat = "dd MMM yyyy"
        return formatter.string(from: date)
    }

    private var originDateCalendar: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Choose the day the train starts in India.")
                        .font(LocomateFont.body)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    DatePicker("Origin date", selection: $calendarDraft,
                               in: (try! IndiaDate.instant(originDate: "0001-01-01", time: "12:00"))...(try! IndiaDate.instant(originDate: "9999-12-31", time: "12:00")),
                               displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .environment(\.calendar, IndiaDate.calendar)
                        .environment(\.timeZone, IndiaDate.timeZone)
                        .accessibilityIdentifier("search.originDate.picker")
                    Button {
                        let date = IndiaDate.today(calendarDraft)
                        guard IndiaDate.isValid(date) else { return }
                        selectedDate = date
                        showsCalendar = false
                    } label: {
                        Text("Use date")
                            .font(LocomateFont.bodyStrong)
                            .foregroundStyle(colors.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("search.originDate.confirm")
                    Button { showsCalendar = false } label: {
                        Text("Cancel")
                            .font(LocomateFont.bodyStrong)
                            .foregroundStyle(colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                }
                .padding(20)
            }
            .accessibilityIdentifier("search.originDate.scroll")
            .background(colors.canvas)
            .navigationTitle("Origin date")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(colors.accentBase)
        .preferredColorScheme(colors.dark ? .dark : .light)
        .presentationDetents([.large])
    }

    private func dateChip(_ date: String) -> some View {
        let selected = date == selectedDate
        return ScaleButton(accessibilityLabel: quickLabel(date), haptic: false, action: {
            Haptics.select()
            withAnimation(Motion.animation(Motion.snappy, reduceMotion: reduceMotion)) {
                selectedDate = date
            }
        }) {
            VStack(spacing: 2) {
                Text(quickLabel(date))
                    .font(LocomateFont.micro)
                    .monospacedDigit()
                    .textCase(.uppercase)
                Text(dayLabel(date))
                    .font(LocomateFont.bodyStrong)
                    .monospacedDigit()
            }
            .fixedSize()
            .foregroundStyle(selected ? colors.onAccent : colors.textPrimary)
            .padding(.horizontal, Spacing.units(3.5))
            .padding(.vertical, Spacing.units(2.5))
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(selected ? colors.accentBase : colors.elevated)
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(selected ? Color.clear : colors.borderSubtle, lineWidth: 0.75))
        }
        .accessibilityValue(date)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func quickLabel(_ date: String) -> String {
        let today = IndiaDate.today()
        if date == today { return "Today" }
        if let tomorrow = try? IndiaDate.addDays(today, 1), date == tomorrow { return "Tmrw" }
        if let yesterday = try? IndiaDate.addDays(today, -1), date == yesterday { return "Yest" }
        return weekday(date)
    }

    private func weekday(_ date: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = IndiaDate.timeZone
        parser.dateFormat = "yyyy-MM-dd"
        guard let value = parser.date(from: date) else { return date }
        let display = DateFormatter()
        display.calendar = IndiaDate.calendar
        display.timeZone = IndiaDate.timeZone
        display.locale = Locale(identifier: "en_IN")
        display.dateFormat = "EEE"
        return display.string(from: value)
    }

    private func dayLabel(_ date: String) -> String {
        String(date.suffix(2))
    }

    private var snapshotNotice: some View {
        let pair = colors.pair(for: .delayed)
        return HStack(alignment: .top, spacing: Spacing.units(2.5)) {
            Image(systemName: "info.circle").foregroundStyle(pair.fg)
            Text("Search uses a historical Indian Railways snapshot. Results are real records, not current schedules.")
                .font(LocomateFont.caption)
                .foregroundStyle(pair.fg)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Spacing.units(3))
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(pair.bg))
    }

    @ViewBuilder private var resultList: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(currentResults.enumerated()), id: \.element.id) { index, train in
                StaggerIn(index: index) {
                    SearchResultRow(train: train, showSeparator: index < currentResults.count - 1) {
                        Haptics.tap()
                        try? services.recentTrains.record(train)
                        onSelect(train, selectedDate)
                    }
                }
            }
        }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 12) {
            dateHeaderLayout {
                Text("Recent trains").eyebrow(colors.textTertiary)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                if !services.recentTrains.trains.isEmpty {
                    Button {
                        do { try services.recentTrains.clear(); recentNotice = nil }
                        catch { recentNotice = "Couldn't clear recent trains. Try again." }
                    } label: {
                        Text("Clear").font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                            .padding(.horizontal, 12).frame(minHeight: 44)
                    }
                    .accessibilityLabel("Clear recent trains")
                }
            }
            if let recentNotice {
                Text(recentNotice).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            }
            if services.recentTrains.trains.isEmpty {
                Text("Trains you choose will appear here.")
                    .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(services.recentTrains.trains.enumerated()), id: \.element.id) { index, train in
                        SearchResultRow(train: train, showSeparator: index < services.recentTrains.trains.count - 1) {
                            Haptics.tap()
                            try? services.recentTrains.record(train)
                            onSelect(train, selectedDate)
                        }
                        .accessibilityIdentifier("search.recent.\(train.number)")
                    }
                }
            }
        }
    }

    // MARK: Search execution

    private func runSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let requestQuery = normalizedQuery
        resultQuery = requestQuery
        results = []
        guard normalizedQuery.count >= 2 else {
            results = []
            error = nil
            loading = false
            return
        }
        guard let service = services.railService else {
            // Preview: match against bundled route packs.
            loading = false
            error = nil
            let matches = RoutePackStore.packs
                .filter { $0.trainNumber.contains(requestQuery) || $0.name.localizedCaseInsensitiveContains(requestQuery) }
                .map { pack in
                    TrainSearchResult(
                        number: pack.trainNumber, name: pack.name,
                        originCode: pack.originCode, originName: pack.originName,
                        destinationCode: pack.destinationCode, destinationName: pack.destinationName,
                        departure: String(pack.departure.prefix(5)), arrival: String(pack.arrival.prefix(5)),
                        durationHours: Double(pack.durationMinutes) / 60, distanceKm: pack.distanceKm,
                        sourceLabel: "Historical route pack", sourceUpdatedAt: "", live: false
                    )
                }
            results = matches
            return
        }

        loading = true
        error = nil
        searchTask = Task {
            if !immediate { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            do {
                let found = try await service.searchTrains(requestQuery)
                guard !Task.isCancelled, normalizedQuery == requestQuery else { return }
                await MainActor.run {
                    results = found
                    loading = false
                }
            } catch {
                guard !Task.isCancelled, normalizedQuery == requestQuery else { return }
                await MainActor.run {
                    self.error = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    @ScaledMetric(relativeTo: .body) private var numberSize: CGFloat = 14
    @ScaledMetric(relativeTo: .footnote) private var detailSize: CGFloat = 12.5
    let train: TrainSearchResult
    let showSeparator: Bool
    let onTap: () -> Void

    var body: some View {
        ScaleButton(accessibilityLabel: "\(train.number) \(train.name)", action: onTap) {
            metadataLayout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(train.number)
                        .font(.system(size: numberSize, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("search.result.number.\(train.number)")
                    Text(train.name)
                        .font(.system(size: detailSize))
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("search.result.name.\(train.number)")
                    metadataLayout {
                        Text("\(train.originCode) → \(train.destinationCode)")
                            .font(.system(size: detailSize, design: .monospaced))
                            .foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("search.result.route.\(train.number)")
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Spacing.units(2)) }
                        if train.distanceKm > 0 {
                            Text("\(Int(train.distanceKm)) km")
                                .font(.system(size: detailSize, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("search.result.distance.\(train.number)")
                        }
                    }
                }
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 12) }
                Text(train.sourceLabel.isEmpty ? "Railway catalogue" : train.sourceLabel)
                    .font(.system(size: detailSize, weight: .semibold))
                    .foregroundStyle(colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 124, alignment: .leading)
                    .accessibilityIdentifier("search.result.source.\(train.number)")
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                if showSeparator { colors.borderSubtle.opacity(0.42).frame(height: 1) }
            }
        }
        .accessibilityIdentifier("search.result.\(train.number)")
        .accessibilityValue("\(train.originName) to \(train.destinationName). \(train.sourceLabel)")
    }

    private var metadataLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.units(2)))
            : AnyLayout(HStackLayout(spacing: Spacing.units(2)))
    }
}

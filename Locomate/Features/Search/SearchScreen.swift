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
    var sharedSelectedDate: Binding<String>? = nil

    @State private var query = ""
    @State private var results: [TrainSearchResult] = []
    @State private var selectedStation: StationSearchResult?
    @State private var resultStationCode: String?
    @State private var stations: [StationSearchResult] = []
    @State private var stationResultQuery = ""
    @State private var stationError: String?
    @State private var stationLoading = false
    @State private var stationTruncated = false
    @State private var stationTask: Task<Void, Never>?
    @State private var resultQuery = ""
    @State private var loading = false
    @State private var error: String?
    @State private var localSelectedDate = IndiaDate.today()
    @State private var calendarDraft = Date()
    @State private var showsCalendar = false
    @State private var recentNotice: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool
    @ScaledMetric(relativeTo: .body) private var fieldSize: CGFloat = 16
    @ScaledMetric(relativeTo: .footnote) private var subtitleSize: CGFloat = 13.5

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var selectedDate: String {
        get { sharedSelectedDate?.wrappedValue ?? localSelectedDate }
        nonmutating set {
            if let sharedSelectedDate { sharedSelectedDate.wrappedValue = newValue }
            else { localSelectedDate = newValue }
        }
    }
    private var production: Bool { services.mode.isProduction }
    private var currentResults: [TrainSearchResult] { resultQuery == normalizedQuery && resultStationCode == selectedStation?.code ? results : [] }
    private var currentError: String? { resultQuery == normalizedQuery && resultStationCode == selectedStation?.code ? error : nil }

    private var currentStations: [StationSearchResult] {
        selectedStation == nil && stationResultQuery == normalizedQuery ? stations : []
    }
    private var currentStationError: String? {
        selectedStation == nil && stationResultQuery == normalizedQuery ? stationError : nil
    }

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
                    if let station = selectedStation {
                        Text("Trains at \(station.name)").font(LocomateFont.headline).foregroundStyle(colors.textPrimary)
                        Text(production ? "Scheduled services. Choose the train’s origin date to open a run." : "Services in the historical route pack.")
                            .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let error = currentError {
                        EmptyState(icon: "wifi.exclamationmark",
                                   title: "Couldn't reach the railway feed",
                                   body: error,
                                   actionTitle: "Try again",
                                   onAction: { runSearch(immediate: true) })
                    }
                    if !loading && !stationLoading && currentError == nil && currentStationError == nil && normalizedQuery.count >= 2 && currentResults.isEmpty && currentStations.isEmpty {
                        EmptyState(icon: "magnifyingglass",
                                   title: "No trains found",
                                   body: "Try a train number, train name or station name/code.")
                    }
                    resultList
                    if stationTruncated && resultStationCode == selectedStation?.code {
                        Text("Showing the first 1,000 scheduled services.").font(LocomateFont.caption)
                    }
                    stationChoices
                    BetweenStationsSection { train, originDate in
                        selectedDate = originDate
                        onSelect(train, originDate)
                    }
                }
                .padding(Spacing.units(5))
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: [normalizedQuery, selectedStation?.code ?? ""]) { _, _ in
            runSearch(immediate: selectedStation != nil)
        }
        .onDisappear { searchTask?.cancel(); stationTask?.cancel() }
        .sheet(isPresented: $showsCalendar) { originDateCalendar }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Search")
                .pageHeading()
                .foregroundStyle(colors.textPrimary)
            Text("Find trains and stations")
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
            TextField("", text: Binding(get: { query }, set: { query = $0; selectedStation = nil }),
                      prompt: Text(dynamicTypeSize.isAccessibilitySize ? "Train or station" : "Train no. or station")
                        .foregroundColor(colors.textSecondary))
                .focused($isFieldFocused)
                .font(.system(size: fieldSize, weight: .medium))
                .foregroundStyle(colors.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search trains")
                .onSubmit { isFieldFocused = false }
            if loading || stationLoading {
                ProgressView().controlSize(.small).tint(colors.accentBase)
            }
            if !query.isEmpty {
                Button { query = ""; selectedStation = nil } label: {
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

    @ViewBuilder private var stationChoices: some View {
        if selectedStation == nil && (normalizedQuery.isEmpty || !currentStations.isEmpty || currentStationError != nil) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Stations").eyebrow(colors.textTertiary)
                let choices = normalizedQuery.isEmpty ? StationSearch.shortcuts : currentStations
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 145), alignment: .leading)],
                          alignment: .leading, spacing: 8) {
                    ForEach(choices) { station in
                        Button {
                            isFieldFocused = false
                            selectedStation = station
                            query = station.code
                        } label: {
                            (Text(station.code).monospaced().foregroundStyle(colors.accentBase) + Text(" " + station.name))
                                .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .padding(.vertical, 4)
                                .background(colors.elevated, in: RoundedRectangle(cornerRadius: 20))
                                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(colors.borderSubtle))
                        }
                        .accessibilityLabel("Find trains at \(station.name), \(station.code)")
                        .accessibilityIdentifier("search.station.\(station.code)")
                    }
                }
                if let error = currentStationError {
                    Text("Station search unavailable. " + error).font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                    Button("Retry station search") { runStationSearch(immediate: true) }
                        .frame(minHeight: 44)
                }
            }
        }
    }

    private func runStationSearch(immediate: Bool = false) {
        stationTask?.cancel()
        stations = []; stationError = nil; stationLoading = false
        let requestQuery = normalizedQuery
        stationResultQuery = requestQuery
        guard selectedStation == nil, requestQuery.count >= 2,
              requestQuery.rangeOfCharacter(from: .letters) != nil else { return }
        guard let service = services.railService else {
            stations = StationSearch.previewStations.filter {
                $0.code.localizedCaseInsensitiveContains(requestQuery) || $0.name.localizedCaseInsensitiveContains(requestQuery)
            }
            return
        }
        stationLoading = true
        stationTask = Task {
            if !immediate { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            do {
                let found = try await service.searchStations(requestQuery)
                guard !Task.isCancelled, selectedStation == nil, normalizedQuery == requestQuery else { return }
                stations = found; stationLoading = false
            } catch {
                guard !Task.isCancelled, selectedStation == nil, normalizedQuery == requestQuery else { return }
                stationError = error.localizedDescription; stationLoading = false
            }
        }
    }

    // MARK: Search execution

    private func runSearch(immediate: Bool = false) {
        searchTask?.cancel()
        runStationSearch(immediate: immediate)
        let requestQuery = normalizedQuery
        let requestedStation = selectedStation
        resultQuery = requestQuery
        resultStationCode = requestedStation?.code
        results = []; stationTruncated = false
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
            let matches = RoutePackStore.packs.filter { pack in
                if let station = requestedStation { return pack.calls.contains { $0.code == station.code } }
                return pack.trainNumber.contains(requestQuery) || pack.name.localizedCaseInsensitiveContains(requestQuery)
            }.map(StationSearch.previewTrain)
            results = matches
            return
        }

        loading = true
        error = nil
        searchTask = Task {
            if !immediate { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            do {
                let found: [TrainSearchResult]
                let truncated: Bool
                if let station = requestedStation {
                    let board = try await service.stationTrains(station.code)
                    found = board.trains; truncated = board.truncated
                } else { found = try await service.searchTrains(requestQuery); truncated = false }
                guard !Task.isCancelled, normalizedQuery == requestQuery, selectedStation?.code == requestedStation?.code else { return }
                await MainActor.run {
                    results = found
                    stationTruncated = truncated
                    loading = false
                }
            } catch {
                guard !Task.isCancelled, normalizedQuery == requestQuery, selectedStation?.code == requestedStation?.code else { return }
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

private enum BetweenStationSide: String, Identifiable {
    case from, to
    var id: String { rawValue }
    var title: String { self == .from ? "Board at" : "Leave at" }
}

private struct BetweenStationsSection: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.locomoteServices) private var services
    let onSelect: (TrainSearchResult, String) -> Void
    @State private var from: StationSearchResult?
    @State private var to: StationSearchResult?
    @State private var pickerSide: BetweenStationSide?
    @State private var travelDate = IndiaDate.today()
    @State private var draftDate = Date()
    @State private var showsDatePicker = false
    @State private var trains: [TrainSearchResult] = []
    @State private var truncated = false
    @State private var loading = false
    @State private var searched = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Between stations").eyebrow(colors.textTertiary)
            Text("Find trains for a boarding date at your station.")
                .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                stationButton(.from, station: from)
                Image(systemName: "arrow.right").foregroundStyle(colors.textTertiary)
                stationButton(.to, station: to)
            }
            Button {
                draftDate = (try? IndiaDate.instant(originDate: travelDate, time: "12:00")) ?? Date()
                showsDatePicker = true
            } label: {
                Label("Boarding date: \(travelDate)", systemImage: "calendar")
                    .font(LocomateFont.caption).foregroundStyle(colors.textPrimary)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("search.between.date")
            Button { search() } label: {
                HStack {
                    if loading { ProgressView().tint(colors.onAccent) }
                    Text("Find trains between stations")
                }
                .font(LocomateFont.bodyStrong).foregroundStyle(colors.onAccent)
                .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .disabled(from == nil || to == nil || from?.code == to?.code || loading)
            .accessibilityIdentifier("search.between.submit")
            if from?.code == to?.code && from != nil {
                Text("Choose different boarding and destination stations.")
                    .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            }
            if let error {
                Text("Route search unavailable. \(error)").font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                Button("Retry route search") { search() }.frame(minHeight: 44)
            } else if searched && !loading && trains.isEmpty {
                Text(services.mode.isProduction ? "No scheduled trains found for these stations and boarding date."
                    : "No historical route matches these stations.")
                    .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
            }
            if !trains.isEmpty {
                Text(services.mode.isProduction ? "Scheduled route timetable. Choose a train to open its dated run."
                    : "Historical route pack. Choose a train to open its preview.")
                    .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(trains.enumerated()), id: \.element.id) { index, train in
                        VStack(alignment: .leading, spacing: 2) {
                            SearchResultRow(train: train, showSeparator: false) {
                                guard let originDate = train.originDate else { return }
                                Haptics.tap()
                                try? services.recentTrains.record(train)
                                onSelect(train, originDate)
                            }
                            Text("\(train.departure) → \(train.arrival) · train origin \(train.originDate ?? "unknown")")
                                .font(LocomateFont.caption).foregroundStyle(colors.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, index < trains.count - 1 ? 8 : 0)
                        }
                    }
                }
                if truncated { Text("Showing the first 1,000 scheduled trains.").font(LocomateFont.caption) }
            }
        }
        .sheet(item: $pickerSide) { side in
            BetweenStationPicker(title: side.title) { station in
                if side == .from { from = station } else { to = station }
                resetResults()
                pickerSide = nil
            }
        }
        .sheet(isPresented: $showsDatePicker) { datePicker }
        .onDisappear { task?.cancel() }
    }

    private func stationButton(_ side: BetweenStationSide, station: StationSearchResult?) -> some View {
        Button { pickerSide = side } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(side.title.uppercased()).eyebrow(colors.textTertiary)
                Text(station.map { "\($0.code) · \($0.name)" } ?? "Choose station")
                    .font(LocomateFont.caption).foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(10)
            .background(colors.elevated, in: RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityIdentifier("search.between.\(side.rawValue)")
    }

    private var datePicker: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Choose the day you board at the first station.")
                    .font(LocomateFont.body).foregroundStyle(colors.textSecondary)
                DatePicker("Boarding date", selection: $draftDate,
                           in: (try! IndiaDate.instant(originDate: "0001-01-01", time: "12:00"))...(try! IndiaDate.instant(originDate: "9999-12-31", time: "12:00")),
                           displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .environment(\.calendar, IndiaDate.calendar).environment(\.timeZone, IndiaDate.timeZone)
                Button("Use boarding date") {
                    travelDate = IndiaDate.today(draftDate)
                    resetResults()
                    showsDatePicker = false
                }.frame(minHeight: 48)
                Button("Cancel") { showsDatePicker = false }.frame(minHeight: 48)
            }
            .padding(20)
            .navigationTitle("Boarding date")
        }
    }

    private func resetResults() {
        task?.cancel(); trains = []; error = nil; loading = false; searched = false; truncated = false
    }

    private func search() {
        guard let from, let to, from.code != to.code else { return }
        resetResults()
        let date = travelDate
        loading = true; searched = true
        task = Task {
            do {
                let result: BetweenStationsResult
                if let service = services.railService {
                    result = try await service.trainsBetween(from: from.code, to: to.code, travelDate: date)
                } else {
                    result = previewBetween(from: from, to: to, date: date)
                }
                guard !Task.isCancelled, self.from?.code == from.code, self.to?.code == to.code,
                      travelDate == date else { return }
                trains = result.trains; truncated = result.truncated; loading = false
            } catch {
                guard !Task.isCancelled, self.from?.code == from.code, self.to?.code == to.code,
                      travelDate == date else { return }
                self.error = error.localizedDescription; loading = false
            }
        }
    }

    private func previewBetween(from: StationSearchResult, to: StationSearchResult, date: String) -> BetweenStationsResult {
        let results: [TrainSearchResult] = RoutePackStore.packs.compactMap { pack in
            guard let start = pack.calls.firstIndex(where: { $0.code == from.code }),
                  let end = pack.calls.firstIndex(where: { $0.code == to.code }), start < end,
                  let originDate = try? IndiaDate.addDays(date, 1 - pack.calls[start].day) else { return nil }
            let boarding = pack.calls[start], arrival = pack.calls[end]
            var train = TrainSearchResult(number: pack.trainNumber, name: pack.name,
                originCode: from.code, originName: from.name, destinationCode: to.code, destinationName: to.name,
                departure: boarding.departure ?? "—", arrival: arrival.arrival ?? "—",
                durationHours: 0, distanceKm: 0, sourceLabel: "Historical route pack",
                sourceUpdatedAt: nil, live: false)
            train.originDate = originDate; train.boardingDay = boarding.day; train.arrivalDay = arrival.day
            return train
        }
        return BetweenStationsResult(from: from, to: to, trains: results, truncated: false)
    }
}

private struct BetweenStationPicker: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.locomoteServices) private var services
    let title: String
    let onSelect: (StationSearchResult) -> Void
    @State private var query = ""
    @State private var stations: [StationSearchResult] = []
    @State private var resultQuery = ""
    @State private var error: String?
    @State private var loading = false
    @State private var task: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("", text: $query,
                              prompt: Text("Station name or code").foregroundColor(colors.textSecondary))
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .font(LocomateFont.body)
                        .padding(14)
                        .background(colors.elevated, in: RoundedRectangle(cornerRadius: 16))
                        .accessibilityIdentifier("search.between.stationQuery")
                    if loading { ProgressView() }
                    if let error {
                        Text("Station lookup unavailable. \(error)").font(LocomateFont.caption)
                        Button("Retry station lookup") { search(immediate: true) }.frame(minHeight: 44)
                    }
                    ForEach(query.trimmingCharacters(in: .whitespaces).isEmpty ? StationSearch.shortcuts :
                        (resultQuery == query.trimmingCharacters(in: .whitespaces) ? stations : [])) { station in
                        Button { onSelect(station) } label: {
                            HStack {
                                Text(station.code).monospaced().foregroundStyle(colors.accentBase)
                                Text(station.name).foregroundStyle(colors.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .font(LocomateFont.body).frame(minHeight: 48)
                        }
                        .accessibilityIdentifier("search.between.station.\(station.code)")
                    }
                }
                .padding(20)
            }
            .navigationTitle(title)
        }
        .onChange(of: query) { _, _ in search() }
        .onDisappear { task?.cancel() }
    }

    private func search(immediate: Bool = false) {
        task?.cancel(); stations = []; error = nil; loading = false
        let term = query.trimmingCharacters(in: .whitespaces)
        resultQuery = term
        guard term.count >= 2 else { return }
        if let service = services.railService {
            loading = true
            task = Task {
                if !immediate { try? await Task.sleep(nanoseconds: 350_000_000) }
                guard !Task.isCancelled else { return }
                do {
                    let found = try await service.searchStations(term)
                    guard !Task.isCancelled, query.trimmingCharacters(in: .whitespaces) == term else { return }
                    stations = found; loading = false
                } catch {
                    guard !Task.isCancelled, query.trimmingCharacters(in: .whitespaces) == term else { return }
                    self.error = error.localizedDescription; loading = false
                }
            }
        } else {
            stations = StationSearch.previewStations.filter {
                $0.code.localizedCaseInsensitiveContains(term) || $0.name.localizedCaseInsensitiveContains(term)
            }
        }
    }
}

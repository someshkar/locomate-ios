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
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.locomoteServices) private var services
    @Environment(Preferences.self) private var preferences
    var onSelect: (TrainSearchResult, String) -> Void = { _, _ in }

    @State private var query = ""
    @State private var results: [TrainSearchResult] = []
    @State private var loading = false
    @State private var error: String?
    @State private var selectedDate = IndiaDate.today()
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFieldFocused: Bool

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var production: Bool { services.mode.isProduction }

    private var quickDates: [String] {
        let today = IndiaDate.today()
        return (-1...5).compactMap { try? IndiaDate.addDays(today, $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.units(4)) {
                intro
                searchField
                dateStrip
                if !production { snapshotNotice }
                if let error {
                    EmptyState(icon: "wifi.exclamationmark",
                               title: "Couldn't reach the railway feed",
                               body: error,
                               actionTitle: "Try again",
                               onAction: { runSearch(immediate: true) })
                }
                if !loading && error == nil && normalizedQuery.count >= 2 && results.isEmpty {
                    EmptyState(icon: "magnifyingglass",
                               title: "No trains found",
                               body: "Try a five-digit train number, a different station, or part of the train's name.")
                }
                resultList
            }
            .padding(Spacing.units(4.5))
            .padding(.bottom, 140)
        }
        .background(colors.canvas.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: query) { _, _ in runSearch() }
        .onDisappear { searchTask?.cancel() }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2)) {
            HStack(spacing: 8) {
                Image(systemName: "tram.fill").foregroundStyle(colors.accentBase)
                Text("SMART RAIL · INDIA").eyebrow(colors.textSecondary)
            }
            Text("Every journey\nstarts here.")
                .font(LocomateFont.display)
                .tracking(-1.4)
                .foregroundStyle(colors.textPrimary)
            Text("Find your train. Make the journey yours.")
                .font(LocomateFont.body)
                .foregroundStyle(colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.units(2.5)) {
            Image(systemName: "magnifyingglass").foregroundStyle(colors.textTertiary)
            TextField("Try 12137 or Punjab Mail", text: $query)
                .focused($isFieldFocused)
                .font(LocomateFont.body)
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
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.units(3.5))
        .padding(.vertical, Spacing.units(3.5))
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
    }

    private var dateStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.units(2)) {
            Text("Origin date").eyebrow(colors.textTertiary)
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
        }
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
            Spacer(minLength: 0)
        }
        .padding(Spacing.units(3))
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(pair.bg))
    }

    @ViewBuilder private var resultList: some View {
        ForEach(Array(results.enumerated()), id: \.element.id) { index, train in
            StaggerIn(index: index) {
                SearchResultRow(train: train) {
                    Haptics.tap()
                    onSelect(train, selectedDate)
                }
            }
        }
    }

    // MARK: Search execution

    private func runSearch(immediate: Bool = false) {
        searchTask?.cancel()
        guard normalizedQuery.count >= 2 else {
            results = []
            error = nil
            loading = false
            return
        }
        guard let service = services.railService else {
            // Preview: match against bundled route packs.
            let matches = RoutePackStore.packs
                .filter { $0.trainNumber.contains(normalizedQuery) || $0.name.localizedCaseInsensitiveContains(normalizedQuery) }
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
            if !matches.isEmpty { isFieldFocused = false }
            return
        }

        loading = true
        error = nil
        searchTask = Task {
            if !immediate { try? await Task.sleep(nanoseconds: 350_000_000) }
            guard !Task.isCancelled else { return }
            do {
                let found = try await service.searchTrains(normalizedQuery)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    results = found
                    loading = false
                    if !found.isEmpty { isFieldFocused = false }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.error = error.localizedDescription
                    loading = false
                }
            }
        }
    }
}

private struct SearchResultRow: View {
    @Environment(\.locomoteColors) private var colors
    let train: TrainSearchResult
    let onTap: () -> Void

    var body: some View {
        ScaleButton(accessibilityLabel: "\(train.number) \(train.name)", action: onTap) {
            VStack(alignment: .leading, spacing: Spacing.units(2.5)) {
                HStack {
                    Text(train.number)
                        .font(LocomateFont.timeLarge)
                        .monospacedDigit()
                        .foregroundStyle(colors.textPrimary)
                    Spacer(minLength: Spacing.units(2))
                    Text(train.live ? "LIVE" : train.sourceLabel.uppercased())
                        .eyebrow(train.live ? colors.pair(for: .onTime).fg : colors.textTertiary)
                }
                Text(train.name)
                    .font(LocomateFont.bodyStrong)
                    .foregroundStyle(colors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Spacing.units(2)) {
                    Text("\(train.originCode) → \(train.destinationCode)")
                        .font(LocomateFont.data)
                        .foregroundStyle(colors.textSecondary)
                    Spacer(minLength: Spacing.units(2))
                    if train.distanceKm > 0 {
                        Text("\(Int(train.distanceKm)) km")
                            .font(LocomateFont.data)
                            .monospacedDigit()
                            .foregroundStyle(colors.textTertiary)
                    }
                }
            }
            .padding(Spacing.units(4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(colors.elevated))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
        }
    }
}

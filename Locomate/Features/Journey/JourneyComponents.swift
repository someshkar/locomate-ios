//
//  JourneyComponents.swift
//  Locomate
//
//  Journey sheet components ported from SmartRail:
//  JourneySections, PersonalizedTripCard, JourneyTimeline, NextStopStat,
//  JourneyActions, DataBanner, RotationIntelligenceCard.
//

import SwiftUI

// MARK: - JourneySections (Trip / Stops / Insights)

struct JourneySections: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var namespace

    let selected: JourneyPanel
    let onChange: (JourneyPanel) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(JourneyPanel.allCases) { panel in
                let isActive = panel == selected
                ScaleButton(accessibilityLabel: panel.label, haptic: false, action: {
                    guard panel != selected else { return }
                    Haptics.select()
                    withAnimation(Motion.animation(Motion.selection, reduceMotion: reduceMotion)) {
                        onChange(panel)
                    }
                }) {
                    Text(panel.label)
                        .font(LocomateFont.bodyStrong)
                        .foregroundStyle(isActive ? colors.textPrimary : colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background {
                            if isActive {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(colors.raised)
                                    .matchedGeometryEffect(id: "journey-section", in: namespace)
                            }
                        }
                }
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(colors.dark ? colors.raised.opacity(0.5) : Palette.paper200))
    }
}

// MARK: - PersonalizedTripCard

struct PersonalizedTripCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors

    let journey: Journey
    let plan: JourneyPlan
    let mode: StatusKind
    let preview: Bool
    var cached = false
    var expanded = false
    let onEdit: () -> Void

    private var segment: [StationStop] { JourneyPlanLogic.stops(journey: journey, plan: plan) }
    private var boardingClock: JourneySummaryClock? {
        segment.first.map { JourneyStopProjection.summaryClock(stop: $0, departure: true,
            preview: preview, cached: cached,
            originDeparture: plan.boarding.index == 0 ? journey.departureTime : nil) }
    }
    private var alightingClock: JourneySummaryClock? {
        segment.last.map { JourneyStopProjection.summaryClock(stop: $0, departure: false,
            preview: preview, cached: cached, stale: journey.provenance?.freshness == "stale") }
    }
    private var arrivalDaySuffix: String {
        guard alightingClock?.evidence == .scheduled,
              let start = RailNaturalLanguage.scheduledBoarding(journey: journey, plan: plan),
              let end = RailNaturalLanguage.scheduledAlighting(journey: journey, plan: plan) else { return "" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = IndiaDate.timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                           to: calendar.startOfDay(for: end)).day ?? 0
        return days > 0 ? " +\(days)" : ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))) {
                Text("\(journey.trainNumber) · \(journey.trainName)")
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(preview ? "PREVIEW · NOT LIVE" : StatusMapping.journeyModeLabel(mode, cached: cached))
                    .font(LocomateFont.micro)
                    .foregroundStyle(colors.pair(for: cached ? .stale : mode).fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                  VStack(alignment: .leading, spacing: 4) {
                    if let countdown = RailNaturalLanguage.departureCountdown(
                        journey: journey, plan: plan, preview: preview, now: context.date
                    ) {
                        JourneyCountdownText(value: countdown)
                            .accessibilityIdentifier("journey.departureCountdown")
                        Text("\(cached ? "Saved timetable · " : "")Scheduled boarding at \(plan.boarding.code)")
                            .font(LocomateFont.caption)
                            .foregroundStyle(colors.textSecondary)
                    } else if let countdown = RailNaturalLanguage.arrivalCountdown(
                        journey: journey, plan: plan, preview: preview, now: context.date
                    ) {
                        JourneyCountdownText(value: countdown)
                            .accessibilityIdentifier("journey.arrivalCountdown")
                        Text("\(cached ? "Saved timetable · " : "")Scheduled arrival at \(plan.alighting.code)")
                            .font(LocomateFont.caption)
                            .foregroundStyle(colors.textSecondary)
                    } else {
                        Text(preview ? "Timetable sample" : journeyEndedTitle)
                            .font(.system(.title2, weight: .bold))
                            .foregroundStyle(colors.textPrimary)
                    }
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentTransition(.numericText(countsDown: true))
                  .animation(Motion.fadeNormal, value: context.date)
                }
                if plan.coach != nil || plan.seat != nil {
                    Text([plan.coach.map { "Coach \($0)" }, plan.seat.map { "Seat \($0)" }].compactMap { $0 }.joined(separator: " · "))
                        .font(LocomateFont.bodyStrong).foregroundStyle(colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("journey.privateSeat")
                }
                Text("\(plan.boarding.name) to \(plan.alighting.name)")
                    .font(LocomateFont.bodyStrong)
                    .foregroundStyle(colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().overlay(colors.borderSubtle)
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 14))) {
                stationClock(code: plan.boarding.code, clock: boardingClock, name: plan.boarding.name, role: "boarding")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                stationClock(code: plan.alighting.code, clock: alightingClock, name: plan.alighting.name, role: "alighting",
                             daySuffix: arrivalDaySuffix)
            }
            if expanded {
                (dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout())) {
                    Text("\(segment.count) stops · \(Int(totalDistance).formatted()) kilometres on your segment")
                        .accessibilityIdentifier("journey.segmentDistance")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    ScaleButton(accessibilityLabel: "Edit your journey", action: onEdit) {
                        Label("Edit", systemImage: "ticket").font(LocomateFont.bodyStrong)
                            .foregroundStyle(colors.accentBase)
                    }
                }
            }
        }
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(colors.canvas.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(colors.borderSubtle, lineWidth: 0.75))
        .accessibilityElement(children: .contain)
    }

    private func stationClock(code: String, clock: JourneySummaryClock?, name: String, role: String, daySuffix: String = "") -> some View {
        VStack(alignment: .leading, spacing: 5) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))) {
                Text(code).font(LocomateFont.data.weight(.semibold))
                    .foregroundStyle(colors.textSecondary)
                Text("\(clock?.time ?? "—")\(daySuffix)")
                    .font(.system(.body, weight: .bold)).monospacedDigit()
                    .foregroundStyle(clock?.evidence == .estimated ? colors.pair(for: .delayed).fg
                        : clock?.evidence == .recorded ? colors.pair(for: .onTime).fg : colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(clock?.label ?? "Timing unavailable")
                .font(LocomateFont.micro)
                .foregroundStyle(colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(clock?.label ?? "Timing unavailable"), \(clock?.time ?? "unavailable")\(daySuffix)")
        .accessibilityIdentifier("journey.\(role)Clock")
    }

    /// Past the scheduled arrival with no recorded call, say what is known
    /// rather than a generic title.
    private var journeyEndedTitle: String {
        guard let arrival = RailNaturalLanguage.scheduledAlighting(journey: journey, plan: plan),
              arrival <= Date() else { return "\(plan.boarding.code) to \(plan.alighting.code)" }
        return segment.last?.actualArrival != nil ? "Arrived at \(plan.alighting.code)" : "Scheduled to have arrived"
    }

    private var totalDistance: Double {
        guard let first = segment.first, let last = segment.last else { return journey.distanceKm }
        return max(1, last.distanceKm - first.distanceKm)
    }
}

private struct JourneyCountdownText: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    @ScaledMetric(relativeTo: .title2) private var numberSize: CGFloat = 27
    @ScaledMetric(relativeTo: .caption) private var unitSize: CGFloat = 15

    let value: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Text(value).font(.system(.title2, weight: .bold))
            } else {
                Text(styledValue)
            }
        }
        .monospacedDigit()
        .foregroundStyle(colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var styledValue: AttributedString {
        var text = AttributedString(value)
        text.font = .system(size: unitSize, weight: .semibold)
        text.foregroundColor = colors.textSecondary
        for range in value.ranges(of: /[0-9]+/) {
            if let lower = AttributedString.Index(range.lowerBound, within: text),
               let upper = AttributedString.Index(range.upperBound, within: text) {
                text[lower..<upper].font = .system(size: numberSize, weight: .heavy)
                text[lower..<upper].foregroundColor = colors.textPrimary
            }
        }
        return text
    }
}

// MARK: - NextStopStat

struct NextStopStat: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors

    let journey: Journey
    let originDate: String
    let plan: JourneyPlan?
    let cached: Bool
    let preview: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let stop = JourneyStopProjection.make(journey: journey, plan: plan, originDate: originDate,
                                                       cached: cached, preview: preview, now: context.date) {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.units(2)) {
                        Text(stop.heading).eyebrow(colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                        (dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.units(2)))
                            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.units(3)))) {
                            Text("\(stop.code) · \(stop.name)")
                                .font(LocomateFont.title)
                                .tracking(-1.2)
                                .foregroundStyle(colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("journey.nextStop.station")
                            if let platform = stop.platform {
                                PlatformBadge(platform: platform, label: stop.platformLabel, station: stop.name)
                                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
                                           alignment: .trailing)
                                    .accessibilityIdentifier("journey.nextStop.platform")
                            }
                        }
                        (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.units(4)))) {
                            Stat(label: stop.timeLabel, value: stop.time ?? "Unavailable")
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("journey.nextStop.time")
                            if let distance = stop.distanceKm {
                                Stat(label: "Reported distance", value: String(format: "%.0f", distance), unit: "km")
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Delay at this stop").eyebrow(colors.textTertiary)
                                Text(stop.delayLabel)
                                    .font(LocomateFont.bodyStrong.monospacedDigit())
                                    .foregroundStyle(colors.pair(for: stop.delayKind).fg)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text(stop.detail).font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// A known platform belongs to this station call, with a separate readable box.
struct PlatformBadge: View {
    @Environment(\.locomoteColors) private var colors
    let platform: String
    let label: String
    let station: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(label).font(LocomateFont.caption)
            Text(platform).font(LocomateFont.title.monospacedDigit())
        }
        .foregroundStyle(colors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(Spacing.units(2))
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(colors.raised))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(colors.borderStrong, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(platform) for \(station)")
    }
}

/// Delay readout. Long labels ("DELAY UNAVAILABLE") shrink rather than wrap.
struct DelayStat: View {
    @Environment(\.locomoteColors) private var colors
    let journey: Journey

    private var label: String {
        StatusMapping.delayStatusLabel(
            delayMinutes: journey.prediction.delayMinutes,
            delayStatus: journey.prediction.delayStatus,
            predictionSource: journey.prediction.source
        )
    }

    private var kind: StatusKind {
        StatusMapping.statusForDelay(
            delayMinutes: journey.prediction.delayMinutes,
            delayStatus: journey.prediction.delayStatus
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Delay").eyebrow(colors.textTertiary)
            Text(label)
                .font(LocomateFont.timeLarge)
                .monospacedDigit()
                .foregroundStyle(colors.pair(for: kind).fg)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Delay: \(label)")
    }
}

// MARK: - JourneyTimeline

struct JourneyTimeline: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let journey: Journey
    let plan: JourneyPlan?
    var cached = false
    var preview = false

    private var stops: [StationStop] {
        guard let plan, let resolved = JourneyPlanLogic.resolve(journey: journey, plan: plan) else {
            return journey.stops
        }
        return JourneyPlanLogic.stops(journey: journey, plan: resolved)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                HStack(alignment: .top, spacing: Spacing.units(3)) {
                    // Spine
                    VStack(spacing: 0) {
                        Circle()
                            .fill(nodeColor(stop))
                            .frame(width: stop.state == .current ? 12 : 9,
                                   height: stop.state == .current ? 12 : 9)
                            .overlay(Circle().strokeBorder(colors.canvas, lineWidth: 2))
                        if index < stops.count - 1 {
                            Rectangle()
                                .fill(colors.borderSubtle)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 14)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        (dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                            : AnyLayout(HStackLayout(spacing: Spacing.units(2)))) {
                            Text(stop.name)
                                .font(LocomateFont.bodyStrong)
                                .foregroundStyle(stop.state == .upcoming ? colors.textSecondary : colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("journeyTimeline.\(stop.code).name")
                            Text(RailTime.format(stop.scheduledArrival))
                                .font(LocomateFont.data)
                                .monospacedDigit()
                                .foregroundStyle(colors.textTertiary)
                                .fixedSize()
                                .accessibilityLabel("Scheduled time, \(RailTime.format(stop.scheduledArrival))")
                                .accessibilityIdentifier("journeyTimeline.\(stop.code).arrival")
                        }
                        (dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 3))
                            : AnyLayout(HStackLayout(spacing: Spacing.units(2)))) {
                            Text(stop.code).eyebrow(colors.textTertiary)
                            let kind = StatusMapping.statusForDelay(
                                delayMinutes: stop.delayMinutes, delayStatus: stop.delayStatus
                            )
                            if stop.delayMinutes != nil {
                                Text(StatusMapping.delayStatusLabel(delayMinutes: stop.delayMinutes, delayStatus: stop.delayStatus))
                                    .font(LocomateFont.micro)
                                    .monospacedDigit()
                                    .foregroundStyle(colors.pair(for: kind).fg)
                            }
                            if !preview, let platform = stop.knownPlatform {
                                PlatformBadge(platform: platform,
                                              label: cached || stop.delayStatus == .stale ? "Last known platform" : "Platform",
                                              station: stop.name)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                    .padding(.bottom, Spacing.units(3.5))
                }
            }
        }
        .padding(Spacing.units(4))
        .background(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(colors.elevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
            .strokeBorder(colors.borderSubtle, lineWidth: 0.75))
    }

    private func nodeColor(_ stop: StationStop) -> Color {
        switch stop.state {
        case .passed: return colors.borderStrong
        case .current: return colors.accentBase
        case .upcoming: return colors.borderSubtle
        }
    }
}

// MARK: - JourneyActions

struct JourneyActions: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let liveCardEnabled: Bool
    let liveCardPending: Bool
    let calendarPending: Bool
    let journeySaved: Bool
    let onCalendar: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onToggleLiveCard: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Grid(horizontalSpacing: 10, verticalSpacing: 16) {
                    GridRow { liveCardAction; calendarAction }
                    GridRow { saveAction; shareAction }
                }
            } else {
                HStack(spacing: Spacing.units(2.5)) { actions }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        liveCardAction
        calendarAction
        saveAction
        shareAction
    }

    private var liveCardAction: some View {
        action("Live card", systemImage: liveCardEnabled ? "rectangle.inset.filled" : "rectangle",
               active: liveCardEnabled, pending: liveCardPending, action: onToggleLiveCard)
    }

    private var calendarAction: some View {
        action("Calendar", systemImage: "calendar", active: false, pending: calendarPending, action: onCalendar)
    }

    private var saveAction: some View {
        action("Save", systemImage: journeySaved ? "bookmark.fill" : "bookmark",
               active: journeySaved, pending: false, action: onSave)
    }

    private var shareAction: some View {
        action("Share", systemImage: "square.and.arrow.up", active: false, pending: false, action: onShare)
    }

    private func action(_ title: String, systemImage: String, active: Bool, pending: Bool, action: @escaping () -> Void) -> some View {
        ScaleButton(accessibilityLabel: title, action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(active ? colors.accentWash : colors.raised)
                    if pending {
                        ProgressView().scaleEffect(0.7).tint(colors.accentBase)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(active ? colors.accentBase : colors.textSecondary)
                    }
                }
                .frame(width: 52, height: 52)
                Text(title)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - DataBanner

struct DataBanner: View {
    @Environment(\.locomoteColors) private var colors
    let model: DataBannerModel

    var body: some View {
        let pair = colors.pair(for: model.status)
        HStack(alignment: .top, spacing: Spacing.units(2.5)) {
            RoundedRectangle(cornerRadius: 2)
                .fill(pair.fg)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.title)
                    .font(LocomateFont.micro)
                    .monospacedDigit()
                    .tracking(0.8)
                    .foregroundStyle(pair.fg)
                Text(model.body)
                    .font(LocomateFont.caption)
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.units(3))
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(pair.bg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title). \(model.body)")
    }
}

// MARK: - RotationIntelligenceCard

struct RotationIntelligenceCard: View {
    @Environment(\.locomoteColors) private var colors

    let operations: OperationalChainResponse?
    let trainNumber: String
    let enabled: Bool
    var onFocus: ((OperationalRun) -> Void)? = nil

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(3)) {
                Text("Rotation intelligence").eyebrow(colors.textTertiary)
                if let operations {
                    ViewThatFits(in: .horizontal) {
                      HStack(spacing: Spacing.units(3)) {
                        ForEach(["previous", "current", "next"], id: \.self) { role in
                            roleColumn(role, operations: operations)
                        }
                      }
                      VStack(alignment: .leading, spacing: 16) {
                        ForEach(["previous", "current", "next"], id: \.self) { roleColumn($0, operations: operations) }
                      }
                    }
                    if let linkage = operations.linkage {
                        Text(linkageLabel(linkage))
                            .font(LocomateFont.caption)
                            .foregroundStyle(colors.textSecondary)
                    }
                    if let assessment = operations.delayAssessment {
                        Text(assessment.summary).font(LocomateFont.bodyStrong).foregroundStyle(colors.textPrimary)
                        Text("Incoming delay \(assessment.incomingDelayMinutes.formatted()) min · \(assessment.confidence.rawValue) confidence")
                            .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                        ForEach(assessment.evidence) { evidence in
                            Text("\(evidence.summary) · \(evidence.source.rawValue)\(evidence.observedAt.map { " · " + $0 } ?? "")")
                                .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                        }
                    }
                    if let delay = operations.propagatedDelay {
                        Text("Propagation: \(delay.minutes.formatted()) min · \(delay.explanation)")
                            .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    }
                    if let risk = operations.turnaroundRisk {
                        Text("Turnaround risk: \(risk.level) · \(risk.summary)").font(LocomateFont.bodyStrong).foregroundStyle(colors.textPrimary)
                        Text("Available \(risk.availableMinutes.formatted()) / minimum \(risk.minimumMinutes.formatted()) min")
                            .font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    }
                    if let linkage = operations.linkage {
                        ForEach(linkage.caveats, id: \.self) { Text($0).font(LocomateFont.caption).foregroundStyle(colors.textSecondary) }
                    }
                    Text("Updated \(operations.updatedAt) · \(operations.mode)").font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                    Text(operations.disclaimer)
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textTertiary)
                } else {
                    Text(enabled
                         ? "Rotation evidence is not available for this run yet."
                         : "Rotation intelligence requires a production journey.")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
        }
    }

    private func roleColumn(_ role: String, operations: OperationalChainResponse) -> some View {
        let run = role == "previous" ? operations.previous
            : (role == "current" ? operations.current : operations.next)
        return VStack(alignment: .leading, spacing: 4) {
            Text(role).eyebrow(colors.textTertiary)
            Text(run?.trainNumber ?? "—")
                .font(LocomateFont.timeLarge)
                .monospacedDigit()
                .foregroundStyle(run == nil ? colors.textTertiary : colors.textPrimary)
            if let run, run.geometry.coordinates.count >= 2 {
                Button(role == "previous" ? "Focus inbound" : role == "next" ? "Focus outbound" : "Focus current") { onFocus?(run) }
                    .buttonStyle(AccessibleTextButtonStyle())
                    .accessibilityIdentifier("operations.focus.\(role)")
                Text("Geometry: \(run.geometry.source)").font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                if let position = run.position {
                    Text("Position: \(position.source.rawValue) · \(position.observedAt)").font(LocomateFont.caption).foregroundStyle(colors.textSecondary)
                }
            }
            Text("\(run?.originCode ?? "—") → \(run?.destinationCode ?? "—")")
                .font(LocomateFont.data)
                .foregroundStyle(colors.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linkageLabel(_ linkage: LinkageClaim) -> String {
        switch linkage.claim {
        case "same-rake": return "Same train-set confirmed"
        case "possible-same-rake": return "Possible same train-set · \(linkage.confidence.rawValue) confidence"
        default: return "Not linked"
        }
    }
}

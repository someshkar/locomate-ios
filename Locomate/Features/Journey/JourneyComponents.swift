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
    let onEdit: () -> Void

    private var segment: [StationStop] { JourneyPlanLogic.stops(journey: journey, plan: plan) }
    private var boardingTime: String {
        RailTime.format(segment.first?.scheduledDeparture ?? segment.first?.scheduledArrival ?? journey.departureTime)
    }
    private var alightingTime: String {
        let stop = segment.last
        return RailTime.format(preview ? stop?.scheduledArrival : stop?.forecast.flatMap { forecast in
            if case .available(let available) = forecast { return available.p50 }
            return nil
        } ?? stop?.predictedArrival ?? journey.prediction.expectedTime ?? journey.scheduledArrival)
    }

    /// Line height of the station-code text, used to align the centre column's
    /// arrow with the code row so the distance lands on the name row.
    private var codeLineHeight: CGFloat {
        UIFont.monospacedSystemFont(ofSize: 26, weight: .regular).lineHeight
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(4)) {
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))) {
                    Text("\(journey.trainNumber) · \(journey.trainName)")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Text(preview ? "PREVIEW · NOT LIVE" : StatusMapping.journeyModeLabel(mode, cached: cached))
                        .font(LocomateFont.micro)
                        .foregroundStyle(colors.pair(for: cached ? .stale : mode).fg)
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.8)
                }
                VStack(alignment: .leading, spacing: 5) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if let countdown = RailNaturalLanguage.departureCountdown(
                            journey: journey, plan: plan, preview: preview, now: context.date
                        ) {
                            Text(countdown)
                                .font(.system(.title2, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("journey.departureCountdown")
                            Text("\(cached ? "Saved timetable · " : "")Scheduled boarding at \(plan.boarding.code)")
                                .font(LocomateFont.caption)
                                .foregroundStyle(colors.textSecondary)
                        } else {
                            Text(preview ? "Timetable sample" : "Your railway journey")
                                .font(.system(.title2, weight: .semibold))
                                .foregroundStyle(colors.textPrimary)
                        }
                    }
                    Text("\(plan.boarding.name) to \(plan.alighting.name)")
                        .font(LocomateFont.bodyStrong)
                        .foregroundStyle(colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // Two flexible outer columns of EQUAL width keep the centre
                // column optically centred on the card. Using `Spacer`s here
                // instead would centre the leftover *gap*, which drifts by half
                // the difference between the two station-name widths.
                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.units(3)))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.boarding.code)
                            .font(LocomateFont.bodyStrong.monospacedDigit())
                            .monospacedDigit()
                            .foregroundStyle(colors.textPrimary)
                        Text(boardingTime)
                            .font(LocomateFont.caption)
                            .foregroundStyle(preview ? colors.textSecondary : colors.pair(for: mode).fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(colors.accentBase)
                            .frame(height: codeLineHeight)
                        Text("\(Int(totalDistance)) km")
                            .font(LocomateFont.caption.monospacedDigit())
                            .foregroundStyle(colors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .fixedSize()
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(plan.alighting.code)
                            .font(LocomateFont.bodyStrong.monospacedDigit())
                            .monospacedDigit()
                            .foregroundStyle(colors.textPrimary)
                        Text(alightingTime)
                            .font(LocomateFont.caption)
                            .foregroundStyle(preview ? colors.textSecondary : colors.pair(for: mode).fg)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(plan.boarding.name), \(boardingTime), to \(plan.alighting.name), \(alightingTime). \(Int(totalDistance)) kilometres"
                )

                Divider().overlay(colors.borderSubtle)

                (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())) {
                    Text("\(segment.count) stops on your segment")
                        .font(LocomateFont.caption)
                        .foregroundStyle(colors.textTertiary)
                    Spacer()
                    ScaleButton(accessibilityLabel: "Edit your journey", action: onEdit) {
                        HStack(spacing: 6) {
                            Image(systemName: "ticket")
                            Text("Edit").font(LocomateFont.bodyStrong)
                        }
                        .foregroundStyle(colors.accentBase)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var totalDistance: Double {
        guard let first = segment.first, let last = segment.last else { return journey.distanceKm }
        return max(1, last.distanceKm - first.distanceKm)
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

    let liveCardEnabled: Bool
    let liveCardPending: Bool
    let calendarPending: Bool
    let journeySaved: Bool
    let onCalendar: () -> Void
    let onSave: () -> Void
    let onShare: () -> Void
    let onToggleLiveCard: () -> Void

    var body: some View {
        HStack(spacing: Spacing.units(2.5)) {
            action("Live card", systemImage: liveCardEnabled ? "rectangle.inset.filled" : "rectangle",
                   active: liveCardEnabled, pending: liveCardPending, action: onToggleLiveCard)
            action("Calendar", systemImage: "calendar", active: false, pending: calendarPending, action: onCalendar)
            action("Save", systemImage: journeySaved ? "bookmark.fill" : "bookmark",
                   active: journeySaved, pending: false, action: onSave)
            action("Share", systemImage: "square.and.arrow.up", active: false, pending: false, action: onShare)
        }
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

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.units(3)) {
                Text("Rotation intelligence").eyebrow(colors.textTertiary)
                if let operations {
                    HStack(spacing: Spacing.units(3)) {
                        ForEach(["previous", "current", "next"], id: \.self) { role in
                            roleColumn(role, operations: operations)
                        }
                    }
                    if let linkage = operations.linkage {
                        Text(linkageLabel(linkage))
                            .font(LocomateFont.caption)
                            .foregroundStyle(colors.textSecondary)
                    }
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

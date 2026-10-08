//
//  LocomateWidgets.swift
//  LocomateWidgets
//
//  Live Activity + Dynamic Island for the active journey — the native
//  equivalent of SmartRail's `expo-widgets` TrainLiveActivity.
//  Shows next station, ETA and delay with provenance, in lock-screen,
//  compact, minimal and expanded presentations.
//
//  `JourneyActivityAttributes` lives in /Shared so the app and the extension
//  use identical types (required by ActivityKit).
//

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Palette (local to the widget target)

private enum WidgetPalette {
    static let ink = Color(red: 0.024, green: 0.027, blue: 0.031)
    static let accent = Color(red: 0.0, green: 0.667, blue: 1.0)
    static let green = Color(red: 0.216, green: 0.788, blue: 0.510)
    static let amber = Color(red: 1.0, green: 0.722, blue: 0.302)
    static let secondary = Color(red: 0.678, green: 0.682, blue: 0.710)
}

private struct DelayBadge: View {
    let label: String
    let minutes: Double?

    private var color: Color {
        guard let minutes else { return WidgetPalette.secondary }
        return minutes > 0 ? WidgetPalette.amber : WidgetPalette.green
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
    }
}

struct LocomateLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            // Lock Screen / banner presentation
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(context.attributes.trainNumber) → \(context.attributes.destinationCode)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WidgetPalette.secondary)
                    Text(context.state.nextStation)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        DelayBadge(label: context.isStale ? "STALE · LAST KNOWN" : context.state.delayLabel,
                                   minutes: context.isStale ? nil : context.state.delayMinutes)
                        Text("\(Int(context.state.distanceToNextKm.rounded())) km")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.eta)
                        .font(.system(size: 30, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(context.isStale ? "Last known arrival" : (context.state.etaLabel ?? "Arrival"))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WidgetPalette.secondary)
                }
            }
            .padding(16)
            .activityBackgroundTint(WidgetPalette.ink)
            .activitySystemActionForegroundColor(WidgetPalette.accent)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WidgetPalette.secondary)
                        Text(context.state.nextStation)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.isStale ? "Last known arrival" : (context.state.etaLabel ?? "Arrival"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(WidgetPalette.secondary)
                        Text(context.state.eta)
                            .font(.system(size: 20, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        DelayBadge(label: context.isStale ? "STALE" : context.state.delayLabel,
                                   minutes: context.isStale ? nil : context.state.delayMinutes)
                        Text("\(Int(context.state.distanceToNextKm.rounded())) km to go")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(WidgetPalette.secondary)
                        Spacer()
                        Text(context.state.confidence)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(WidgetPalette.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "tram.fill").foregroundStyle(WidgetPalette.accent)
            } compactTrailing: {
                Text(context.isStale ? "STALE" : context.state.eta)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "tram.fill").foregroundStyle(WidgetPalette.accent)
            }
            .keylineTint(WidgetPalette.accent)
        }
    }
}

@main
struct LocomateWidgetsBundle: WidgetBundle {
    var body: some Widget {
        LocomateLiveActivity()
    }
}

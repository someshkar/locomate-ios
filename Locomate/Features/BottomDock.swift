//
//  BottomDock.swift
//  Locomate
//
//  Floating frosted tab bar with a sliding active indicator and a separate
//  circular Search control. Ported from SmartRail
//  `src/screens/BottomNavigation.tsx`.
//
//  Micro-interaction: the icon translates up 1pt and scales 1.045 when active,
//  the pill indicator springs between equal-width slots, and each selection
//  fires a selection haptic. Reduce Motion snaps the indicator instantly.
//

import SwiftUI

public enum LocomateTab: String, CaseIterable, Identifiable, Sendable {
    case journey, explore, passport, search
    public var id: String { rawValue }

    var label: String {
        switch self {
        case .journey: return "Journey"
        case .explore: return "Explore"
        case .passport: return "Passport"
        case .search: return "Search"
        }
    }

    var systemImage: String {
        switch self {
        case .journey: return "tram.fill"
        case .explore: return "globe.asia.australia.fill"
        case .passport: return "person.crop.circle"
        case .search: return "magnifyingglass"
        }
    }
}

struct BottomDock: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var scaledDockHeight = 66.0
    private var dockHeight: Double { dynamicTypeSize.isAccessibilitySize ? 74 : scaledDockHeight }

    let active: LocomateTab
    let onChange: (LocomateTab) -> Void

    /// The dock shows three labelled tabs; Search is its own circular control.
    private var items: [LocomateTab] { [.journey, .explore, .passport] }

    var body: some View {
        HStack(spacing: Spacing.units(2.5)) {
            dockBar
            searchButton
        }
    }

    private var dockBar: some View {
        GeometryReader { geometry in
            let count = items.count
            let slot = geometry.size.width / CGFloat(count)
            let pillWidth = min(slot - 8, 104)
            let activeSlot = items.firstIndex(of: active) ?? 0
            let targetX = CGFloat(activeSlot) * slot + (slot - pillWidth) / 2
            let isSearch = active == .search

            ZStack(alignment: .leading) {
                // Sliding indicator
                RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                    .fill(colors.dark ? Color(rgba: 255, 255, 255, 0.14) : Color(rgba: 255, 255, 255, 0.52))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                            .strokeBorder(colors.dark
                                ? Color(rgba: 255, 255, 255, 0.12)
                                : Color(rgba: 255, 255, 255, 0.66), lineWidth: 0.75)
                    )
                    .frame(width: pillWidth, height: dockHeight - 12)
                    .offset(x: targetX)
                    .opacity(isSearch ? 0 : 1)
                    .animation(Motion.animation(Motion.selection, reduceMotion: reduceMotion), value: active)

                HStack(spacing: 0) {
                    ForEach(items) { item in
                        DockItem(
                            tab: item,
                            active: active == item,
                            onSelect: { select(item) }
                        )
                        .frame(width: slot)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: dockHeight)
        .background {
            ZStack {
                GlassSurface(cornerRadius: 34)
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .strokeBorder(colors.dark ? colors.borderStrong : Color(rgba: 255, 255, 255, 0.8), lineWidth: 0.75)
            }
        }
        .shadow(color: .black.opacity(colors.dark ? 0.26 : 0.12), radius: 22, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var searchButton: some View {
        ScaleButton(accessibilityLabel: "Find a train", haptic: false, action: { select(.search) }) {
            ZStack {
                GlassSurface(shape: RoundedRectangle(cornerRadius: 32, style: .continuous))
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(colors.dark ? colors.borderStrong : Color(rgba: 255, 255, 255, 0.8), lineWidth: 0.75)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(active == .search ? colors.accentBase : colors.textPrimary)
            }
            .frame(width: 64, height: 64)
        }
        .shadow(color: .black.opacity(colors.dark ? 0.24 : 0.12), radius: 22, y: 8)
        .accessibilityAddTraits(active == .search ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ tab: LocomateTab) {
        guard tab != active else { return }
        Haptics.select()
        withAnimation(Motion.animation(Motion.fadeNormal, reduceMotion: reduceMotion)) {
            onChange(tab)
        }
    }
}

private struct DockItem: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let tab: LocomateTab
    let active: Bool
    let onSelect: () -> Void

    var body: some View {
        ScaleButton(accessibilityLabel: tab.label, haptic: false, action: onSelect) {
            VStack(spacing: 4) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(active ? (colors.dark ? colors.accentSoft : colors.accentBase) : colors.textPrimary)
                    .offset(y: active && !reduceMotion ? -1 : 0)
                    .scaleEffect(active && !reduceMotion ? 1.045 : 1)
                if !dynamicTypeSize.isAccessibilitySize {
                Text(tab.label)
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(active ? (colors.dark ? colors.accentSoft : colors.accentBase) : colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.animation(Motion.selection, reduceMotion: reduceMotion), value: active)
        }
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Label(tab.label, systemImage: tab.systemImage)
        }
    }
}

#Preview {
    VStack {
        Spacer()
        BottomDock(active: .journey, onChange: { _ in })
            .padding()
    }
    .background(LocomateTheme.dark.canvas)
    .environment(\.locomoteColors, LocomateTheme.dark)
    .preferredColorScheme(.dark)
}

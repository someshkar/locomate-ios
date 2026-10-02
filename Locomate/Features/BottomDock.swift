//
//  BottomDock.swift
//  Locomate
//
//  Floating frosted tab bar with a sliding active indicator and a separate
//  circular Search control. Native vectors follow the approved Doop navigation.
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
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { dockContent }
        } else {
            dockContent
        }
    }

    private var dockContent: some View {
        HStack(spacing: 14) {
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
                    .fill(colors.dark ? Color.white.opacity(0.07) : Color.white.opacity(0.52))
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
        .modifier(DockLens(cornerRadius: 34))
        .shadow(color: .black.opacity(colors.dark ? 0.26 : 0.12), radius: 22, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var searchButton: some View {
        ScaleButton(accessibilityLabel: "Find a train", haptic: false, action: { select(.search) }) {
            ZStack {
                NavigationGlyph(tab: .search, side: 23)
                    .foregroundStyle(colors.textPrimary)
            }
            .frame(width: 60, height: 60)
            .modifier(DockLens(cornerRadius: 30))
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
                NavigationGlyph(tab: tab)
                    .foregroundStyle(active ? colors.textPrimary : colors.navigationSecondary)
                    .offset(y: active && !reduceMotion ? -1 : 0)
                    .scaleEffect(active && !reduceMotion ? 1.045 : 1)
                if !dynamicTypeSize.isAccessibilitySize {
                Text(tab == .journey ? "Journeys" : tab.label)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(active ? colors.textPrimary : colors.navigationSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Motion.animation(Motion.selection, reduceMotion: reduceMotion), value: active)
        }
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
        .accessibilityShowsLargeContentViewer {
            Label { Text(tab.label) } icon: { NavigationGlyph(tab: tab, side: 56) }
        }
    }

}

/// The reference dock is a lightly tinted lens, distinct from the data sheets.
private struct DockLens: ViewModifier {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let tint = LinearGradient(colors: [
            colors.navigationGlass.opacity(colors.dark ? 0.42 : 0.72),
            colors.navigationGlass.opacity(colors.dark ? 0.26 : 0.52)
        ], startPoint: .top, endPoint: .bottom)
        if reduceTransparency {
            content.background(shape.fill(colors.dark ? colors.navigationGlass : colors.elevated))
                .overlay(shape.strokeBorder(colors.borderSubtle, lineWidth: 0.75).allowsHitTesting(false))
        } else if #available(iOS 26.0, *) {
            // Apply to the complete control so its foreground remains above
            // the native lens, rather than becoming part of its backdrop.
            content.glassEffect(.clear, in: shape)
                .background(shape.fill(tint))
        } else {
            content.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(tint)
                    shape.strokeBorder(LinearGradient(colors: [
                        Color.white.opacity(colors.dark ? 0.30 : 0.8),
                        Color.white.opacity(colors.dark ? 0.06 : 0.4)
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                }
            }
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

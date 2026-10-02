//
//  Theme.swift
//  Locomate
//
//  Semantic theme based on SmartRail tokens and the approved Doop canvas.
//  The dark primary blue, glass surface, and sheet radius follow the canvas.
//

import SwiftUI

/// Paired foreground/background for a status family. Must pass WCAG AA.
public struct StatusPair: Sendable, Equatable {
    public let fg: Color
    public let bg: Color
    public init(_ fg: Color, _ bg: Color) { self.fg = fg; self.bg = bg }
}

public struct LocomateColors: Sendable {
    public let dark: Bool

    // Backgrounds
    public let canvas: Color
    public let elevated: Color
    public let raised: Color
    public let glass: Color
    public let overlay: Color
    public let navigationGlass: Color
    public let navigationSecondary: Color

    // Text
    public let textPrimary: Color
    public let textSecondary: Color
    public let textTertiary: Color
    public let onAccent: Color

    // Borders
    public let borderSubtle: Color
    public let borderStrong: Color

    // Accent
    public let accentBase: Color
    public let accentSoft: Color
    public let accentWash: Color
    public let accentLine: Color

    // Status families
    public let statusOnTime: StatusPair
    public let statusDelayed: StatusPair
    public let statusStale: StatusPair
    public let statusError: StatusPair
    public let statusPreview: StatusPair
    public let statusScheduled: StatusPair

    // Map
    public let mapScrimTop: Color
    public let mapScrimBottom: Color
    public let mapRoute: Color
    public let mapRouteGlow: Color

    /// Resolve the pair for a semantic status kind.
    public func pair(for kind: StatusKind) -> StatusPair {
        switch kind {
        case .onTime: return statusOnTime
        case .delayed: return statusDelayed
        case .stale: return statusStale
        case .error: return statusError
        case .preview: return statusPreview
        case .scheduled: return statusScheduled
        }
    }
}

public enum LocomateTheme {
    public static let dark = LocomateColors(
        dark: true,
        canvas: Palette.ink950,
        elevated: Palette.ink850,
        raised: Palette.ink800,
        glass: Color(rgba: 16, 17, 22, 0.92),
        overlay: Color(rgba: 0, 0, 0, 0.60),
        navigationGlass: Palette.dockInk,
        navigationSecondary: Palette.dockText,
        textPrimary: Palette.grey200,
        textSecondary: Palette.grey300,
        textTertiary: Palette.grey400,
        onAccent: Palette.ink900,
        borderSubtle: Color(rgba: 255, 255, 255, 0.12),
        borderStrong: Color(rgba: 255, 255, 255, 0.22),
        accentBase: Palette.accent500,
        accentSoft: Palette.accent200,
        accentWash: Color(rgba: 86, 178, 255, 0.16),
        accentLine: Color(rgba: 86, 178, 255, 0.32),
        statusOnTime: StatusPair(Palette.green400, Color(rgba: 78, 203, 147, 0.12)),
        statusDelayed: StatusPair(Palette.amber400, Color(rgba: 255, 184, 77, 0.12)),
        statusStale: StatusPair(Color(hex: 0xC7A377), Color(rgba: 199, 163, 119, 0.11)),
        statusError: StatusPair(Palette.red400, Color(rgba: 255, 106, 97, 0.12)),
        statusPreview: StatusPair(Palette.violet400, Color(rgba: 156, 139, 255, 0.12)),
        statusScheduled: StatusPair(Palette.grey400, Color(rgba: 152, 160, 172, 0.11)),
        mapScrimTop: Color(rgba: 6, 8, 12, 0.22),
        mapScrimBottom: Color(rgba: 6, 8, 12, 0.16),
        mapRoute: Palette.route400,
        mapRouteGlow: Color(rgba: 95, 174, 245, 0.4)
    )

    public static let light = LocomateColors(
        dark: false,
        canvas: Palette.paper100,
        elevated: Palette.white,
        raised: Palette.paper50,
        glass: Color(rgba: 248, 248, 250, 0.94),
        overlay: Color(rgba: 10, 12, 18, 0.42),
        navigationGlass: Palette.white,
        navigationSecondary: Palette.grey600,
        textPrimary: Palette.ink900,
        textSecondary: Palette.grey600,
        textTertiary: Palette.grey600,
        onAccent: Palette.white,
        borderSubtle: Color(rgba: 17, 19, 26, 0.09),
        borderStrong: Color(rgba: 17, 19, 26, 0.16),
        accentBase: Palette.accent700,
        accentSoft: Palette.accent700,
        accentWash: Color(rgba: 30, 130, 230, 0.12),
        accentLine: Color(rgba: 30, 130, 230, 0.26),
        statusOnTime: StatusPair(Palette.green700, Color(rgba: 30, 158, 106, 0.12)),
        statusDelayed: StatusPair(Palette.amber700, Color(rgba: 217, 142, 27, 0.12)),
        statusStale: StatusPair(Color(hex: 0x6F502A), Color(rgba: 143, 107, 61, 0.12)),
        statusError: StatusPair(Palette.red700, Color(rgba: 217, 67, 59, 0.10)),
        statusPreview: StatusPair(Palette.violet700, Color(rgba: 122, 104, 224, 0.12)),
        statusScheduled: StatusPair(Palette.grey600, Color(rgba: 86, 93, 105, 0.10)),
        mapScrimTop: Color(rgba: 245, 246, 248, 0.66),
        mapScrimBottom: Color(rgba: 245, 246, 248, 0.14),
        mapRoute: Palette.route500,
        mapRouteGlow: Color(rgba: 62, 150, 232, 0.35)
    )

    public static func colors(dark isDark: Bool) -> LocomateColors { isDark ? Self.dark : light }
}

// MARK: - Radii & spacing

public enum Radius {
    public static let sm: CGFloat = 9
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 22
    public static let xl: CGFloat = 30
    public static let pill: CGFloat = 999
    public static let sheet: CGFloat = 28
}

public enum Spacing {
    /// 4pt grid. `Spacing.units(3)` == 12.
    public static func units(_ value: CGFloat) -> CGFloat { value * 4 }
}

// MARK: - Environment

private struct LocomateColorsKey: EnvironmentKey {
    static let defaultValue = LocomateTheme.dark
}

public extension EnvironmentValues {
    var locomoteColors: LocomateColors {
        get { self[LocomateColorsKey.self] }
        set { self[LocomateColorsKey.self] = newValue }
    }
}

/// Convenience accessor mirroring `useTheme()`.
public struct LocomateThemeReader<Content: View>: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.colorScheme) private var scheme
    private let content: (LocomateColors) -> Content
    public init(@ViewBuilder content: @escaping (LocomateColors) -> Content) {
        self.content = content
    }
    public var body: some View { content(colors) }
}

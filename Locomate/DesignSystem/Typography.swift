//
//  Typography.swift
//  Locomate
//
//  Native iOS typography, ported from SmartRail `src/theme/typography.ts`.
//  On iOS the source used the system font (SF Pro). Times and data use SF Mono
//  with TABULAR numerals so ticking values never shift layout — that rule is
//  preserved and is enforced by `monospacedDigit()`.
//

import SwiftUI

public enum LocomateFont {
    // Semantic styles follow the user's preferred size, including accessibility sizes.
    public static let displayXL = Font.system(.largeTitle, weight: .regular)
    public static let display = Font.system(.largeTitle, weight: .regular)
    public static let title = Font.system(.title, weight: .semibold)
    public static let headline = Font.system(.title3, weight: .semibold)
    public static let subhead = Font.system(.body, weight: .regular)
    public static let body = Font.system(.body, weight: .regular)
    public static let bodyStrong = Font.system(.body, weight: .semibold)
    public static let caption = Font.system(.footnote, weight: .regular)

    // Numeric voice — SF Mono, tabular digits, also scaled by Dynamic Type.
    public static let timeHero = Font.system(.largeTitle, design: .monospaced, weight: .medium)
    public static let timeLarge = Font.system(.title2, design: .monospaced, weight: .regular)
    public static let data = Font.system(.caption, design: .monospaced, weight: .regular)
    public static let micro = Font.system(.caption, design: .monospaced, weight: .semibold)
}

/// Text styles pairing a font with the tracking from `typography.ts`.
public enum LocomateText {
    public static func displayXL(_ text: String) -> Text {
        Text(text).font(LocomateFont.displayXL).tracking(-2)
    }
    public static func display(_ text: String) -> Text {
        Text(text).font(LocomateFont.display).tracking(-1.4)
    }
    public static func title(_ text: String) -> Text {
        Text(text).font(LocomateFont.title).tracking(-1.2)
    }
    public static func headline(_ text: String) -> Text {
        Text(text).font(LocomateFont.headline).tracking(-0.4)
    }
    public static func body(_ text: String) -> Text {
        Text(text).font(LocomateFont.body)
    }
    public static func caption(_ text: String) -> Text {
        Text(text).font(LocomateFont.caption)
    }
    /// Uppercase mono eyebrow. Callers apply `.textCase(.uppercase)`.
    public static func micro(_ text: String) -> Text {
        Text(text).font(LocomateFont.micro).tracking(0.8)
    }
    /// Hero time — tabular so it never jitters as it ticks.
    public static func timeHero(_ text: String) -> Text {
        Text(text).font(LocomateFont.timeHero).monospacedDigit().tracking(-1)
    }
    public static func timeLarge(_ text: String) -> Text {
        Text(text).font(LocomateFont.timeLarge).monospacedDigit().tracking(-0.8)
    }
}

// MARK: - Reusable modifiers

/// The uppercase mono eyebrow used across the app.
public struct EyebrowModifier: ViewModifier {
    let color: Color
    public func body(content: Content) -> some View {
        content
            .font(LocomateFont.micro)
            .monospacedDigit()
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

public extension View {
    func eyebrow(_ color: Color) -> some View {
        modifier(EyebrowModifier(color: color))
    }
}

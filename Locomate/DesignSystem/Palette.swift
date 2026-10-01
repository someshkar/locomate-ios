//
//  Palette.swift
//  Locomate
//
//  Raw palette — ported 1:1 from SmartRail `src/theme/tokens.ts`.
//  Rules preserved from the source of truth:
//  - Raw hex values live ONLY here. Everything else is semantic (`LocomateColors`).
//  - Components consume `LocomateTheme.colors`; they never hardcode colors.
//  - Status colors are paired (fg on bg) and must pass WCAG AA in both themes.
//

import SwiftUI

public enum Palette {
    // MARK: Ink — matte near-blacks, dark-first canvas
    public static let ink950 = Color(hex: 0x060708)
    public static let ink900 = Color(hex: 0x0C0D10)
    public static let ink850 = Color(hex: 0x17171D)
    public static let ink800 = Color(hex: 0x202025)
    public static let ink700 = Color(hex: 0x22262F)
    public static let ink600 = Color(hex: 0x2C313C)
    public static let ink500 = Color(hex: 0x3E4553)

    // MARK: Paper — warm-neutral light surfaces
    public static let paper50 = Color(hex: 0xF5F6F8)
    public static let paper100 = Color(hex: 0xECEDF1)
    public static let paper200 = Color(hex: 0xDFE1E7)
    public static let paper300 = Color(hex: 0xC9CCD4)

    // MARK: Text greys
    public static let grey200 = Color(hex: 0xF5F5F7)
    public static let grey300 = Color(hex: 0xADAEB5)
    public static let grey400 = Color(hex: 0x98A0AC)
    public static let grey500 = Color(hex: 0x767D89)
    public static let grey600 = Color(hex: 0x565D68)

    // MARK: Accent — a single confident system blue
    public static let accent200 = Color(hex: 0xBFE0FF)
    public static let accent300 = Color(hex: 0x8FCBFF)
    public static let accent400 = Color(hex: 0x00AAFF)
    public static let accent500 = Color(hex: 0x009DFA)
    public static let accent600 = Color(hex: 0x1E82E6)
    public static let accent700 = Color(hex: 0x1666BF)

    // MARK: Cool ink for the map route (distinct from the UI accent)
    public static let route300 = Color(hex: 0x8FC7FF)
    public static let route400 = Color(hex: 0x5FAEF5)
    public static let route500 = Color(hex: 0x3E96E8)

    // MARK: Warm gold — tiny highlight chips only
    public static let gold300 = Color(hex: 0xE8C48C)
    public static let gold400 = Color(hex: 0xDDAE6C)

    // MARK: Status hues — muted, matte, quiet
    public static let green300 = Color(hex: 0x7FD8AE)
    public static let green400 = Color(hex: 0x37C982)
    public static let green600 = Color(hex: 0x28A068)
    public static let green700 = Color(hex: 0x087744)
    public static let amber300 = Color(hex: 0xFFC670)
    public static let amber400 = Color(hex: 0xFFB84D)
    public static let amber600 = Color(hex: 0xD9931F)
    public static let amber700 = Color(hex: 0x8D5700)
    public static let red300 = Color(hex: 0xFF8A82)
    public static let red400 = Color(hex: 0xFF6A61)
    public static let red600 = Color(hex: 0xDA4A41)
    public static let red700 = Color(hex: 0xB52E28)
    public static let violet300 = Color(hex: 0xB4A6FF)
    public static let violet400 = Color(hex: 0x9C8BFF)
    public static let violet600 = Color(hex: 0x7C69E2)
    public static let violet700 = Color(hex: 0x5C47BF)

    public static let white = Color.white
    public static let black = Color.black
}

public extension Color {
    /// Build a Color from a 0xRRGGBB literal.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    /// `rgba(r,g,b,a)` literal from the TS source, e.g. `Color.rgba(24,30,40,0.9)`.
    init(rgba r: Double, _ g: Double, _ b: Double, _ a: Double) {
        self.init(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }
}

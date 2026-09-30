import SwiftUI

// Central motion + color tokens (mirrored one-for-one on Android).
enum LM {
    // Colors (from the approved Doop iOS design)
    static let accent   = Color(hex: 0x3E8EF7)   // single blue
    static let accentHi = Color(hex: 0x7FB8FF)   // route line top
    static let success  = Color(hex: 0x37C982)
    static let successDim = Color(hex: 0x37C982).opacity(0.18)
    static let warn     = Color(hex: 0xF5C77E)
    static let ink      = Color(hex: 0xF7F7F9)   // primary text
    static let ink2     = Color(hex: 0xB4B9C4)   // secondary
    static let ink3     = Color(hex: 0x8B909B)   // tertiary
    static let hairline = Color.white.opacity(0.08)
    static let sheetEdge = Color.white.opacity(0.10)

    // Springs — one language of motion across the app
    static let springUI    = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let springSnap  = Animation.spring(response: 0.38, dampingFraction: 0.92)
    static let springBouncy = Animation.spring(response: 0.5, dampingFraction: 0.72)
    static let easeOut     = Animation.easeOut(duration: 0.22)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

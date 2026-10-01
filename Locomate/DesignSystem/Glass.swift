//
//  Glass.swift
//  Locomate
//
//  Native glass surface — replaces the RN `GlassBackdrop`. On iOS the system
//  `Material` gives true vibrancy for free, so we use it directly and layer a
//  restrained highlight edge the way the source component did.
//
//  Reduce Transparency → solid readable surface (product rule, ported).
//

import SwiftUI

public struct GlassSurface<S: InsettableShape>: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public let shape: S
    public let heavy: Bool

    public init(shape: S, heavy: Bool = false) {
        self.shape = shape
        self.heavy = heavy
    }

    private var tint: Color {
        colors.dark
            ? Color(rgba: 17, 21, 28, heavy ? 0.34 : 0.16)
            : Color(rgba: 250, 252, 255, heavy ? 0.40 : 0.18)
    }

    private var highlight: Color {
        colors.dark
            ? Color(rgba: 255, 255, 255, 0.14)
            : Color(rgba: 255, 255, 255, 0.70)
    }

    public var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(colors.elevated)
                shape.strokeBorder(colors.borderSubtle, lineWidth: 0.75)
            } else {
                shape.fill(heavy ? Material.thin : Material.ultraThin)
                shape.fill(tint)
                shape.strokeBorder(highlight, lineWidth: 0.75)
            }
        }
    }
}

public extension GlassSurface where S == RoundedRectangle {
    init(cornerRadius: CGFloat, heavy: Bool = false) {
        self.init(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), heavy: heavy)
    }
}

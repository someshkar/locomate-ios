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
            ? Color(rgba: 17, 21, 28, heavy ? 0.94 : 0.90)
            : Color(rgba: 250, 252, 255, heavy ? 0.97 : 0.94)
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

/// Keep the native map and its legal controls above one scrollable data sheet.
/// Accessibility sizes reserve more room for the sheet without covering map credits.
struct OverviewPage<MapContent: View, SheetContent: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    var hidesMap = false
    @ViewBuilder var map: () -> MapContent
    @ViewBuilder var sheet: () -> SheetContent

    var body: some View {
        GeometryReader { geometry in
            let mapHeight: CGFloat = dynamicTypeSize.isAccessibilitySize
                ? 96 : max(128, min(190, geometry.size.height * 0.24))
            VStack(spacing: 0) {
                map()
                    .frame(height: hidesMap ? 0 : mapHeight + geometry.safeAreaInsets.top)
                    .clipped()
                    .padding(.top, hidesMap ? 0 : -geometry.safeAreaInsets.top)
                    .accessibilityHidden(hidesMap)
                sheet()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { OverviewSheetSurface() }
            }
        }
        .background(colors.canvas)
    }
}

private struct OverviewSheetSurface: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let shape = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(colors.elevated)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(LinearGradient(
                    colors: colors.dark
                        ? [Color(hex: 0x0B0C16).opacity(0.55), Color(hex: 0x090A12).opacity(0.98)]
                        : [colors.elevated.opacity(0.75), colors.elevated],
                    startPoint: .top, endPoint: .bottom))
            }
            shape.strokeBorder(colors.borderSubtle, lineWidth: 0.75)
        }
    }
}

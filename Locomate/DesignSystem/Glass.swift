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
            ? Color(rgba: 17, 21, 28, heavy ? 0.98 : 0.96)
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

/// The native map fills the screen beneath one material sheet and the floating dock.
/// Only the exposed strip supplies network bounds and receives map gestures.
struct OverviewPage<MapContent: View, SheetContent: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locomoteColors) private var colors
    var hidesMap = false
    var sheetStyle: OverviewSheetStyle = .standard
    @ViewBuilder var map: (CGRect) -> MapContent
    @ViewBuilder var sheet: () -> SheetContent

    var body: some View {
        GeometryReader { geometry in
            let mapHeight: CGFloat = dynamicTypeSize.isAccessibilitySize
                ? 96 : max(128, min(190, geometry.size.height * 0.24))
            let frame = geometry.frame(in: .global)
            let viewport = CGRect(x: frame.minX, y: frame.minY,
                                  width: frame.width, height: hidesMap ? 0 : mapHeight)
            ZStack(alignment: .top) {
                map(viewport)
                    .ignoresSafeArea()
                    .opacity(hidesMap ? 0 : 1)
                    .accessibilityHidden(hidesMap)
                    .allowsHitTesting(!hidesMap)
                VStack(spacing: 0) {
                    Color.clear.frame(height: hidesMap ? 0 : mapHeight)
                        .allowsHitTesting(false)
                    sheet()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            OverviewSheetSurface(style: sheetStyle)
                                .ignoresSafeArea(.container, edges: .bottom)
                        }
                }
            }
        }
        .background(colors.canvas)
    }
}

enum OverviewSheetStyle {
    case standard, passport

    var darkStops: [Gradient.Stop] {
        switch self {
        case .standard:
            [ .init(color: Color(hex: 0x111119).opacity(0.96), location: 0),
              .init(color: Color(hex: 0x0F0F16).opacity(0.88), location: 0.20),
              .init(color: Color(hex: 0x0E0E15).opacity(0.98), location: 1) ]
        case .passport:
            [ .init(color: Color(hex: 0x0B0C16).opacity(0.96), location: 0),
              .init(color: Color(hex: 0x0A0B14).opacity(0.94), location: 0.20),
              .init(color: Color(hex: 0x090A12).opacity(0.99), location: 1) ]
        }
    }
}

struct OverviewSheetSurface: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var style: OverviewSheetStyle = .standard

    private let shape = UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(colors.elevated)
            } else {
                shape.fill(.ultraThinMaterial)
                shape.fill(LinearGradient(
                    stops: colors.dark ? style.darkStops : [
                        .init(color: colors.elevated.opacity(0.97), location: 0),
                        .init(color: colors.elevated, location: 1)],
                    startPoint: .top, endPoint: .bottom))
            }
            shape.strokeBorder(colors.borderSubtle, lineWidth: 0.75)
        }
    }
}

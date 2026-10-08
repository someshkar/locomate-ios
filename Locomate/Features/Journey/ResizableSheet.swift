//
//  ResizableSheet.swift
//  Locomate
//
//  The signature interaction: a NON-modal, resizable bottom sheet that coexists
//  with the map behind it. Ported behaviour from SmartRail `src/components/ui/Sheet.tsx`:
//
//  - Detents sorted ascending (distance from top; smallest = most open).
//  - Drag with velocity + position projection snapping.
//  - Rubber-band overdrag past the top detent.
//  - Haptic on detent change; interruptible everywhere.
//  - Exposes `visibleHeight` so the map camera can follow the sheet live.
//  - Reduce Motion snaps instantly with no spring.
//
//  Geometry model: the sheet's top edge is at `detents[index]` measured from the
//  top of the parent. Height is therefore `totalHeight - detent`, and the sheet is
//  bottom-aligned. During a drag a continuous detent is tracked so the sheet
//  resizes under the finger; on release the value snaps to the nearest detent.
//
//  Drag is attached to the grabber + header chrome (not the scrollable body) so
//  scrolling content and dragging the sheet never fight each other.
//

import SwiftUI

/// Shared, observable sheet geometry so the map can react to the sheet's drag.
@MainActor
@Observable
public final class SheetPosition {
    /// Current top edge of the sheet, in points from the top of the parent.
    public var topEdge: Double = 0
    /// Height of the visible sheet region.
    public var visibleHeight: Double = 0
    public init() {}
}

public struct ResizableSheet<Handle: View, Content: View>: View {
    @Environment(\.locomoteColors) private var colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Snap points as distance-from-top in points, ascending.
    public let detents: [CGFloat]
    @Binding public var detentIndex: Int
    public let position: SheetPosition
    public let handle: () -> Handle
    public let content: () -> Content

    /// Continuous detent while dragging; `nil` when settled on a snap point.
    @State private var liveDetent: CGFloat?
    @State private var dragStart: CGFloat?

    public init(
        detents: [CGFloat],
        detentIndex: Binding<Int>,
        position: SheetPosition,
        @ViewBuilder handle: @escaping () -> Handle,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.detents = detents.sorted()
        self._detentIndex = detentIndex
        self.position = position
        self.handle = handle
        self.content = content
    }

    private var topDetent: CGFloat { detents.first ?? 0 }
    private var bottomDetent: CGFloat { detents.last ?? 0 }

    private var clampedIndex: Int {
        max(0, min(detents.count - 1, detentIndex))
    }

    /// The detent currently expressed on screen (live during a drag).
    private var effectiveDetent: CGFloat {
        liveDetent ?? detents[clampedIndex]
    }

    /// Diminishing-returns curve for overdrag past the top detent.
    private func rubberBand(_ overdrag: CGFloat) -> CGFloat {
        let limit: CGFloat = 72
        return (1 - 1 / ((overdrag * 0.55) / limit + 1)) * limit
    }

    public var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height
            // Height follows the live detent so the sheet resizes under the drag.
            let sheetHeight = max(120, totalHeight - effectiveDetent)

            VStack(spacing: 0) {
                // Drag surface: grabber + caller-supplied header chrome.
                VStack(spacing: 0) {
                    Capsule()
                        .fill(colors.borderStrong)
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                        .frame(maxWidth: .infinity)
                    handle()
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(totalHeight: totalHeight))

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // Size the SHEET itself to `sheetHeight` and pin it to the bottom by
            // placing it in a bottom-aligned container. Do NOT use a second
            // `.frame(maxHeight: .infinity)` around the styled view: that expands
            // the view to the whole container, so `.background` would then paint
            // ink across the entire screen above the sheet.
            .frame(height: sheetHeight, alignment: .top)
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 28, bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0, topTrailingRadius: 28,
                    style: .continuous
                )
            )
            // The surface continues under the floating dock and home indicator;
            // only the content is clipped to the sheet's own frame.
            .background(alignment: .top) {
                OverviewSheetSurface()
                    .padding(.bottom, -geometry.safeAreaInsets.bottom)
            }
            .shadow(color: .black.opacity(colors.dark ? 0.5 : 0.18), radius: 32, y: -12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .onAppear { updatePosition(totalHeight) }
            .onChange(of: detentIndex) { _, _ in updatePosition(totalHeight) }
            .onChange(of: effectiveDetent) { _, _ in updatePosition(totalHeight) }
        }
    }

    private func dragGesture(totalHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                // Capture the detent this drag started from.
                let start = dragStart ?? detents[clampedIndex]
                if dragStart == nil { dragStart = start }

                // Downward drag increases the detent (sheet gets shorter).
                let raw = start + value.translation.height
                // Rubber-band only past the most-open detent.
                liveDetent = raw < topDetent ? topDetent - rubberBand(topDetent - raw) : raw
            }
            .onEnded { value in
                let start = dragStart ?? detents[clampedIndex]
                // Velocity projection: continue the gesture's momentum.
                let projected = start + value.predictedEndTranslation.height
                let target = nearestDetentIndex(to: projected)
                let changed = target != clampedIndex
                dragStart = nil
                liveDetent = nil
                if changed { Haptics.snap() }
                withAnimation(Motion.animation(Motion.sheet, reduceMotion: reduceMotion)) {
                    detentIndex = target
                }
                updatePosition(totalHeight)
            }
    }

    private func nearestDetentIndex(to detent: CGFloat) -> Int {
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, candidate) in detents.enumerated() {
            let distance = abs(candidate - detent)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    private func updatePosition(_ totalHeight: CGFloat) {
        let top = effectiveDetent
        position.topEdge = Double(top)
        position.visibleHeight = Double(totalHeight - top)
    }
}

public extension ResizableSheet where Handle == EmptyView {
    init(
        detents: [CGFloat],
        detentIndex: Binding<Int>,
        position: SheetPosition,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(detents: detents, detentIndex: detentIndex, position: position,
                  handle: { EmptyView() }, content: content)
    }
}

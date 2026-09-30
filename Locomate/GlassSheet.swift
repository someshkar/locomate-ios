import SwiftUI

// The hero piece: a floating glass sheet with velocity-aware snap physics,
// rubber-band at the edges, and the whole-map subtle parallax under drag.
struct GlassSheet<Content: View>: View {
    // two detents (fractions of available height)
    let collapsed: CGFloat   // e.g. 0.52
    let expanded: CGFloat    // e.g. 0.86
    @Binding var presented: Bool
    var onCollapse: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0          // from collapsed position
    @GestureState private var drag: CGFloat = 0
    @State private var isExpanded = false

    var body: some View {
        GeometryReader { geo in
            let maxH = geo.size.height * expanded
            let minOffset = -(geo.size.height * (expanded - collapsed))
            let live = presented ? offset + drag : offset + 900

            ZStack(alignment: .top) {
                // the sheet
                content()
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 130)
            }
            .frame(maxWidth: .infinity)
            .frame(height: maxH, alignment: .top)
            .background(
                // real native material — this is Liquid Glass on iOS
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.16).opacity(0.55), Color(white: 0.09).opacity(0.85)],
                                             startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(LM.sheetEdge, lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 30, y: -14)
            )
            .overlay(alignment: .top) {
                Capsule().fill(Color.white.opacity(0.45))
                    .frame(width: 40, height: 5).padding(.top, 9)
            }
            .offset(y: geo.size.height * (1 - collapsed) + live + (geo.safeAreaInsets.bottom))
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($drag) { value, state, _ in
                        var t = value.translation.height
                        // rubber-band beyond limits
                        if presented && (offset + t) < minOffset { t = minOffset - offset + (t > 0 ? (t - (minOffset - offset)) * 0.25 : (t - (minOffset - offset)) * 0.25) }
                        state = t
                    }
                    .onEnded { value in
                        let total = offset + value.translation.height
                        let v = value.predictedEndTranslation.height - value.translation.height
                        let eff = total + v * 0.3   // velocity-aware
                        let snapExpanded = eff < minOffset * 0.5
                        withAnimation(LM.springSnap) {
                            isExpanded = snapExpanded
                            offset = snapExpanded ? minOffset : 0
                        }
                    }
            )
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

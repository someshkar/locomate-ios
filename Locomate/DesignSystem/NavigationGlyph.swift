import SwiftUI

/// Native vectors from the four approved Doop frames (24 × 24 view box).
/// https://doop.design/c/ha6YK6QvsY — navigation SVGs, 2026-09-30.
struct NavigationGlyph: View {
    let tab: LocomateTab
    var side: CGFloat = 21

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 24
            context.translateBy(x: (size.width - 24 * scale) / 2, y: (size.height - 24 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let stroke = StrokeStyle(lineWidth: tab == .search ? 2.2 : 1.9, lineCap: .butt, lineJoin: .miter)
            var outline = Path()
            switch tab {
            case .journey:
                outline.addRoundedRect(in: CGRect(x: 4.5, y: 4, width: 15, height: 13),
                                       cornerSize: CGSize(width: 3.5, height: 3.5), style: .circular)
                outline.move(to: CGPoint(x: 4.5, y: 11))
                outline.addLine(to: CGPoint(x: 19.5, y: 11))
                outline.move(to: CGPoint(x: 8, y: 17))
                outline.addLine(to: CGPoint(x: 6.2, y: 20.5))
                outline.move(to: CGPoint(x: 16, y: 17))
                outline.addLine(to: CGPoint(x: 17.8, y: 20.5))
            case .explore:
                outline.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
                outline.move(to: CGPoint(x: 12, y: 3.5))
                outline.addLine(to: CGPoint(x: 12, y: 20.5))
                outline.move(to: CGPoint(x: 3.5, y: 12))
                outline.addLine(to: CGPoint(x: 20.5, y: 12))
            case .passport:
                outline.addRoundedRect(in: CGRect(x: 4, y: 3.5, width: 16, height: 18),
                                       cornerSize: CGSize(width: 3, height: 3), style: .circular)
                outline.addEllipse(in: CGRect(x: 9.5, y: 8.5, width: 5, height: 5))
                outline.move(to: CGPoint(x: 9, y: 15.5))
                outline.addLine(to: CGPoint(x: 15, y: 15.5))
            case .search:
                outline.addEllipse(in: CGRect(x: 4.5, y: 4.5, width: 13, height: 13))
                outline.move(to: CGPoint(x: 16, y: 16))
                outline.addLine(to: CGPoint(x: 20.5, y: 20.5))
            }
            context.stroke(outline, with: .foreground, style: stroke)
            if tab == .journey {
                // The SVG headlights inherit the same stroke as the train outline.
                var lights = Path()
                for x in [8.5, 15.5] {
                    lights.addEllipse(in: CGRect(x: x - 0.9, y: 13.1, width: 1.8, height: 1.8))
                }
                context.fill(lights, with: .foreground)
                context.stroke(lights, with: .foreground, style: stroke)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}

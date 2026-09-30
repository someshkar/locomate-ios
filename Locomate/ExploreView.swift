import SwiftUI

struct ExploreView: View {
    @State private var presented = true
    var body: some View {
        ZStack(alignment: .bottom) {
            MapCanvas()
            LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.0), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            GlassSheet(collapsed: 0.62, expanded: 0.9, presented: $presented) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Explore").font(.system(size: 34, weight: .heavy)).tracking(-1.2)
                    Text("The network, live").font(.system(size: 15, weight: .medium)).foregroundStyle(LM.ink3).padding(.top, 2)
                    HStack(spacing: 12) {
                        stat("13,452", "LIVE TRAINS"); stat("7,325", "STATIONS"); stat("68,585", "ROUTE KM")
                    }.padding(.top, 20)
                    section("Busiest corridors today")
                    corridor("New Delhi → Mumbai", "WESTERN RAILWAY", "41 trains")
                    corridor("Howrah → New Delhi", "EASTERN RAILWAY", "36 trains")
                    section("Delay hotspots")
                    corridor("Mughal Sarai Jn", "EAST CENTRAL", "avg 38 min", warn: true)
                }
            }
        }
    }
    private func stat(_ n: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(n).font(.system(size: 26, weight: .heavy)).tracking(-0.5)
            Text(l).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(LM.ink3).tracking(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.05)).overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(LM.hairline, lineWidth: 1)))
    }
    private func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(LM.ink3).tracking(0.8).padding(.top, 24).padding(.bottom, 10)
    }
    private func corridor(_ name: String, _ zone: String, _ tag: String, warn: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 16.5, weight: .semibold))
                Text(zone).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(LM.ink3).tracking(0.6)
            }
            Spacer()
            Text(tag).font(.system(size: 13, weight: .semibold)).foregroundStyle(warn ? LM.warn : Color(.white)).padding(.horizontal, 13).padding(.vertical, 8)
                .background(Capsule().fill(warn ? LM.warn.opacity(0.14) : .white.opacity(0.06)))
        }
        .padding(.vertical, 12)
    }
}

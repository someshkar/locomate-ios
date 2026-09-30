import SwiftUI

struct PassportView: View {
    @State private var presented = true
    var body: some View {
        ZStack(alignment: .bottom) {
            MapCanvas()
            LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.0), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            GlassSheet(collapsed: 0.62, expanded: 0.9, presented: $presented) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Passport").font(.system(size: 34, weight: .heavy)).tracking(-1.2)
                        Spacer()
                        Circle().fill(LinearGradient(colors: [LM.success, Color(hex: 0x1FA463)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Text("SK").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x06110A)))
                            .frame(width: 40, height: 40)
                    }
                    Text("Your rail story, so far").font(.system(size: 15, weight: .medium)).foregroundStyle(LM.ink3).padding(.top, 2)

                    HStack(spacing: 8) { chip("All-Time", on: true); chip("2026"); chip("2025") }.padding(.top, 16)

                    // Hero
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("ALL TIME · AS OF TODAY").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xB39BF0)).tracking(1.8)
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("8,412").font(.system(size: 58, weight: .heavy)).tracking(-1.8).foregroundStyle(.white)
                                Text("km").font(.system(size: 20, weight: .medium)).foregroundStyle(Color(hex: 0xCFBBF6))
                            }
                            Text("0.2× the length of India's rail network").font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xA98BE8))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(22)
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                        HStack(spacing: 0) {
                            cell("JOURNEYS", "14", "2 long haul")
                            divider
                            cell("TIME ON RAILS", "2d 6h", "avg 4h / trip")
                            divider
                            cell("STATIONS", "9", "5 zones")
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [Color(hex: 0x1A1240), Color(hex: 0x0B0A20)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                        .shadow(color: Color(hex: 0x12062E).opacity(0.5), radius: 24, y: 10))
                    .padding(.top, 16)

                    // This year row
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("THIS YEAR · 2026").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(LM.ink3).tracking(1.2)
                            Text("3,214 km · 6 journeys").font(.system(size: 16.5, weight: .semibold))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(LM.ink3)
                    }
                    .padding(18)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(0.05)))
                    .padding(.top, 14)
                }
            }
        }
    }
    private func chip(_ t: String, on: Bool = false) -> some View {
        Text(t).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(on ? .white : LM.ink2)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(on ? .white.opacity(0.12) : .white.opacity(0.03)).overlay(Capsule().stroke(.white.opacity(on ? 0.16 : 0.06), lineWidth: 1)))
    }
    private func cell(_ l: String, _ v: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(l).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).foregroundStyle(Color(hex: 0xA98BE8)).tracking(1.4)
            Text(v).font(.system(size: 23, weight: .bold)).foregroundStyle(.white)
            Text(s).font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color(hex: 0x9C86E0))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 15)
    }
    private var divider: some View { Rectangle().fill(.white.opacity(0.08)).frame(width: 1, height: 44) }
}

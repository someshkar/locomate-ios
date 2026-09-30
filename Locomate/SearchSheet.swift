import SwiftUI

struct SearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // pill field
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .semibold)).foregroundStyle(LM.ink2)
                        Text("Train no., station or route").font(.system(size: 17, weight: .medium)).foregroundStyle(LM.ink3)
                        Spacer()
                    }
                    .padding(15)
                    .background(Capsule().fill(.white.opacity(0.07)).overlay(Capsule().stroke(.white.opacity(0.1), lineWidth: 1)))
                    .padding(.top, 4)

                    section("Recent")
                    recent("12951", "Mumbai Rajdhani · NDLS → MMCT", status: ("On time", LM.success))
                    recent("12952", "Mumbai Rajdhani · MMCT → NDLS", status: ("~20 min late", LM.warn))
                    section("Stations")
                    FlowRow(spacing: 10) { station("NDLS");station("MMCT");station("KOTA");station("BRC") }
                }
                .padding(.horizontal, 22)
            }
            .background(Color(white: 0.07).ignoresSafeArea())
            .navigationTitle("Search")
            .toolbar(content: { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } })
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(34)
    }
    private func section(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(LM.ink3).tracking(0.8)
            .padding(.top, 26).padding(.bottom, 12).padding(.horizontal, 2)
    }
    private func recent(_ num: String, _ name: String, status: (String, Color)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(num).font(.system(size: 17, weight: .bold, design: .monospaced))
                Text(name).font(.system(size: 14.5, weight: .medium)).foregroundStyle(LM.ink2)
            }
            Spacer()
            Text(status.0).font(.system(size: 13, weight: .semibold)).foregroundStyle(status.1)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Capsule().fill(status.1.opacity(0.14)))
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.05)))
        .padding(.bottom, 12)
    }
    private func station(_ t: String) -> some View {
        Text(t).font(.system(size: 14, weight: .semibold)).foregroundStyle(LM.ink2).padding(.horizontal, 16).padding(.vertical, 9)
            .background(Capsule().fill(.white.opacity(0.06)).overlay(Capsule().stroke(.white.opacity(0.06), lineWidth: 1)))
    }
}

// tiny flow layout for chips
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity; var x: CGFloat = 0, y: CGFloat = 0, h: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > w { x = 0; y += h + spacing; h = 0 }
            x += s.width + spacing; h = max(h, s.height)
        }
        return .init(width: w, height: y + h)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, h: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += h + spacing; h = 0 }
            v.place(at: .init(x: x, y: y), proposal: .init(s))
            x += s.width + spacing; h = max(h, s.height)
        }
    }
}

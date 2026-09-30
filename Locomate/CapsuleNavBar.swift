import SwiftUI

// Floating capsule navbar — the Liquid Glass pill tabs + separate search bubble.
struct CapsuleNavBar: View {
    @Binding var tab: Tab
    var onSearch: () -> Void
    @Namespace private var bubble

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                tabButton(.journeys, label: "Journeys", icon: {
                    RoundedRectangle(cornerRadius: 4).stroke(lineWidth: 1.8)
                        .overlay(Rectangle().frame(height: 1.8).offset(y: 0.2))
                        .frame(width: 20, height: 20)
                })
                tabButton(.explore, label: "Explore", icon: {
                    ZStack { Circle().stroke(lineWidth: 1.8).frame(width: 20, height: 20)
                             Path { p in p.move(to: .init(x: 12, y: 2)); p.addLine(to: .init(x: 12, y: 22)); p.move(to: .init(x: 2, y: 12)); p.addLine(to: .init(x: 22, y: 12)) }.stroke(lineWidth: 1.6) }
                        .frame(width: 20, height: 20)
                })
                tabButton(.passport, label: "Passport", icon: {
                    RoundedRectangle(cornerRadius: 3.5).stroke(lineWidth: 1.8)
                        .overlay(Circle().stroke(lineWidth: 1.4).frame(width: 5))
                        .overlay(Rectangle().frame(width: 7, height: 1.4).offset(y: 7))
                        .frame(width: 20, height: 20)
                })
            }
            .padding(8)
            .background(glass(radius: 36))

            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(19)
                    .background(glass(radius: 30))
            }
        }
        .shadow(color: .black.opacity(0.42), radius: 16, y: 8)
    }

    private func tabButton(_ t: Tab, label: String, icon: () -> some View) -> some View {
        let active = tab == t
        return Button {
            withAnimation(LM.springUI) { tab = t }
        } label: {
            VStack(spacing: 4) {
                icon()
                Text(label).font(.system(size: 10.5, weight: .semibold, design: .default))
            }
            .foregroundStyle(active ? .white : LM.ink2)
            .padding(.horizontal, 15).padding(.vertical, 9)
            .background(
                ZStack {
                    if active {
                        Capsule()
                            .fill(.white.opacity(0.09))
                            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                            .matchedGeometryEffect(id: "pill", in: bubble)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // Clean lens: ultra-thin material + subtle inner shine — the restrained glass.
    private func glass(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.white.opacity(0.14), lineWidth: 1))
    }
}

import SwiftUI

struct JourneyView: View {
    @State private var presented = true

    var body: some View {
        ZStack(alignment: .bottom) {
            MapCanvas()
            // subtle fade so the map melts into the sheet
            LinearGradient(colors: [.black.opacity(0.10), .black.opacity(0.0), .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            GlassSheet(collapsed: 0.56, expanded: 0.86, presented: $presented) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("My Journeys")
                            .font(.system(size: 34, weight: .heavy)).tracking(-1.2)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 17, weight: .bold))
                            .padding(11).background(Circle().fill(.white.opacity(0.08)))
                        Circle().fill(LinearGradient(colors: [LM.success, Color(hex: 0x1FA463)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .overlay(Text("SK").font(.system(size: 15, weight: .bold)).foregroundStyle(Color(hex: 0x06110A)))
                            .frame(width: 40, height: 40)
                    }

                    // Journey card
                    JourneyCard()
                        .padding(.top, 22)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

struct JourneyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("12951").monospacedDigit().font(.system(size: 14.5, weight: .medium, design: .monospaced)).foregroundStyle(LM.ink2)
                Text("· Mumbai Rajdhani").font(.system(size: 14.5, weight: .medium)).foregroundStyle(LM.ink3)
                Spacer()
                Text("Departs ").font(.system(size: 14.5, weight: .medium)).foregroundStyle(LM.ink3)
                + Text("On Time").font(.system(size: 14.5, weight: .bold)).foregroundStyle(LM.success)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("1").font(.system(size: 30, weight: .heavy)).tracking(-0.4)
                Text("day").font(.system(size: 16, weight: .semibold)).foregroundStyle(LM.ink2)
                Text("4").font(.system(size: 30, weight: .heavy)).tracking(-0.4).padding(.leading, 4)
                Text("hours").font(.system(size: 16, weight: .semibold)).foregroundStyle(LM.ink2)
                Text("  until departure").font(.system(size: 12, weight: .medium)).foregroundStyle(LM.ink3)
            }
            .padding(.top, 14)
            Text("New Delhi to Mumbai").font(.system(size: 17, weight: .semibold)).tracking(-0.3).padding(.top, 6)

            HStack(spacing: 14) {
                leg("chevron.up.right.circle.fill", "NDLS", "16:25", nil)
                Spacer()
                leg("chevron.down.right.circle.fill", "MMCT", "08:15", "+1")
            }
            .padding(.top, 20)
            .padding(.top, 18)
            .overlay(alignment: .top) { hairline().padding(.top, 44) }
        }
    }

    private func leg(_ icon: String, _ code: String, _ time: String, _ plus: String?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(LM.success)
                .symbolRenderingMode(.palette).foregroundStyle(.white, LM.success.opacity(0.2))
            VStack(alignment: .leading, spacing: 1) {
                Text(code).font(.system(size: 15, weight: .semibold, design: .monospaced)).foregroundStyle(LM.ink2)
                HStack(spacing: 3) {
                    Text(time).font(.system(size: 18, weight: .bold)).foregroundStyle(LM.success).tracking(-0.3)
                    if let plus { Text(plus).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(LM.success) }
                }
            }
        }
    }

    private func hairline() -> some View { Rectangle().fill(LM.hairline).frame(height: 1) }
}

struct JourneyView_Previews: PreviewProvider {
    static var previews: some View { JourneyView().preferredColorScheme(.dark) }
}

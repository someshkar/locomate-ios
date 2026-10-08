import SwiftUI
import MapKit

private let text = "The origin date is the day the train starts in India — overnight runs may reach your station the next day."
private let white = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255)
private let ink = Color(red: 17 / 255, green: 17 / 255, blue: 25 / 255)
@main struct ContrastRepro: App {
    private let sample = ProcessInfo.processInfo.environment["CONTRAST_SAMPLE"] ?? "system"
    var body: some Scene {
        WindowGroup {
            if sample == "scroll" || sample == "map" || sample == "scroll-solid" || sample == "scroll-shape" { ScrollingText(map: sample == "map", solid: sample == "scroll-solid", shape: sample == "scroll-shape") }
            else if sample == "uikit" { NativeText().padding(20).background(ink).preferredColorScheme(.dark) }
            else {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Origin date").font(.title.bold())
                    if sample == "color" { Text(text).foregroundColor(white) }
                    else { Text(text).foregroundStyle(sample == "system" ? .white : white) }
                }.font(.system(.footnote, weight: .medium))
                    .padding(20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .foregroundStyle(.white).background(sample == "system" ? .black : ink).preferredColorScheme(.dark)
            }
        }
    }
}
private struct NativeText: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = UIColor(red: 17 / 255, green: 17 / 255, blue: 25 / 255, alpha: 1)
        let label = UILabel()
        label.text = text; label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(red: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor), label.topAnchor.constraint(equalTo: container.topAnchor)])
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {}
}

private struct ScrollingText: View {
    let map: Bool
    let solid: Bool
    let shape: Bool
    var body: some View {
        ZStack(alignment: .top) {
            if map {
                Map(initialPosition: .region(.init(center: .init(latitude: 22, longitude: 79), span: .init(latitudeDelta: 20, longitudeDelta: 20))))
                    .mapStyle(.hybrid(elevation: .flat)).ignoresSafeArea()
            } else { ink.ignoresSafeArea() }
            VStack(spacing: 0) {
                Color.clear.frame(height: 190)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Origin date").font(.title.bold())
                        Text(text).font(.system(.footnote, weight: .medium)).foregroundStyle(white)
                        Text("Search uses a historical Indian Railways snapshot. Results are real records, not current schedules.")
                            .font(.system(.footnote, weight: .medium)).foregroundStyle(.orange)
                        ForEach(0..<15) { index in Text("Station \(index)").font(.footnote).foregroundStyle(white) }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }.background { if solid { ink } else if shape { RoundedRectangle(cornerRadius: 28).fill(ink) } else { LinearGradient(colors: [ink, Color.black], startPoint: .top, endPoint: .bottom) } }
            }
        }.safeAreaInset(edge: .bottom) {
            HStack { Text("Journeys"); Text("Explore"); Text("Passport") }.padding(16).foregroundStyle(white).background(ink)
        }.preferredColorScheme(.dark)
    }
}

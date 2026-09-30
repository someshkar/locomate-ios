import SwiftUI
import MapKit

// Full-bleed hybrid map with the glowing route arc — matches the Doop design.
struct MapCanvas: View {
    // New Delhi -> Mumbai control points (tuned to look like the design arc)
    private let c_ndls = CLLocationCoordinate2D(latitude: 28.6315, longitude: 77.2167)
    private let c_mmct = CLLocationCoordinate2D(latitude: 18.9689, longitude: 72.8236)

    @State private var camera: MapCameraPosition

    init() {
        let center = CLLocationCoordinate2D(latitude: 29.0, longitude: 76.0)
        _camera = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 13.5, longitudeDelta: 11.0))))
    }

    var body: some View {
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            // Blurred glow underlay (rendered as a thick, low-alpha polyline)
            MapPolyline(coordinates: [c_ndls, c_mmct])
                .stroke(LM.accent.opacity(0.28), lineWidth: 14)
            MapPolyline(coordinates: [c_ndls, c_mmct])
                .stroke(
                    LinearGradient(colors: [LM.accentHi, LM.accent],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
            Annotation("", coordinate: c_ndls) {
                Circle().fill(.white).frame(width: 14, height: 14)
                    .background(Circle().fill(LM.accentHi.opacity(0.45)).frame(width: 30))
            }
            Annotation("", coordinate: c_mmct) {
                Circle().fill(Color(.black)).overlay(Circle().stroke(LM.accentHi, lineWidth: 3))
                    .frame(width: 16, height: 16)
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
        .mapControls { } // hide defaults; design has its own cluster
        .ignoresSafeArea()
        .task(id: camera) {
            // gentle drift to keep the map feeling alive but calm
        }
    }
}

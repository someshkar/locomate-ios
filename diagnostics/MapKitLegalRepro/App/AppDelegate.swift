import UIKit
import MapKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let controller = UIViewController()
        let map = MKMapView()
        if ProcessInfo.processInfo.environment["MAP_MODE"] == "hybrid" {
            map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
        }
        map.setRegion(MKCoordinateRegion(center: .init(latitude: 23, longitude: 77),
            span: .init(latitudeDelta: 5, longitudeDelta: 5)), animated: false)
        controller.view = map
        let window = UIWindow(windowScene: scene)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        self.window = window
    }
}

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    // Created once per app launch and handed down to every screen that needs
    // the ModelContainer or the translation service.
    private let dependencies = AppDependencies()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = RootTabBarController(dependencies: dependencies)
        self.window = window
        window.makeKeyAndVisible()
    }
}

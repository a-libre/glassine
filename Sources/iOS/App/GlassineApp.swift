import SwiftUI
import UIKit

/// Glassine on iPhone and iPad: the same root view over the same state as the
/// Mac's (Sources/Mac/App/GlassineApp.swift), hosted in a window of the app's
/// own making — because the window is where an attached keyboard is heard.
///
/// SwiftUI's own app lifecycle was tried first, with the Mac's menu commands
/// for the keys: on an iPhone the commands' shortcuts were not reliably
/// delivered, and an app delegate handed to SwiftUI is not in the responder
/// chain, so its key commands were never asked for. A window that sees every
/// key before anything else (KeyWindow) is the Mac's key monitor again, and
/// behaves the same on both devices.
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Glassine", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = KeyWindow(windowScene: scene)
        let root = RootController(rootView: RootView())
        root.view.backgroundColor = .black
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        AppState.shared.systemAppearanceChanged(dark: UIScreen.main.traitCollection.userInterfaceStyle == .dark)
    }
}

/// Esc has a second way in. Most keys reach the window as presses; Esc does
/// not always (a UI test's never does), but a key command for it on the
/// controller every view sits in is always asked for.
final class RootController: UIHostingController<RootView> {
    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapePressed))
        escape.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [escape]
    }

    @objc private func escapePressed() { _ = KeyDispatcher.escape() }
}

/// Every key of an attached keyboard passes through here on its way to
/// whatever has the keyboard. The ones Glassine has a use for stop here
/// (KeyDispatcher); the rest — typing — carry on.
final class KeyWindow: UIWindow {
    /// Keys taken on the way down are taken on the way up too, so nothing
    /// further along sees half a keystroke.
    private var taken: Set<UIKeyboardHIDUsage> = []

    override func sendEvent(_ event: UIEvent) {
        guard let event = event as? UIPressesEvent else { super.sendEvent(event); return }
        var pass = false
        for press in event.allPresses {
            guard let key = press.key else { pass = true; continue }
            switch press.phase {
            case .began:
                if KeyDispatcher.handle(key) { taken.insert(key.keyCode) } else { pass = true }
            case .ended, .cancelled:
                if taken.remove(key.keyCode) == nil { pass = true }
            default:
                if !taken.contains(key.keyCode) { pass = true }
            }
        }
        if pass { super.sendEvent(event) }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        AppState.shared.systemAppearanceChanged(dark: UIScreen.main.traitCollection.userInterfaceStyle == .dark)
    }
}

/// The root of the view tree, watching the app's state itself and handing it down.
struct RootView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        // Measured here, outside the content's own disregard for the safe area.
        GeometryReader { proxy in
            ContentView()
                .environmentObject(state)
                .environment(\.windowMetrics, WindowMetrics(top: proxy.safeAreaInsets.top, bottom: proxy.safeAreaInsets.bottom,
                                                            width: proxy.size.width))
        }
    }
}

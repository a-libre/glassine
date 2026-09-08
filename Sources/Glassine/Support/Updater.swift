#if canImport(Sparkle)
import AppKit
import Sparkle

/// Updates for the direct download: Sparkle, reading appcast.xml at
/// glassine.ink, which release.sh writes and signs with the key generate_keys
/// put in the keychain of the Mac that cuts releases. Once a day it asks for
/// the feed; when there is something newer it says so, downloads the disk
/// image from GitHub, checks the signature against the public key in
/// Info.plist, swaps the app in place and relaunches it. The App Store flavor
/// is built without any of this — the store is its updater — which is why
/// everything here sits behind canImport(Sparkle).
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// Bring the updater up at launch; the first scheduled check follows a
    /// little later, on Sparkle's own clock.
    static func start(checkingAutomatically: Bool) {
        shared.checksAutomatically = checkingAutomatically
    }

    /// Sparkle keeps this in the app's defaults; the setting in Settings →
    /// General mirrors it.
    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastChecked: Date? { controller.updater.lastUpdateCheckDate }

    /// Help → Check for Updates…, and the button in Settings.
    func check() {
        controller.checkForUpdates(nil)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
#endif

import Foundation

/// Which way this copy of Glassine reached the Mac, and what that allows.
///
/// The direct download (Developer ID, notarized) runs without the App Sandbox
/// and can reach iCloud Drive straight from the filesystem. The App Store build
/// runs sandboxed: it owns an iCloud container of its own, and any other folder
/// has to be picked by the user and remembered through a security-scoped
/// bookmark. Both come from the same source; the only compile-time difference
/// is `APPSTORE`, which leaves the GitHub update check out of the store build.
enum Distribution {
    /// The iCloud container declared in the App Store entitlements.
    static let iCloudContainerID = "iCloud.com.alexlibre.glassine"

    /// True when the App Sandbox is on. A sandboxed process gets a home
    /// directory inside ~/Library/Containers, which is the cheapest reliable tell.
    static let isSandboxed: Bool = {
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil { return true }
        return NSHomeDirectory().contains("/Library/Containers/")
    }()

    #if APPSTORE
    static let isAppStore = true
    #else
    static let isAppStore = false
    #endif

    /// For diagnostics and the About text.
    static var channel: String {
        isAppStore ? "App Store" : (isSandboxed ? "Sandboxed" : "Direct")
    }

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// The user's real home folder, even inside the sandbox (where NSHomeDirectory
    /// is the container). Used only to shorten paths for display.
    static let realHomePath: String = {
        if let dir = getpwuid(getuid())?.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }()

    private static let containerCacheKey = "glassine.icloudContainer.path"

    /// The Documents folder of Glassine's own iCloud container, when the entitlement
    /// is present and iCloud Drive is turned on. This is what shows in iCloud Drive
    /// as a "Glassine" folder with the app's icon. Nil outside the sandbox (the
    /// direct build uses iCloud Drive itself) and when iCloud is off.
    ///
    /// The ubiquity lookup can take a moment the very first time, so the answer is
    /// cached; later launches use the cached path at once and refresh it in the
    /// background.
    static func iCloudContainerDocuments() -> URL? {
        guard isSandboxed else { return nil }
        let defaults = UserDefaults.standard
        if let cached = defaults.string(forKey: containerCacheKey) {
            DispatchQueue.global(qos: .utility).async {
                if let fresh = lookUpContainer() { defaults.set(fresh.path, forKey: containerCacheKey) }
                else { defaults.removeObject(forKey: containerCacheKey) }
            }
            return URL(fileURLWithPath: cached, isDirectory: true)
        }
        // First launch: wait briefly for the daemon rather than guess at the path.
        var found: URL?
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            found = lookUpContainer()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 4)
        if let found { defaults.set(found.path, forKey: containerCacheKey) }
        return found
    }

    private static func lookUpContainer() -> URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerID)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// Where documents go when there is no iCloud and no chosen folder: the
    /// sandbox container's Documents (App Store) or ~/Documents/Glassine (direct).
    static func localDocumentsFallback(folderName: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents", isDirectory: true)
        return isSandboxed ? docs : docs.appendingPathComponent(folderName, isDirectory: true)
    }
}

/// A folder the user picked, kept reachable across launches. Outside the
/// sandbox this is just a path; inside it, the bookmark carries the permission,
/// which stays open for as long as this object lives.
final class ChosenFolder {
    let url: URL
    let bookmark: Data?
    private let accessing: Bool

    deinit { if accessing { url.stopAccessingSecurityScopedResource() } }

    /// Makes a bookmark for a folder the user just chose in an open panel.
    init(pickedURL: URL) {
        url = pickedURL
        bookmark = try? pickedURL.bookmarkData(options: Distribution.isSandboxed ? [.withSecurityScope] : [],
                                               includingResourceValuesForKeys: nil, relativeTo: nil)
        accessing = Distribution.isSandboxed && pickedURL.startAccessingSecurityScopedResource()
    }

    /// Reopens a folder from settings. Returns nil when the bookmark no longer
    /// resolves (the folder was removed or permission was lost); the caller then
    /// falls back to the default location.
    init?(bookmark data: Data?, path: String?) {
        if let data {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: data,
                                       options: Distribution.isSandboxed ? [.withSecurityScope] : [],
                                       relativeTo: nil, bookmarkDataIsStale: &stale) {
                url = resolved
                accessing = Distribution.isSandboxed && resolved.startAccessingSecurityScopedResource()
                // A stale bookmark still works this once; refresh it for next time.
                bookmark = stale ? (try? resolved.bookmarkData(options: Distribution.isSandboxed ? [.withSecurityScope] : [],
                                                               includingResourceValuesForKeys: nil, relativeTo: nil)) ?? data : data
                return
            }
        }
        // No bookmark (a library chosen before bookmarks existed): the path alone
        // is enough outside the sandbox, and nothing inside it.
        guard let path, !path.isEmpty, !Distribution.isSandboxed else { return nil }
        url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
        bookmark = nil
        accessing = false
    }

    var isReachable: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

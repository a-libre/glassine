import Foundation

/// Glassine shipped briefly as "Pyrus". These helpers pick up settings, themes
/// and the iCloud folder from that name so nothing is lost on the first launch.
enum Legacy {
    static let oldBundleID = "com.alexlibre.pyrus"
    static let oldFolderName = "Pyrus"

    /// Data stored under the old bundle identifier, if any.
    static func defaultsData(forKey key: String) -> Data? {
        UserDefaults(suiteName: oldBundleID)?.data(forKey: key)
    }

    /// Renames a "Pyrus" library folder to the new name when the new one doesn't exist yet.
    static func migrateLibraryFolderIfNeeded(newRoot: URL) {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newRoot.path) else { return }
        let oldRoot = newRoot.deletingLastPathComponent().appendingPathComponent(oldFolderName, isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: oldRoot.path, isDirectory: &isDir), isDir.boolValue else { return }
        try? fm.moveItem(at: oldRoot, to: newRoot)
    }
}

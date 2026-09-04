import Foundation

/// The Shelf: out of the way, not gone. A shelved document or folder moves
/// under a `Shelf` folder at the top of the library, keeping the path it had
/// (Essays/Draft.md becomes Shelf/Essays/Draft.md), so it is still a plain
/// file that syncs and can be searched — it just leaves Recents, Starred, the
/// folder tree and All Documents, and sits in its own collapsed section at the
/// bottom of the sidebar. Unshelving puts it back exactly where it was.
enum Shelf {
    static let folder = "Shelf"

    /// True for the Shelf folder itself and anything inside it.
    static func holds(_ rel: String) -> Bool {
        rel == folder || rel.hasPrefix(folder + "/")
    }

    /// Where something on the Shelf came from: "Shelf/Essays/Draft.md" → "Essays/Draft.md".
    static func home(of rel: String) -> String {
        rel.hasPrefix(folder + "/") ? String(rel.dropFirst(folder.count + 1)) : rel
    }

    /// The folder a relative path sits in ("" at the top level).
    static func parent(of rel: String) -> String {
        guard let slash = rel.lastIndex(of: "/") else { return "" }
        return String(rel[..<slash])
    }
}

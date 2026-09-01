import AppKit
import Combine

struct DocumentRef: Identifiable, Hashable {
    /// Path relative to the library root, e.g. "Essays/On Writing.md".
    let id: String
    let url: URL
    let title: String
    let modified: Date
    let created: Date
    let size: Int
    let folder: String
    var tags: [String]
    /// The first ~2000 characters, used for gallery cards.
    var preview: String = ""
    /// False until the file has been read (the launch listing skips reading).
    var contentLoaded: Bool = true
}

struct LibraryFolder: Identifiable, Hashable {
    /// Relative path ("" for the root).
    let id: String
    let name: String
    let url: URL
    var folders: [LibraryFolder]
    var documents: [DocumentRef]

    var isRoot: Bool { id.isEmpty }

    var allDocuments: [DocumentRef] {
        documents + folders.flatMap { $0.allDocuments }
    }

    var allFolders: [LibraryFolder] {
        folders + folders.flatMap { $0.allFolders }
    }
}

struct TagInfo: Identifiable, Hashable {
    let name: String
    let count: Int
    var id: String { name }
}

/// The document library: a folder (by default inside iCloud Drive) full of Markdown files.
final class LibraryStore: ObservableObject {
    static let appFolderName = "Glassine"
    static let extensions: Set<String> = ["md", "markdown", "txt", "text"]

    @Published private(set) var root: LibraryFolder
    @Published private(set) var allDocuments: [DocumentRef] = []
    @Published private(set) var tags: [TagInfo] = []
    @Published private(set) var lastError: String? = nil
    @Published private(set) var isScanning = false

    let rootURL: URL
    let isInICloud: Bool

    private let scanQueue = DispatchQueue(label: "glassine.library.scan", qos: .userInitiated)
    private var lastSignature: Int = 0
    /// False after a listing that skipped file contents; the next full scan always applies.
    private var contentsComplete = true
    /// Bumped whenever the document list changes; cheap to compare in caches.
    private(set) var generation = 0
    private var tagCache: [String: CachedMeta] = [:]

    struct CachedMeta {
        let modified: Date
        let tags: [String]
        let preview: String
        /// The whole text, folded for searching (lowercase, accents stripped).
        let searchable: String
    }

    /// Text as the search compares it: case- and accent-insensitive.
    static func searchable(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The searchable text of a document as of the last scan, if it was small enough to read.
    func searchableText(for id: String) -> String? {
        tagCache[id]?.searchable
    }
    private var scanPending = false

    // MARK: - Root resolution

    static var iCloudDriveURL: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func defaultRootURL() -> (URL, Bool) {
        if let icloud = iCloudDriveURL {
            return (icloud.appendingPathComponent(appFolderName, isDirectory: true), true)
        }
        let docs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents", isDirectory: true)
        return (docs.appendingPathComponent(appFolderName, isDirectory: true), false)
    }

    init(customPath: String?) {
        var url: URL
        var inCloud: Bool
        if let p = customPath, !p.isEmpty {
            url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
            inCloud = url.path.contains("Mobile Documents/com~apple~CloudDocs")
        } else {
            (url, inCloud) = LibraryStore.defaultRootURL()
        }
        rootURL = url.standardizedFileURL
        isInICloud = inCloud
        root = LibraryFolder(id: "", name: rootURL.lastPathComponent, url: rootURL, folders: [], documents: [])
        if customPath == nil || customPath?.isEmpty == true {
            Legacy.migrateLibraryFolderIfNeeded(newRoot: rootURL)
        }
        ensureRootExists()
    }

    private func ensureRootExists() {
        do {
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDir) {
                try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            }
        } catch {
            lastError = "Couldn't create the library folder: \(error.localizedDescription)"
        }
    }

    var isEmptyOnDisk: Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
        return items.filter { !$0.hasPrefix(".") }.isEmpty
    }

    // MARK: - Paths

    func url(forRelativePath rel: String) -> URL {
        rel.isEmpty ? rootURL : rootURL.appendingPathComponent(rel)
    }

    func relativePath(for url: URL) -> String {
        url.pathRelative(to: rootURL)
    }

    func document(withID id: String) -> DocumentRef? {
        allDocuments.first { $0.id == id }
    }

    func folder(withID id: String) -> LibraryFolder? {
        if id.isEmpty { return root }
        return root.allFolders.first { $0.id == id }
    }

    // MARK: - Scanning

    /// Scans synchronously (used at launch so the first frame has content).
    /// Synchronous scan. With `readingContents: false` it only lists files (no reads),
    /// which is what launch wants: the window comes up at once and a full scan follows.
    func scanNow(readingContents: Bool = true) {
        let result = LibraryStore.scan(rootURL: rootURL, tagCache: &tagCache, readContents: readingContents)
        apply(result)
    }

    func rescan() {
        guard !scanPending else { return }
        scanPending = true
        var cache = tagCache
        let rootURL = self.rootURL
        scanQueue.async { [weak self] in
            let result = LibraryStore.scan(rootURL: rootURL, tagCache: &cache)
            DispatchQueue.main.async {
                guard let self else { return }
                self.scanPending = false
                self.tagCache = cache
                self.apply(result)
            }
        }
    }

    private func apply(_ result: ScanResult) {
        if result.signature == lastSignature && contentsComplete && lastError == nil { return }
        lastSignature = result.signature
        contentsComplete = result.complete
        generation += 1
        root = result.root
        allDocuments = result.root.allDocuments
        var counts: [String: Int] = [:]
        for d in allDocuments { for t in d.tags { counts[t, default: 0] += 1 } }
        tags = counts.map { TagInfo(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    private struct ScanResult {
        var root: LibraryFolder
        var signature: Int
        /// Every readable file's contents were read (or came from the cache).
        var complete: Bool
    }

    private static func scan(rootURL: URL, tagCache: inout [String: CachedMeta], readContents: Bool = true) -> ScanResult {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey, .fileAllocatedSizeKey, .nameKey]
        var hasher = Hasher()

        func buildFolder(at url: URL, rel: String) -> LibraryFolder {
            var folders: [LibraryFolder] = []
            var docs: [DocumentRef] = []
            let items = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            for item in items {
                let values = try? item.resourceValues(forKeys: Set(keys))
                let name = values?.name ?? item.lastPathComponent
                if name.hasPrefix(".") { continue }
                let childRel = rel.isEmpty ? name : rel + "/" + name
                if values?.isDirectory == true {
                    folders.append(buildFolder(at: item, rel: childRel))
                } else if extensions.contains(item.pathExtension.lowercased()) {
                    let modified = values?.contentModificationDate ?? Date.distantPast
                    let created = values?.creationDate ?? modified
                    let size = values?.fileSize ?? 0
                    let allocated = values?.fileAllocatedSize ?? size
                    hasher.combine(childRel)
                    hasher.combine(modified)
                    hasher.combine(size)

                    var tags: [String] = []
                    var preview = ""
                    var loaded = true
                    if let cached = tagCache[childRel], cached.modified == modified {
                        tags = cached.tags
                        preview = cached.preview
                    } else if !readContents {
                        loaded = false
                    } else if size > 0 && allocated == 0 {
                        // Dataless iCloud file (not downloaded yet): ask for it, don't block on it.
                        try? fm.startDownloadingUbiquitousItem(at: item)
                    } else if size < 2_000_000 {
                        var searchable = ""
                        if let text = try? String(contentsOf: item, encoding: .utf8) {
                            tags = TagExtractor.tags(in: text)
                            preview = String(text.prefix(2000))
                            searchable = LibraryStore.searchable(text)
                        }
                        tagCache[childRel] = CachedMeta(modified: modified, tags: tags, preview: preview, searchable: searchable)
                    }
                    docs.append(DocumentRef(
                        id: childRel, url: item,
                        title: item.deletingPathExtension().lastPathComponent,
                        modified: modified, created: created, size: size,
                        folder: rel, tags: tags, preview: preview, contentLoaded: loaded
                    ))
                }
            }
            folders.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let folderName = rel.isEmpty ? rootURL.lastPathComponent : (rel as NSString).lastPathComponent
            return LibraryFolder(id: rel, name: folderName, url: url, folders: folders, documents: docs)
        }

        let root = buildFolder(at: rootURL, rel: "")
        for f in root.allFolders { hasher.combine("dir:" + f.id) }
        return ScanResult(root: root, signature: hasher.finalize(), complete: readContents)
    }

    // MARK: - File operations

    func uniqueURL(in folder: URL, stem: String, ext: String = "md") -> URL {
        var candidate = folder.appendingPathComponent(stem).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) \(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    func createDocument(in folderRel: String, stem: String = "Untitled", contents: String = "") throws -> DocumentRef {
        let folderURL = url(forRelativePath: folderRel)
        let target = uniqueURL(in: folderURL, stem: stem)
        try FileCoordination.write(contents, to: target)
        let now = Date()
        let rel = relativePath(for: target)
        let ref = DocumentRef(id: rel, url: target, title: target.deletingPathExtension().lastPathComponent,
                              modified: now, created: now, size: contents.utf8.count, folder: folderRel, tags: [],
                              preview: String(contents.prefix(2000)))
        scanNow()
        return ref
    }

    func createFolder(named name: String, in parentRel: String) throws -> String {
        let clean = name.sanitizedFileStem
        guard !clean.isEmpty else { throw LibraryError.invalidName }
        let target = url(forRelativePath: parentRel).appendingPathComponent(clean, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        scanNow()
        return relativePath(for: target)
    }

    /// Renames a file or folder. Returns the new relative path.
    func rename(_ rel: String, to newStem: String) throws -> String {
        let source = url(forRelativePath: rel)
        let clean = newStem.sanitizedFileStem
        guard !clean.isEmpty else { throw LibraryError.invalidName }
        let parent = source.deletingLastPathComponent()
        let target: URL
        if source.isDirectoryURL {
            target = parent.appendingPathComponent(clean, isDirectory: true)
        } else {
            let ext = source.pathExtension.isEmpty ? "md" : source.pathExtension
            target = parent.appendingPathComponent(clean).appendingPathExtension(ext)
        }
        if target.standardizedFileURL == source.standardizedFileURL { return rel }
        guard !FileManager.default.fileExists(atPath: target.path) else { throw LibraryError.alreadyExists }
        try FileCoordination.move(from: source, to: target)
        scanNow()
        return relativePath(for: target)
    }

    func move(_ rel: String, toFolder folderRel: String) throws -> String {
        let source = url(forRelativePath: rel)
        let folderURL = url(forRelativePath: folderRel)
        var target = folderURL.appendingPathComponent(source.lastPathComponent)
        if target.standardizedFileURL == source.standardizedFileURL { return rel }
        if FileManager.default.fileExists(atPath: target.path) {
            target = uniqueURL(in: folderURL, stem: source.deletingPathExtension().lastPathComponent, ext: source.pathExtension)
        }
        try FileCoordination.move(from: source, to: target)
        scanNow()
        return relativePath(for: target)
    }

    func duplicate(_ rel: String) throws -> String {
        let source = url(forRelativePath: rel)
        let target = uniqueURL(in: source.deletingLastPathComponent(),
                               stem: source.deletingPathExtension().lastPathComponent + " Copy",
                               ext: source.pathExtension)
        try FileManager.default.copyItem(at: source, to: target)
        scanNow()
        return relativePath(for: target)
    }

    func trash(_ rel: String) throws {
        let source = url(forRelativePath: rel)
        try FileManager.default.trashItem(at: source, resultingItemURL: nil)
        scanNow()
    }

    func revealInFinder(_ rel: String) {
        NSWorkspace.shared.activateFileViewerSelecting([url(forRelativePath: rel)])
    }
}

enum LibraryError: LocalizedError {
    case invalidName, alreadyExists
    var errorDescription: String? {
        switch self {
        case .invalidName: return "That name can't be used."
        case .alreadyExists: return "Something with that name already exists."
        }
    }
}

enum TagExtractor {
    private static let regex = try! NSRegularExpression(pattern: "(?<![\\w#/&])#([A-Za-z_][\\w\\-/]*)", options: [])
    private static let hexLike = try! NSRegularExpression(pattern: "^[0-9A-Fa-f]{3}$|^[0-9A-Fa-f]{6}$", options: [])

    static func tags(in text: String) -> [String] {
        let ns = text as NSString
        var found = Set<String>()
        for m in regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: m.range(at: 1))
            if hexLike.firstMatch(in: tag, options: [], range: NSRange(location: 0, length: (tag as NSString).length)) != nil { continue }
            found.insert(tag.lowercased())
        }
        return found.sorted()
    }
}

enum FileCoordination {
    static func read(_ url: URL) throws -> String {
        var coordError: NSError?
        var result: String?
        var readError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            do {
                if let s = try? String(contentsOf: u, encoding: .utf8) {
                    result = s
                } else {
                    var enc = String.Encoding.utf8
                    result = try String(contentsOf: u, usedEncoding: &enc)
                }
            } catch {
                readError = error
            }
        }
        if let e = coordError { throw e }
        if let e = readError { throw e }
        return result ?? ""
    }

    static func write(_ text: String, to url: URL) throws {
        var coordError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forReplacing, error: &coordError) { u in
            do {
                try Data(text.utf8).write(to: u, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let e = coordError { throw e }
        if let e = writeError { throw e }
    }

    static func move(from source: URL, to target: URL) throws {
        var coordError: NSError?
        var moveError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: source, options: .forMoving,
                                                         writingItemAt: target, options: .forReplacing,
                                                         error: &coordError) { s, t in
            do {
                try FileManager.default.moveItem(at: s, to: t)
            } catch {
                moveError = error
            }
        }
        if let e = coordError { throw e }
        if let e = moveError { throw e }
    }
}

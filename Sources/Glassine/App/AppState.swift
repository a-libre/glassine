import AppKit
import Combine
import SwiftUI

/// Central app state: settings, themes, the library and the open document.
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings: AppSettings
    let themes: ThemeStore
    @Published private(set) var library: LibraryStore
    @Published private(set) var document: DocumentModel?
    @Published var selection: String?          // relative path of the selected document
    @Published var selectedFolder: String = "" // relative path of the folder new docs go into
    @Published var tagFilter: String?
    @Published var searchText: String = ""
    @Published var pendingPrompt: Prompt?
    @Published var errorMessage: String?
    /// The Craft-style mosaic of every document. Also shown whenever nothing is open.
    @Published var showingGallery: Bool = false
    /// Review mode: the current document rendered read-only in a chosen style.
    @Published var reviewMode: Bool = false
    /// Short confirmation shown in the footer ("Copied as Markdown").
    @Published var transientNotice: String?
    private var noticeWork: DispatchWorkItem?
    /// Scroll position (0–1) the editor was at when Review mode was entered.
    var reviewEntryScrollFraction: Double = 0
    /// Bumped by ⌘F; whichever search box is on screen takes focus and clears the flag.
    @Published var searchFocusRequest: Int = 0
    var searchFocusPending = false

    /// The mosaic is what the content area shows (asked for, or nothing is open).
    var galleryOnScreen: Bool { showingGallery || document == nil }

    enum Prompt: Identifiable {
        case newFolder(parent: String)
        case rename(path: String, isFolder: Bool)

        var id: String {
            switch self {
            case .newFolder(let p): return "newFolder:\(p)"
            case .rename(let p, _): return "rename:\(p)"
            }
        }
    }

    var theme: Theme { themes.theme(id: settings.data.themeID) }
    var styleConfig: StyleConfig { StyleConfig(theme: theme, settings: settings.data) }

    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?

    private init() {
        let settings = AppSettings()
        self.settings = settings
        self.themes = ThemeStore()
        self.library = LibraryStore(customPath: settings.data.libraryPath)

        // Republish nested object changes so views observing AppState refresh.
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        themes.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        bindLibrary()

        bootstrapLibrary()
        startPolling()

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.library.rescan()
            self?.document?.checkExternalChanges()
        }
        nc.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.document?.save()
        }
        nc.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveEverythingNow()
        }
    }

    private func bindLibrary() {
        library.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    private func bootstrapLibrary() {
        if library.isEmptyOnDisk {
            _ = try? library.createDocument(in: "", stem: "Welcome to Glassine", contents: WelcomeDocument.text)
        }
        library.scanNow()
        if let last = settings.data.lastOpenedDocument, let ref = library.document(withID: last) {
            open(ref)
        } else {
            showingGallery = true
        }
    }

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self, NSApp.isActive else { return }
            self.library.rescan()
            self.document?.checkExternalChanges()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    // MARK: - Derived lists

    var recentDocuments: [DocumentRef] {
        let recents = settings.data.recents
        return library.allDocuments
            .filter { recents[$0.id] != nil }
            .sorted { (recents[$0.id] ?? .distantPast) > (recents[$1.id] ?? .distantPast) }
    }

    var starredDocuments: [DocumentRef] {
        let starred = settings.data.starred
        return library.allDocuments.filter { starred.contains($0.id) }
            .sorted { starred.firstIndex(of: $0.id)! < starred.firstIndex(of: $1.id)! }
    }

    func sorted(_ docs: [DocumentRef]) -> [DocumentRef] {
        switch settings.data.sortDocumentsBy {
        case .modified: return docs.sorted { $0.modified > $1.modified }
        case .created: return docs.sorted { $0.created > $1.created }
        case .name: return docs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    /// Documents matching the search box and/or the tag filter, or nil when neither is set.
    /// Every word of the query has to appear somewhere in the title, tags or text
    /// (case- and accent-insensitive). Title matches come first, then the rest in the usual order.
    var filteredDocuments: [DocumentRef]? {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        let base: [DocumentRef]
        if let tag = tagFilter {
            base = library.allDocuments.filter { $0.tags.contains(tag) }
        } else {
            guard !q.isEmpty else { return nil }
            base = library.allDocuments
        }
        guard !q.isEmpty else { return sorted(base) }

        let words = LibraryStore.searchable(q).split(separator: " ").map(String.init)
        // The open document may be ahead of what is on disk.
        let liveID = document?.relativePath
        let liveText = document.map { LibraryStore.searchable($0.text) }
        var titleHits: [DocumentRef] = []
        var otherHits: [DocumentRef] = []
        for doc in base {
            let title = LibraryStore.searchable(doc.title)
            if words.allSatisfy({ title.contains($0) }) { titleHits.append(doc); continue }
            let body = doc.id == liveID ? liveText : library.searchableText(for: doc.id)
            let haystack = title + "\n" + doc.tags.joined(separator: " ") + "\n" + (body ?? "")
            if words.allSatisfy({ haystack.contains($0) }) { otherHits.append(doc) }
        }
        return sorted(titleHits) + sorted(otherHits)
    }

    /// ⌘F: focus the search box in the mosaic when it is showing, else the sidebar's
    /// (bringing the sidebar back if it is hidden).
    func focusSearch() {
        if !galleryOnScreen && !settings.data.sidebarVisible { toggleSidebar() }
        searchFocusPending = true
        searchFocusRequest += 1
    }

    // MARK: - Opening documents

    func open(_ ref: DocumentRef) {
        showingGallery = false
        if let current = document, current.relativePath == ref.id { return }
        closeCurrentDocument()
        let doc = DocumentModel(url: ref.url, library: library, settings: settings)
        wire(doc)
        document = doc
        selection = ref.id
        selectedFolder = ref.folder
        settings.touchRecent(ref.id)
        settings.data.lastOpenedDocument = ref.id
    }

    func open(relativePath: String) {
        if let ref = library.document(withID: relativePath) { open(ref) }
    }

    private func wire(_ doc: DocumentModel) {
        doc.onRenamed = { [weak self] old, new in
            guard let self else { return }
            self.settings.renamePath(old, to: new)
            if self.selection == old { self.selection = new }
            self.objectWillChange.send()
        }
        doc.onVanished = { [weak self] in
            guard let self else { return }
            self.document = nil
            self.selection = nil
            self.library.rescan()
        }
    }

    private func closeCurrentDocument() {
        guard let doc = document else { return }
        doc.close()
        document = nil
    }

    func caretMoved(to position: Int) {
        guard let doc = document else { return }
        settings.data.caretPositions[doc.relativePath] = position
    }

    func savedCaret(for relPath: String) -> Int? {
        settings.data.caretPositions[relPath]
    }

    // MARK: - Creating

    func newDocument(in folder: String? = nil) {
        let target = folder ?? selectedFolder
        do {
            let ref = try library.createDocument(in: target)
            open(ref)
            reviewMode = false
            if !target.isEmpty { settings.setExpanded(target, true) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func promptNewFolder(in parent: String? = nil) {
        pendingPrompt = .newFolder(parent: parent ?? selectedFolder)
    }

    func createFolder(named name: String, in parent: String) {
        do {
            let rel = try library.createFolder(named: name, in: parent)
            settings.setExpanded(rel, true)
            if !parent.isEmpty { settings.setExpanded(parent, true) }
            selectedFolder = rel
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - File management

    func promptRename(_ rel: String, isFolder: Bool) {
        pendingPrompt = .rename(path: rel, isFolder: isFolder)
    }

    func rename(_ rel: String, to newName: String, isFolder: Bool) {
        do {
            if let doc = document, doc.relativePath == rel {
                try doc.rename(to: newName)
            } else {
                let newRel = try library.rename(rel, to: newName)
                settings.renamePath(rel, to: newRel)
                if isFolder, let doc = document, doc.relativePath.hasPrefix(rel + "/") {
                    let moved = newRel + doc.relativePath.dropFirst(rel.count)
                    doc.didMove(to: moved)
                    selection = moved
                    settings.data.lastOpenedDocument = moved
                }
                if selectedFolder == rel { selectedFolder = newRel }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ rel: String, toFolder folder: String) {
        do {
            let wasOpen = document?.relativePath == rel
            if wasOpen { document?.saveNow() }
            let newRel = try library.move(rel, toFolder: folder)
            settings.renamePath(rel, to: newRel)
            if wasOpen {
                document?.didMove(to: newRel)
                selection = newRel
                selectedFolder = folder
                settings.data.lastOpenedDocument = newRel
            }
            if !folder.isEmpty { settings.setExpanded(folder, true) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ rel: String) {
        do {
            if document?.relativePath == rel { document?.saveNow() }
            let newRel = try library.duplicate(rel)
            open(relativePath: newRel)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func trash(_ rel: String) {
        do {
            let wasOpen = document?.relativePath == rel || (document?.relativePath.hasPrefix(rel + "/") ?? false)
            if wasOpen {
                document?.saveNow()
                document = nil
                selection = nil
            }
            try library.trash(rel)
            settings.forgetPath(rel)
            if selectedFolder == rel || selectedFolder.hasPrefix(rel + "/") { selectedFolder = "" }
            if wasOpen, let next = recentDocuments.first { open(next) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func trashCurrentDocument() {
        guard let rel = document?.relativePath else { return }
        trash(rel)
    }

    func revealCurrentDocument() {
        guard let rel = document?.relativePath else { return }
        library.revealInFinder(rel)
    }

    func revealLibrary() {
        NSWorkspace.shared.activateFileViewerSelecting([library.rootURL])
    }

    func toggleStar(_ rel: String) {
        settings.toggleStar(rel)
    }

    // MARK: - Library location

    func chooseLibraryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder Glassine keeps your documents in. A folder inside iCloud Drive syncs to your other devices."
        panel.directoryURL = library.rootURL
        if panel.runModal() == .OK, let url = panel.url {
            setLibraryPath(url.path)
        }
    }

    func resetLibraryToDefault() {
        setLibraryPath(nil)
    }

    private func setLibraryPath(_ path: String?) {
        closeCurrentDocument()
        selection = nil
        selectedFolder = ""
        tagFilter = nil
        settings.data.libraryPath = path
        settings.data.lastOpenedDocument = nil
        settings.data.recents = [:]
        settings.data.starred = []
        settings.data.expandedFolders = []
        settings.data.caretPositions = [:]
        library = LibraryStore(customPath: path)
        bindLibrary()
        bootstrapLibrary()
    }

    // MARK: - View toggles

    func toggleGallery() {
        if document == nil { showingGallery = true; return }
        showingGallery.toggle()
    }

    /// Esc from the editor: zoom out to the mosaic.
    func escapeFromEditor() {
        showingGallery = true
    }

    func toggleReview() {
        guard document != nil else { return }
        if showingGallery {
            showingGallery = false
            reviewMode = true
            return
        }
        if !reviewMode { reviewEntryScrollFraction = GlassineTextView.current?.scrollFraction ?? 0 }
        reviewMode.toggle()
    }

    func openInReview(_ ref: DocumentRef) {
        open(ref)
        reviewEntryScrollFraction = 0
        reviewMode = true
    }

    // MARK: - Copying

    func copyCurrentDocument(asMarkdown: Bool) {
        guard let doc = document else { return }
        copy(text: doc.text, title: doc.title, asMarkdown: asMarkdown)
    }

    func copyDocument(_ ref: DocumentRef, asMarkdown: Bool) {
        if let doc = document, doc.relativePath == ref.id {
            copy(text: doc.text, title: doc.title, asMarkdown: asMarkdown)
            return
        }
        guard let text = try? FileCoordination.read(ref.url) else {
            errorMessage = "Couldn't read \(ref.title)."
            return
        }
        copy(text: text, title: ref.title, asMarkdown: asMarkdown)
    }

    private func copy(text: String, title: String, asMarkdown: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if asMarkdown {
            pb.setString(text, forType: .string)
            showNotice("Copied as Markdown")
            return
        }
        let html = MarkdownHTML.neutralDocument(title: title, body: MarkdownHTML.render(text))
        guard let data = html.data(using: .utf8),
              let attributed = NSAttributedString(html: data, options: [
                  .documentType: NSAttributedString.DocumentType.html,
                  .characterEncoding: String.Encoding.utf8.rawValue,
              ], documentAttributes: nil) else {
            pb.setString(text, forType: .string)
            showNotice("Copied as Markdown (rich text failed)")
            return
        }
        pb.declareTypes([.rtf, .html, .string], owner: nil)
        let range = NSRange(location: 0, length: attributed.length)
        if let rtf = attributed.rtf(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pb.setData(rtf, forType: .rtf)
        }
        pb.setString(html, forType: .html)
        pb.setString(attributed.string, forType: .string)
        showNotice("Copied as Rich Text")
    }

    func showNotice(_ text: String) {
        noticeWork?.cancel()
        transientNotice = text
        let work = DispatchWorkItem { [weak self] in self?.transientNotice = nil }
        noticeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    func toggleSidebar() {
        withAnimation(.spring(duration: 0.28, bounce: 0.05)) {
            settings.data.sidebarVisible.toggle()
        }
    }

    /// Help → Copy Debug Info: whatever is on screen describes itself.
    func copyDebugInfo() {
        var parts: [String] = ["Glassine \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") debug"]
        parts.append("view: \(galleryOnScreen ? "gallery" : (reviewMode ? "review" : "editor")) sidebar=\(settings.data.sidebarVisible) docs=\(library.allDocuments.count) query=\"\(searchText)\"")
        if let key = NSApp.keyWindow {
            parts.append("keyWindow firstResponder: \(key.firstResponder.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        if let nav = GalleryNavigator.current { parts.append(nav.debugDescription) }
        if let textView = GlassineTextView.current { parts.append(textView.debugDescription) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: "\n"), forType: .string)
        showNotice("Debug info copied")
    }

    func toggleTypewriter() { settings.data.typewriterMode.toggle() }
    func toggleFocus() { settings.data.focusMode.toggle() }

    func adjustFontSize(by delta: Double) {
        if reviewMode && !showingGallery {
            settings.data.reviewFontScale = min(2.0, max(0.6, (settings.data.reviewFontScale + delta * 0.08 * 1.0).rounded(toPlaces: 2)))
        } else {
            settings.data.fontSize = min(40, max(10, settings.data.fontSize + delta))
        }
    }

    func resetFontSize() {
        if reviewMode && !showingGallery {
            settings.data.reviewFontScale = 1.0
        } else {
            settings.data.fontSize = SettingsData().fontSize
        }
    }

    // MARK: - Shutdown

    func saveEverythingNow() {
        document?.close()
        settings.saveNow()
    }
}

enum WelcomeDocument {
    static let text = """
    # Welcome to Glassine

    Glassine is a quiet place to write. Everything you type is saved as you go — into a plain Markdown file inside iCloud Drive, so it's already on your other devices.

    ## A few things to try

    - Watch the caret glide as you type. Tune it under **Glassine → Settings → Caret**.
    - Press ⌘S to hide the sidebar. Press it again to bring it back. ⌘P shows every document at once; ⌘F searches everything you have written.
    - Try ⌃⌘T for typewriter scrolling and ⌃⌘F for focus mode.
    - Themes live under **View → Theme**. Duplicate one in Settings to make it yours.
    - The file's name follows the first line of the document. Change this heading and watch the sidebar.
    - Type @today, @yesterday or @tomorrow and a space. Handy for daily notes.

    ## Markdown, lightly styled

    Syntax stays visible but steps back: **bold**, *italic*, `inline code`, ~~struck~~, and [links](https://example.com).

    > Quotes get a little room to breathe.

    1. Numbered lists continue when you press Return.
    2. So do bullets.
    - [ ] Tasks too — ⌘⇧L toggles the checkbox.

    Tags like #ideas or #draft show up in the sidebar, so a note can live in more than one place.

    ---

    Write something.
    """
}

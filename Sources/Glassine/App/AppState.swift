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
    var galleryOnScreen: Bool { !showingDaily && (showingGallery || document == nil) }

    /// The Daily timeline: today's note in front, earlier days receding behind it.
    @Published var showingDaily = false

    /// ⌘F overlay. The mosaic's inline box reports its frame so the overlay can
    /// glide out of it; the value lives outside @Published because it changes on layout.
    @Published var showingSearch = false
    var searchFieldFrame: CGRect = .zero

    /// ⌘K command bar.
    @Published var showingCommandBar = false
    @Published var commandQuery = ""
    @Published var commandSelection = 0

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

    /// The theme in force: the chosen one, or the light/dark pair's half that matches the system.
    var theme: Theme {
        switch settings.data.appearanceMode {
        case .fixed: return themes.theme(id: settings.data.themeID)
        case .system: return themes.theme(id: systemIsDark ? settings.data.darkThemeID : settings.data.lightThemeID)
        }
    }

    /// What macOS is set to, independent of what this app's windows are showing.
    @Published private(set) var systemIsDark: Bool = AppState.readSystemIsDark()

    private static func readSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    /// Pick a theme from the menu: in system mode it takes the slot it belongs to.
    func chooseTheme(_ id: String) {
        switch settings.data.appearanceMode {
        case .fixed:
            settings.data.themeID = id
        case .system:
            if themes.theme(id: id).isDark { settings.data.darkThemeID = id } else { settings.data.lightThemeID = id }
        }
    }

    /// True while the writer is typing and the pointer has not moved since; the footer
    /// and the sidebar toggle step back so nothing sits in the eye line.
    @Published private(set) var quietWhileTyping = false
    var isQuiet: Bool { quietWhileTyping && !galleryOnScreen && !reviewMode && pendingPrompt == nil }

    func noteTyping() {
        guard !galleryOnScreen, !reviewMode, !quietWhileTyping else { return }
        quietWhileTyping = true
    }

    func noteMouse() {
        if quietWhileTyping { quietWhileTyping = false }
    }

    /// The ⌘/ overlay listing every shortcut.
    @Published var showingShortcuts = false
    /// Settings as an overlay on the main window, so it can never get lost behind it.
    @Published var showingSettings = false
    /// Which settings pane is up (0–3); Tab and ⇧Tab walk it around.
    @Published var settingsTab = 0
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
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            // The defaults key lags the notification by a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.systemIsDark = AppState.readSystemIsDark() }
        }
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
        // A listing is enough to open the last document and show the window; reading every
        // file for previews, tags and search happens right after, off the main thread.
        library.scanNow(readingContents: false)
        library.rescan()
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
    private struct SearchMemo {
        let query: String, tag: String?, sort: SortMode, generation: Int, liveID: String?, liveEdit: Int
        let result: [DocumentRef]
    }
    private var searchMemo: SearchMemo?

    var filteredDocuments: [DocumentRef]? {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard tagFilter != nil || !q.isEmpty else { return nil }
        if let memo = searchMemo, memo.query == q, memo.tag == tagFilter, memo.sort == settings.data.sortDocumentsBy,
           memo.generation == library.generation, memo.liveID == document?.relativePath,
           memo.liveEdit == (document?.editGeneration ?? -1) {
            return memo.result
        }
        let result = computeFilteredDocuments(query: q)
        searchMemo = SearchMemo(query: q, tag: tagFilter, sort: settings.data.sortDocumentsBy, generation: library.generation,
                                liveID: document?.relativePath, liveEdit: document?.editGeneration ?? -1, result: result)
        return result
    }

    private func computeFilteredDocuments(query q: String) -> [DocumentRef] {
        let base: [DocumentRef]
        if let tag = tagFilter {
            base = library.allDocuments.filter { $0.tags.contains(tag) }
        } else {
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

    /// ⌘F: the mosaic comes up (results filter live behind the overlay) and the
    /// search bar glides to the middle of the window.
    func focusSearch() {
        showingDaily = false
        showingCommandBar = false
        if document != nil { showingGallery = true }
        showingSearch = true
    }

    func showDaily() {
        showingSearch = false
        showingCommandBar = false
        reviewMode = false
        showingDaily = true
    }

    func toggleCommandBar() {
        showingCommandBar.toggle()
        if showingCommandBar {
            commandQuery = ""
            commandSelection = 0
            showingSearch = false
        }
    }

    // MARK: - Opening documents

    /// The card a document is being opened from, while the open animation runs.
    @Published var zoomingCard: String?

    func open(_ ref: DocumentRef, fromCard: Bool = false) {
        if fromCard, galleryOnScreen || showingDaily, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            zoomingCard = ref.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                if self?.zoomingCard == ref.id { self?.zoomingCard = nil }
            }
        }
        showingGallery = false
        showingDaily = false
        showingSearch = false
        showingCommandBar = false
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
            self.pathDidMove(old, to: new)
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

    /// Documents open with the caret at the end — where the writing continues.
    /// (Positions are still recorded, in case restoring them becomes an option.)
    func savedCaret(for relPath: String) -> Int? {
        nil
    }

    // MARK: - Undo (the library kind)

    /// File operations register their inverses here; ⌘Z falls back to this
    /// stack whenever the focused text has no edit left to take back.
    let libraryUndo = UndoManager()

    /// A relative path that stays correct while an undo entry waits around:
    /// renames and moves (automatic first-line renames included) update every
    /// live box, so undoing an old action finds the file where it is now.
    final class PathBox {
        var rel: String
        init(_ rel: String) { self.rel = rel }
    }
    private let trackedPaths = NSHashTable<PathBox>.weakObjects()

    private func track(_ rel: String) -> PathBox {
        let box = PathBox(rel)
        trackedPaths.add(box)
        return box
    }

    private func pathDidMove(_ old: String, to new: String) {
        guard old != new else { return }
        for box in trackedPaths.allObjects {
            if box.rel == old {
                box.rel = new
            } else if box.rel.hasPrefix(old + "/") {
                box.rel = new + box.rel.dropFirst(old.count)
            }
        }
    }

    /// A fresh file or folder was just made; undoing sends it to the Trash.
    private func registerCreationUndo(of rel: String, label: String) {
        let box = track(rel)
        libraryUndo.registerUndo(withTarget: self) { s in
            s.undoableTrash(box, label: label)
        }
        libraryUndo.setActionName(label)
    }

    /// Trashes a file or folder (always the macOS Trash, never a hard delete)
    /// and registers the restore as its inverse.
    private func undoableTrash(_ box: PathBox, label: String) {
        let rel = box.rel
        let wasOpen = document?.relativePath == rel || (document?.relativePath.hasPrefix(rel + "/") ?? false)
        do {
            if wasOpen {
                document?.saveNow()
                document = nil
                selection = nil
            }
            let trashedURL = try library.trash(rel)
            settings.forgetPath(rel)
            if selectedFolder == rel || selectedFolder.hasPrefix(rel + "/") { selectedFolder = "" }
            if wasOpen, let next = recentDocuments.first { open(next) }
            if let trashedURL {
                libraryUndo.registerUndo(withTarget: self) { s in
                    s.undoableRestore(from: trashedURL, to: box, label: label, reopen: wasOpen)
                }
                libraryUndo.setActionName(label)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undoableRestore(from trashedURL: URL, to box: PathBox, label: String, reopen: Bool) {
        do {
            let newRel = try library.restore(from: trashedURL, toRelativePath: box.rel)
            box.rel = newRel
            libraryUndo.registerUndo(withTarget: self) { s in
                s.undoableTrash(box, label: label)
            }
            libraryUndo.setActionName(label)
            if reopen, library.document(withID: newRel) != nil {
                open(relativePath: newRel)
                reviewMode = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Review-mode checkbox clicks come through here so they land on the undo
    /// stack; the editor's own clicks ride the text view's undo instead.
    @discardableResult
    func toggleTask(ordinal: Int, checked: Bool) -> Bool {
        guard let doc = document, let landed = doc.setTask(ordinal: ordinal, checked: checked) else { return false }
        let box = track(doc.relativePath)
        libraryUndo.registerUndo(withTarget: self) { s in
            if s.document?.relativePath != box.rel { s.open(relativePath: box.rel) }
            s.toggleTask(ordinal: landed, checked: !checked)
        }
        libraryUndo.setActionName(checked ? "Check Off Task" : "Uncheck Task")
        return true
    }

    // MARK: - Creating

    func newDocument(in folder: String? = nil) {
        let target = folder ?? selectedFolder
        do {
            let ref = try library.createDocument(in: target)
            open(ref)
            reviewMode = false
            registerCreationUndo(of: ref.id, label: "New Document")
            if !target.isEmpty { settings.setExpanded(target, true) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// ⌘⇧D: today's note in the Daily folder, made on first use.
    func openTodaysNote() {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy"
        let title = formatter.string(from: Date())
        let folder = "Daily"
        let rel = folder + "/" + title.sanitizedFileStem + ".md"
        if let existing = library.document(withID: rel) {
            open(existing)
            reviewMode = false
            return
        }
        do {
            if !FileManager.default.fileExists(atPath: library.url(forRelativePath: folder).path) {
                _ = try library.createFolder(named: folder, in: "")
            }
            let contents = "# \(title)\n\n"
            let ref = try library.createDocument(in: folder, stem: title.sanitizedFileStem, contents: contents)
            open(ref)
            reviewMode = false
            registerCreationUndo(of: ref.id, label: "Today's Note")
            settings.setExpanded(folder, true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// File → Export as PDF…: the document in the current Review style, paginated.
    func exportPDF() {
        guard let doc = document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = doc.title.sanitizedFileStem + ".pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let html = ReviewHTML.document(markdown: doc.text, title: doc.title, style: settings.data.reviewStyle,
                                       theme: theme, scale: 1.0, centerHeadings: settings.data.centerHeadings, forExport: true)
        PDFExporter.export(html: html, baseURL: doc.url.deletingLastPathComponent(), to: url) { [weak self] error in
            if let error {
                self?.errorMessage = "Couldn't export the PDF: \(error.localizedDescription)"
            } else {
                self?.showNotice("Exported PDF")
            }
        }
    }

    func promptNewFolder(in parent: String? = nil) {
        pendingPrompt = .newFolder(parent: parent ?? selectedFolder)
    }

    func createFolder(named name: String, in parent: String) {
        do {
            let rel = try library.createFolder(named: name, in: parent)
            registerCreationUndo(of: rel, label: "New Folder")
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
        let oldStem = isFolder
            ? URL(fileURLWithPath: rel).lastPathComponent
            : URL(fileURLWithPath: rel).deletingPathExtension().lastPathComponent
        do {
            let resultRel: String
            if let doc = document, doc.relativePath == rel {
                try doc.rename(to: newName)
                resultRel = doc.relativePath
            } else {
                let newRel = try library.rename(rel, to: newName)
                settings.renamePath(rel, to: newRel)
                pathDidMove(rel, to: newRel)
                if isFolder, let doc = document, doc.relativePath.hasPrefix(rel + "/") {
                    let moved = newRel + doc.relativePath.dropFirst(rel.count)
                    doc.didMove(to: moved)
                    selection = moved
                    settings.data.lastOpenedDocument = moved
                }
                if selectedFolder == rel { selectedFolder = newRel }
                resultRel = newRel
            }
            if resultRel != rel {
                let box = track(resultRel)
                libraryUndo.registerUndo(withTarget: self) { s in
                    s.rename(box.rel, to: oldStem, isFolder: isFolder)
                }
                libraryUndo.setActionName("Rename")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(_ rel: String, toFolder folder: String) {
        let oldFolder = rel.contains("/") ? String(rel[..<rel.lastIndex(of: "/")!]) : ""
        do {
            let wasOpen = document?.relativePath == rel
            if wasOpen { document?.saveNow() }
            let newRel = try library.move(rel, toFolder: folder)
            settings.renamePath(rel, to: newRel)
            pathDidMove(rel, to: newRel)
            if wasOpen {
                document?.didMove(to: newRel)
                selection = newRel
                selectedFolder = folder
                settings.data.lastOpenedDocument = newRel
            }
            if !folder.isEmpty { settings.setExpanded(folder, true) }
            if newRel != rel {
                let box = track(newRel)
                libraryUndo.registerUndo(withTarget: self) { s in
                    s.move(box.rel, toFolder: oldFolder)
                }
                libraryUndo.setActionName("Move")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func duplicate(_ rel: String) {
        do {
            if document?.relativePath == rel { document?.saveNow() }
            let newRel = try library.duplicate(rel)
            open(relativePath: newRel)
            registerCreationUndo(of: newRel, label: "Duplicate")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func trash(_ rel: String) {
        undoableTrash(track(rel), label: "Move to Trash")
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
        if showingDaily { showingDaily = false; showingGallery = true; return }
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

    // MARK: - Command bar

    struct AppCommand: Identifiable {
        let id: String
        let title: String
        var keys: String? = nil
        let action: () -> Void
    }

    /// What ⌘K offers depends on where you are: Review styles in Review, sorting in
    /// the mosaic, writing modes in the editor. Themes ride along everywhere.
    var availableCommands: [AppCommand] {
        var cmds: [AppCommand] = []
        func add(_ id: String, _ title: String, keys: String? = nil, _ action: @escaping () -> Void) {
            cmds.append(AppCommand(id: id, title: title, keys: keys, action: action))
        }
        let inReview = reviewMode && !galleryOnScreen && !showingDaily && document != nil

        if inReview {
            for s in ReviewStyle.allCases {
                let mark = settings.data.reviewStyle == s ? "  ✓" : ""
                add("style-\(s.rawValue)", "Review style: \(s.label)\(mark)") { [weak self] in self?.settings.data.reviewStyle = s }
            }
            add("leave-review", "Leave Review", keys: "⌘↩") { [weak self] in self?.toggleReview() }
            add("copy-md", "Copy as Markdown", keys: "⌘⇧C") { [weak self] in self?.copyCurrentDocument(asMarkdown: true) }
            add("copy-rtf", "Copy as Rich Text", keys: "⌥⌘C") { [weak self] in self?.copyCurrentDocument(asMarkdown: false) }
            add("export-pdf", "Export as PDF…", keys: "⌘⇧E") { [weak self] in self?.exportPDF() }
            add("all-docs", "All Documents", keys: "⌘P") { [weak self] in self?.toggleGallery() }
        } else if galleryOnScreen || showingDaily {
            add("new-doc", "New Document", keys: "⌘N") { [weak self] in self?.newDocument() }
            add("today", "Today's Note", keys: "⌥⌘D") { [weak self] in self?.openTodaysNote() }
            add("daily", showingDaily ? "All Documents" : "Daily Timeline", keys: showingDaily ? "⌘P" : "⌘D") { [weak self] in
                guard let self else { return }
                if self.showingDaily { self.toggleGallery() } else { self.showDaily() }
            }
            for mode in SortMode.allCases {
                let mark = settings.data.sortDocumentsBy == mode ? "  ✓" : ""
                add("sort-\(mode.rawValue)", "Sort by \(mode.label.lowercased())\(mark)") { [weak self] in self?.settings.data.sortDocumentsBy = mode }
            }
            add("search", "Search", keys: "⌘F") { [weak self] in self?.focusSearch() }
            if document != nil {
                add("back", "Back to Document", keys: "Esc") { [weak self] in
                    self?.showingDaily = false
                    self?.showingGallery = false
                }
            }
        } else {
            add("all-docs", "All Documents", keys: "⌘P") { [weak self] in self?.toggleGallery() }
            add("review", "Review", keys: "⌘↩") { [weak self] in self?.toggleReview() }
            add("today", "Today's Note", keys: "⌥⌘D") { [weak self] in self?.openTodaysNote() }
            add("daily", "Daily Timeline", keys: "⌘D") { [weak self] in self?.showDaily() }
            add("new-doc", "New Document", keys: "⌘N") { [weak self] in self?.newDocument() }
            add("typewriter", "\(settings.data.typewriterMode ? "Turn off" : "Turn on") typewriter scrolling", keys: "⌃⌘T") { [weak self] in self?.toggleTypewriter() }
            add("focus", "\(settings.data.focusMode ? "Turn off" : "Turn on") focus mode", keys: "⌃⌘F") { [weak self] in self?.toggleFocus() }
            add("copy-md", "Copy as Markdown", keys: "⌘⇧C") { [weak self] in self?.copyCurrentDocument(asMarkdown: true) }
            add("copy-rtf", "Copy as Rich Text", keys: "⌥⌘C") { [weak self] in self?.copyCurrentDocument(asMarkdown: false) }
            add("export-pdf", "Export as PDF…", keys: "⌘⇧E") { [weak self] in self?.exportPDF() }
            add("search", "Search", keys: "⌘F") { [weak self] in self?.focusSearch() }
        }

        for t in themes.all {
            let mark = theme.id == t.id ? "  ✓" : ""
            add("theme-\(t.id)", "Theme: \(t.name)\(mark)") { [weak self] in self?.chooseTheme(t.id) }
        }
        add("settings", "Settings…", keys: "⌘,") { [weak self] in self?.showingSettings = true }
        add("shortcuts", "Shortcuts", keys: "⌘/") { [weak self] in self?.showingShortcuts = true }
        return cmds
    }

    var filteredCommands: [AppCommand] {
        let q = commandQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return availableCommands }
        let needle = LibraryStore.searchable(q)
        return availableCommands.filter { LibraryStore.searchable($0.title).contains(needle) }
    }

    func runCommand(at index: Int) {
        let list = filteredCommands
        guard index >= 0, index < list.count else { showingCommandBar = false; return }
        let command = list[index]
        showingCommandBar = false
        commandQuery = ""
        commandSelection = 0
        DispatchQueue.main.async { command.action() }
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

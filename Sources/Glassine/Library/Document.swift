import AppKit
import Combine

/// One open Markdown file. Owns autosave, external-change detection and
/// first-line-based renaming.
final class DocumentModel: ObservableObject, Identifiable {
    enum SaveState: Equatable { case clean, dirty, saving, saved, failed(String) }

    let id = UUID()
    @Published private(set) var url: URL
    @Published private(set) var relativePath: String
    @Published private(set) var text: String
    @Published private(set) var saveState: SaveState = .clean
    @Published private(set) var wordCount = 0
    @Published private(set) var characterCount = 0
    @Published private(set) var readingMinutes = 0.0
    @Published private(set) var lastSavedAt: Date?

    let undoManager = UndoManager()
    /// The file could not be read when the page opened. The page is shown
    /// empty and kept read-only, and nothing is ever written over the file
    /// from here — a keystroke on a page that is not the file would have
    /// saved a blank page over it.
    let loadError: String?
    /// Nothing typed on this page may be taken: it is still on its way down
    /// from iCloud, or it could not be read.
    var isReadOnly: Bool { isLoading || loadError != nil }
    /// The file is still on its way down from iCloud; the page fills in when
    /// it lands. Nothing typed meanwhile is kept, so nothing is lost under it.
    @Published private(set) var isLoading = false
    /// A file from outside the library — opened from Finder, dropped on the
    /// Dock icon, or File → Open… — edited and saved where it is. Its
    /// `relativePath` is its absolute path, which no library id can be; it is
    /// never renamed after its first line, never listed, never remembered.
    let isLoose: Bool

    var title: String { url.deletingPathExtension().lastPathComponent }
    var isDirty: Bool { editGeneration != savedGeneration }

    /// Called after the file is renamed on disk (old relative path, new relative path).
    var onRenamed: ((String, String) -> Void)?
    /// Called when the file disappeared while open and nothing was pending.
    var onVanished: (() -> Void)?
    /// Called when the file content was replaced from disk.
    var onReloaded: (() -> Void)?
    /// Called when a file that was still downloading has arrived.
    var onLoaded: (() -> Void)?

    private unowned let library: LibraryStore
    private let settings: AppSettings

    private(set) var editGeneration = 0
    private var savedGeneration = 0
    private var knownModificationDate: Date?
    private var lastSavedText: String
    private var titleAtLoad: String
    private var lastFirstLine: String

    /// The last texts saved from here, as blob ids. A version of ours
    /// arriving from outside is an echo — a stale answer somewhere on the
    /// way — not another Mac's work, and is not kept as one.
    private var recentSaves: [String] = []
    private let saveDebouncer = Debouncer(delay: 0.5)
    private let renameDebouncer = Debouncer(delay: 4.0)
    private let statsDebouncer = Debouncer(delay: 0.25)
    /// Checked-off tasks waiting to sink, by their line text.
    private var pendingSinks: [String: DispatchWorkItem] = [:]
    private var maxIntervalTimer: Timer?
    private var saveInFlight = false
    private var saveAgain = false
    /// The first-line rename is on its way through the disk; saves wait for
    /// it, so no write lands at the old name once the file has moved.
    private var renameInFlight = false
    /// A read of the file as it is on disk is on its way back.
    private var checkInFlight = false
    /// `close()` was called: the write in flight is the last one, and the
    /// first-line rename follows it.
    private var closing = false
    private var closeRetries = 0
    private var savedIndicatorWork: DispatchWorkItem?

    private static let saveQueue = DispatchQueue(label: "glassine.document.save", qos: .userInitiated)
    private static let statsQueue = DispatchQueue(label: "glassine.document.stats", qos: .utility)

    init(url: URL, library: LibraryStore, settings: AppSettings) {
        self.url = url
        self.library = library
        self.settings = settings
        let inside = url.standardizedFileURL.path.hasPrefix(library.rootURL.standardizedFileURL.path + "/")
        self.isLoose = !inside
        self.relativePath = inside ? library.relativePath(for: url) : url.standardizedFileURL.path
        var loaded = ""
        var err: String?
        var pending = false
        if FileCoordination.isMaterialized(url) {
            // The file is here: a plain read, over in a moment. (A coordinated
            // read is a round trip to filecoordinationd and every presenter
            // of the file, which is a wait of any length — not one to take on
            // the main thread for a page that is about to come up.)
            do {
                loaded = try FileCoordination.readPlain(url)
            } catch {
                err = error.localizedDescription
            }
        } else {
            // Not down from iCloud yet: ask for it, and read it when it lands,
            // off the main thread. The page opens empty and fills in.
            pending = true
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        text = loaded
        lastSavedText = loaded
        loadError = err
        isLoading = pending
        knownModificationDate = url.contentModificationDate
        titleAtLoad = loaded.derivedMarkdownTitle
        lastFirstLine = titleAtLoad
        recomputeStatsAtOpen()
        if pending { loadWhenDownloaded() }
    }

    /// The coordinated read waits for iCloud to finish; the page takes the
    /// text when it arrives, unless it has been closed or moved meanwhile.
    private func loadWhenDownloaded() {
        let target = url
        FileCoordination.read(target) { [weak self] result in
            guard let self, isLoading, target == url else { return }
            isLoading = false
            guard case .success(let loaded) = result else { return }
            text = loaded
            lastSavedText = loaded
            editGeneration = 0
            savedGeneration = 0
            knownModificationDate = url.contentModificationDate
            titleAtLoad = loaded.derivedMarkdownTitle
            lastFirstLine = titleAtLoad
            recomputeStatsAtOpen()
            onLoaded?()
        }
    }

    /// A short document is counted before the first frame; a long one is
    /// counted off the main thread, so opening it never waits on the walk
    /// through its words. The counter ticks to the number a beat later.
    private func recomputeStatsAtOpen() {
        if text.utf16.count > 24_000 {
            characterCount = (text as NSString).length
            recomputeStatsInBackground()
        } else {
            recomputeStats()
        }
    }

    deinit {
        maxIntervalTimer?.invalidate()
    }

    // MARK: - Editing

    /// The editor pushes the whole string after each change. Strings are
    /// copy-on-write so this is cheap until mutated.
    /// A task line: optional quote markers, a list marker, then `[ ]` or `[x]` and a space.
    /// Group 1 is the character inside the brackets.
    private static let taskLineRx = try! NSRegularExpression(
        pattern: "^[ \\t]*(?:>[ \\t]?)*[ \\t]*(?:[-*+]|\\d{1,9}[.)])[ \\t]+\\[([ xX])\\][ \\t]+")

    /// Checks or unchecks the n-th task item, counted the way Review renders them
    /// (top to bottom, skipping fenced code). With the tidy-list setting on, a
    /// checked task sinks after a moment and an unchecked one rises at once.
    /// Returns the item's new line text, or nil when there is no such item or it
    /// is not in the state the caller expected.
    @discardableResult
    func setTask(ordinal: Int, checked: Bool) -> String? {
        var lines = text.components(separatedBy: "\n")
        var inFence = false
        var seen = 0
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            let ns = line as NSString
            guard let m = DocumentModel.taskLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) else { continue }
            if seen == ordinal {
                let box = m.range(at: 1)
                let wasChecked = ns.substring(with: box).lowercased() == "x"
                guard wasChecked != checked else { return nil }
                lines[i] = ns.replacingCharacters(in: box, with: checked ? "x" : " ")
                let newLine = lines[i]
                if settings.data.moveCompletedTasks {
                    if checked {
                        scheduleSink(of: newLine, near: i)
                    } else {
                        pendingSinks.removeValue(forKey: ns.replacingCharacters(in: box, with: "x"))?.cancel()
                        if let moved = TaskReorder.afterToggle(lines: lines, at: i) { lines = moved.lines }
                    }
                }
                textDidChange(lines.joined(separator: "\n"))
                // The editor is told, as it is of a change from the disk:
                // with the page beside it, the editor is still up with the
                // old line, and its next keystroke would have put the old
                // box back over the tick.
                onReloaded?()
                return newLine
            }
            seen += 1
        }
        return nil
    }

    /// A task you check off waits a moment before sinking, so the check itself
    /// registers first. If the line is edited or unchecked meanwhile, it stays.
    private func scheduleSink(of lineText: String, near line: Int) {
        pendingSinks[lineText]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSinks[lineText] = nil
            guard self.settings.data.moveCompletedTasks else { return }
            let lines = self.text.components(separatedBy: "\n")
            let index: Int
            if line < lines.count, lines[line] == lineText { index = line }
            else if let found = lines.firstIndex(of: lineText) { index = found }
            else { return }
            guard let moved = TaskReorder.afterToggle(lines: lines, at: index) else { return }
            self.textDidChange(moved.lines.joined(separator: "\n"))
            self.onReloaded?()
        }
        pendingSinks[lineText] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GlassineTextView.sinkDelay, execute: work)
    }

    /// Review's ordinal for the task whose line reads `text`, wherever it is now.
    func ordinal(ofTaskLine text: String) -> Int? {
        let lines = self.text.components(separatedBy: "\n")
        guard let i = lines.firstIndex(of: text) else { return nil }
        return TaskReorder.ordinal(ofTaskAt: i, in: lines)
    }

    func textDidChange(_ newText: String) {
        guard newText != text, !isReadOnly else { return }
        text = newText
        editGeneration += 1
        // Set only when it changes: a published value set to itself still
        // has every view watching the document redo its body.
        switch saveState {
        case .saving, .dirty: break
        default: saveState = .dirty
        }
        scheduleAutosave()
        statsDebouncer.call { [weak self] in self?.recomputeStatsInBackground() }

        if settings.data.nameFilesFromFirstLine {
            let firstLine = newText.derivedMarkdownTitle
            if firstLine != lastFirstLine {
                lastFirstLine = firstLine
                renameDebouncer.call { [weak self] in self?.renameToMatchTitleIfAppropriate() }
            }
        }
    }

    private func scheduleAutosave() {
        saveDebouncer.call { [weak self] in self?.save() }
        // Guarantee a save at least every 4 seconds while typing continuously.
        if maxIntervalTimer == nil {
            let timer = Timer(timeInterval: 4.0, repeats: false) { [weak self] _ in
                self?.maxIntervalTimer = nil
                self?.save()
            }
            RunLoop.main.add(timer, forMode: .common)
            maxIntervalTimer = timer
        }
    }

    // MARK: - Saving

    func save() {
        guard isDirty, loadError == nil else { return }
        if saveInFlight || renameInFlight { saveAgain = true; return }
        saveInFlight = true
        saveState = .saving
        let snapshot = text
        let generation = editGeneration
        let target = url
        // The model is held until the write lands — a document closed with a
        // write in flight still finishes its save and the rename after it.
        DocumentModel.saveQueue.async {
            var failure: String?
            do {
                try FileCoordination.write(snapshot, to: target)
            } catch {
                failure = error.localizedDescription
            }
            let modDate = target.contentModificationDate
            DispatchQueue.main.async {
                self.saveInFlight = false
                if let failure {
                    self.saveState = .failed(failure)
                } else {
                    self.savedGeneration = max(self.savedGeneration, generation)
                    self.lastSavedText = snapshot
                    self.remember(saved: snapshot)
                    self.knownModificationDate = modDate
                    self.lastSavedAt = Date()
                    self.writes += 1
                    if target != self.url {
                        // The file was renamed or moved while this write was in flight, so the
                        // write recreated the old path. Fold it back into the current file.
                        self.foldBack(snapshot, from: target)
                    }
                    self.saveState = self.isDirty ? .dirty : .saved
                    NotificationCenter.default.post(name: .glassineDocumentSaved, object: nil)
                    self.savedIndicatorWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, case .saved = self.saveState else { return }
                        self.saveState = .clean
                    }
                    self.savedIndicatorWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
                }
                self.saveAgain = false
                if self.isDirty {
                    if !self.closing {
                        self.scheduleAutosave()
                    } else if failure == nil {
                        self.save()   // typed into while the write was out: straight back
                    } else if self.closeRetries < 5 {
                        self.closeRetries += 1   // a closed page tries a few more times, then rests
                        self.scheduleAutosave()
                    } else {
                        self.closing = false
                    }
                } else if self.closing {
                    self.finishClosing()
                }
            }
        }
    }

    /// A write that landed at a path the file has since left: the text goes
    /// to where the file is now, and the stray copy goes — off the main thread.
    private func foldBack(_ snapshot: String, from stale: URL) {
        let current = url
        FileCoordination.queue.async { [weak self] in
            try? FileCoordination.write(snapshot, to: current)
            let modDate = current.contentModificationDate
            if let left = try? FileCoordination.read(stale), left == snapshot {
                try? FileManager.default.removeItem(at: stale)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if self.url == current { self.knownModificationDate = modDate }
                self.library.rescan()
            }
        }
    }

    /// A save that waits for the disk. For the moments that cannot go on
    /// without it: quitting, and a file about to be moved or trashed. (A page
    /// going off screen is not one of those — see `close()`.)
    func saveNow() {
        saveDebouncer.cancel()
        guard isDirty, loadError == nil else { return }
        // A write already on its way to the disk lands first, so the text
        // written here — the newer — is the one the file is left with.
        if saveInFlight { DocumentModel.saveQueue.sync {} }
        let generation = editGeneration
        do {
            try FileCoordination.write(text, to: url)
            savedGeneration = generation
            lastSavedText = text
            remember(saved: text)
            knownModificationDate = url.contentModificationDate
            lastSavedAt = Date()
            writes += 1
            saveState = .clean
            NotificationCenter.default.post(name: .glassineDocumentSaved, object: nil)
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    /// The page is going off screen: what is unsaved goes to the disk, and
    /// the first-line rename follows — neither with the main thread waiting.
    /// The model stays alive until both are done.
    func close() {
        renameDebouncer.cancel()
        saveDebouncer.cancel()
        maxIntervalTimer?.invalidate()
        maxIntervalTimer = nil
        closing = true
        if isDirty {
            save()
        } else if !saveInFlight {
            finishClosing()
        }
        // Otherwise the write in flight calls finishClosing() as it lands.
    }

    private func finishClosing() {
        guard closing else { return }
        closing = false
        renameToMatchTitleIfAppropriate(force: true)
    }

    /// Everything to the disk before the process goes: whatever the files
    /// queue still holds, then the write, then the rename, all waited for.
    func closeNow() {
        closing = false
        renameDebouncer.cancel()
        DocumentModel.saveQueue.sync {}
        FileCoordination.queue.sync {}
        saveNow()
        if !renameInFlight { renameToMatchTitleIfAppropriate(force: true, waiting: true) }
    }

    // MARK: - External changes

    /// Called when the library changed underneath the app (a file event, a
    /// sync round, the app coming to the front, a slow poll). Reloads if the
    /// file changed on disk and we have no unsaved edits; closes if it
    /// vanished. The date is checked here; the file itself is read off the
    /// main thread, and what came back is weighed against the document as it
    /// is by then.
    func checkExternalChanges() {
        guard !saveInFlight, !renameInFlight, !checkInFlight, !isLoading else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            if !isDirty { onVanished?() }
            return
        }
        guard let mod = url.contentModificationDate else { return }
        // iCloud rounds timestamps and touches files after upload, so a date change alone
        // proves nothing. Compare content before believing anything changed.
        if let known = knownModificationDate, abs(mod.timeIntervalSince(known)) < 1.0 { return }
        checkInFlight = true
        let target = url
        let edits = editGeneration
        let saves = savedGeneration
        FileCoordination.read(target) { [weak self] result in
            guard let self else { return }
            checkInFlight = false
            // A save or an edit since the read began makes it a reading of a
            // file that is no longer the one on screen; the next event asks again.
            guard case .success(let onDisk) = result, target == url, !saveInFlight, !renameInFlight,
                  editGeneration == edits, savedGeneration == saves else { return }
            knownModificationDate = mod
            apply(onDisk: onDisk)
        }
    }

    /// The file as it is on disk, against the document as it is now.
    private func apply(onDisk: String) {
        if onDisk == lastSavedText || onDisk == text { return }   // our own write echoing back
        let echo = recentSaves.contains(GitBlob.sha(of: Data(onDisk.utf8)))

        guard !isDirty else {
            // Someone else wrote while we have unsaved edits. Ours win, theirs
            // is kept beside it — unless theirs is an earlier text of ours.
            if !echo {
                let copy = library.uniqueURL(in: url.deletingLastPathComponent(),
                                             stem: title + " (conflict)", ext: url.pathExtension)
                FileCoordination.write(onDisk, to: copy) { _ in }
            }
            lastSavedText = onDisk
            scheduleAutosave()
            return
        }
        if echo {
            // An earlier text of ours came back over the file. What is here
            // is the newer; it goes back over that.
            lastSavedText = onDisk
            editGeneration += 1
            scheduleAutosave()
            return
        }
        text = onDisk
        lastSavedText = onDisk
        editGeneration += 1
        savedGeneration = editGeneration
        titleAtLoad = onDisk.derivedMarkdownTitle
        lastFirstLine = titleAtLoad
        recomputeStatsAtOpen()
        onReloaded?()
    }

    private func remember(saved text: String) {
        let id = GitBlob.sha(of: Data(text.utf8))
        recentSaves.removeAll { $0 == id }
        recentSaves.append(id)
        if recentSaves.count > 64 { recentSaves.removeFirst() }
    }

    // MARK: - Renaming

    private var isAutoNamed: Bool {
        // A file from elsewhere keeps the name it came with.
        if isLoose { return false }
        // A day's note is its date. Whatever its first line becomes, the file
        // keeps the name the Daily view and ⌥⌘D look for.
        if DailyNotes.isDailyNote(relativePath: relativePath) { return false }
        let stem = title
        if stem == titleAtLoad { return true }
        return stem.range(of: "^Untitled( \\d+)?$", options: .regularExpression) != nil
    }

    /// The file takes its first line as its name. The move goes through the
    /// disk off the main thread, with saves held back until it is done;
    /// `waiting` is for quitting, when there is no later.
    private func renameToMatchTitleIfAppropriate(force: Bool = false, waiting: Bool = false) {
        guard settings.data.nameFilesFromFirstLine, isAutoNamed, !isLoading, !renameInFlight else { return }
        let desired = text.derivedMarkdownTitle.sanitizedFileStem
        guard !desired.isEmpty, desired != title else { return }
        if saveInFlight && !force {
            // Never move the file underneath a write; try again shortly.
            renameDebouncer.call { [weak self] in self?.renameToMatchTitleIfAppropriate() }
            return
        }
        let oldRel = relativePath
        let oldURL = url
        if waiting {
            if let newRel = try? library.rename(oldRel, to: desired) { moved(from: oldRel, to: newRel) }
            return
        }
        renameInFlight = true
        let writesBefore = writes
        library.rename(oldRel, to: desired) { [weak self] newRel in
            guard let self else { return }
            renameInFlight = false
            if let newRel {
                moved(from: oldRel, to: newRel)
                // A write that could not wait (a file about to be trashed, say)
                // landed at the old name while the move was under way: the text
                // goes to the new one, and the stray copy goes.
                if writes != writesBefore { foldBack(text, from: oldURL) }
            }
            // A save held back by the move goes now; if the page is closing,
            // that save's landing finishes the close. Nothing to save: done.
            saveAgain = false
            if isDirty { save() } else { closing = false }
        }
    }

    /// Writes that have landed, counted, so a rename knows whether one
    /// happened while it was under way.
    private var writes = 0

    private func moved(from oldRel: String, to newRel: String) {
        url = library.url(forRelativePath: newRel)
        relativePath = newRel
        titleAtLoad = text.derivedMarkdownTitle
        knownModificationDate = url.contentModificationDate
        onRenamed?(oldRel, newRel)
    }

    /// Manual rename from the sidebar.
    func rename(to newStem: String) throws {
        let oldRel = relativePath
        let newRel = try library.rename(oldRel, to: newStem)
        url = library.url(forRelativePath: newRel)
        relativePath = newRel
        titleAtLoad = "\u{0}" // pins the manual name until the first line matches it again
        knownModificationDate = url.contentModificationDate
        onRenamed?(oldRel, newRel)
    }

    /// The page's relative links as they read from its new folder (see
    /// AppState.repointLinks); the editor is told, as of a change from the disk.
    func repointLinks(from oldRel: String, to newRel: String) {
        guard !isReadOnly, let moved = RelativeLinks.rewrite(text, from: oldRel, to: newRel) else { return }
        textDidChange(moved)
        onReloaded?()
    }

    func didMove(to newRel: String) {
        url = library.url(forRelativePath: newRel)
        relativePath = newRel
        knownModificationDate = url.contentModificationDate
    }

    // MARK: - Stats

    private func recomputeStats() {
        let (chars, words) = DocumentModel.stats(of: text)
        characterCount = chars
        wordCount = words
        readingMinutes = Double(words) / 225.0
    }

    /// Counting words walks the whole text; while typing that happens off the main
    /// thread so long documents never make a keystroke wait.
    private func recomputeStatsInBackground() {
        let snapshot = text
        let generation = editGeneration
        DocumentModel.statsQueue.async { [weak self] in
            let (chars, words) = DocumentModel.stats(of: snapshot)
            DispatchQueue.main.async {
                guard let self, self.editGeneration == generation else { return }
                self.characterCount = chars
                self.wordCount = words
                self.readingMinutes = Double(words) / 225.0
            }
        }
    }

    static func stats(of text: String) -> (characters: Int, words: Int) {
        let ns = text as NSString
        var words = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        return (ns.length, words)
    }
}

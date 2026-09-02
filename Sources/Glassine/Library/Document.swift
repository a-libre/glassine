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
    let loadError: String?

    var title: String { url.deletingPathExtension().lastPathComponent }
    var isDirty: Bool { editGeneration != savedGeneration }

    /// Called after the file is renamed on disk (old relative path, new relative path).
    var onRenamed: ((String, String) -> Void)?
    /// Called when the file disappeared while open and nothing was pending.
    var onVanished: (() -> Void)?
    /// Called when the file content was replaced from disk.
    var onReloaded: (() -> Void)?

    private unowned let library: LibraryStore
    private let settings: AppSettings

    private(set) var editGeneration = 0
    private var savedGeneration = 0
    private var knownModificationDate: Date?
    private var lastSavedText: String
    private var titleAtLoad: String
    private var lastFirstLine: String

    private let saveDebouncer = Debouncer(delay: 0.5)
    private let renameDebouncer = Debouncer(delay: 4.0)
    private let statsDebouncer = Debouncer(delay: 0.25)
    private var maxIntervalTimer: Timer?
    private var saveInFlight = false
    private var saveAgain = false
    private var savedIndicatorWork: DispatchWorkItem?

    private static let saveQueue = DispatchQueue(label: "glassine.document.save", qos: .userInitiated)
    private static let statsQueue = DispatchQueue(label: "glassine.document.stats", qos: .utility)

    init(url: URL, library: LibraryStore, settings: AppSettings) {
        self.url = url
        self.library = library
        self.settings = settings
        self.relativePath = library.relativePath(for: url)
        var loaded = ""
        var err: String?
        do {
            loaded = try FileCoordination.read(url)
        } catch {
            err = error.localizedDescription
        }
        text = loaded
        lastSavedText = loaded
        loadError = err
        knownModificationDate = url.contentModificationDate
        titleAtLoad = loaded.derivedMarkdownTitle
        lastFirstLine = titleAtLoad
        recomputeStats()
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
    /// (top to bottom, skipping fenced code), and lets a finished task sink when
    /// that setting is on. Returns the item's ordinal afterwards, or nil when there
    /// is no such item or it is not in the state the caller expected.
    @discardableResult
    func setTask(ordinal: Int, checked: Bool) -> Int? {
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
                var landed = i
                if settings.data.moveCompletedTasks, let moved = TaskReorder.afterToggle(lines: lines, at: i) {
                    lines = moved.lines
                    landed = moved.movedTo
                }
                textDidChange(lines.joined(separator: "\n"))
                return TaskReorder.ordinal(ofTaskAt: landed, in: lines) ?? ordinal
            }
            seen += 1
        }
        return nil
    }

    func textDidChange(_ newText: String) {
        guard newText != text else { return }
        text = newText
        editGeneration += 1
        if case .saving = saveState {} else { saveState = .dirty }
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
            maxIntervalTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
                self?.maxIntervalTimer = nil
                self?.save()
            }
            RunLoop.main.add(maxIntervalTimer!, forMode: .common)
        }
    }

    // MARK: - Saving

    func save() {
        guard isDirty else { return }
        if saveInFlight { saveAgain = true; return }
        saveInFlight = true
        saveState = .saving
        let snapshot = text
        let generation = editGeneration
        let target = url
        DocumentModel.saveQueue.async { [weak self] in
            var failure: String?
            do {
                try FileCoordination.write(snapshot, to: target)
            } catch {
                failure = error.localizedDescription
            }
            let modDate = target.contentModificationDate
            DispatchQueue.main.async {
                guard let self else { return }
                self.saveInFlight = false
                if let failure {
                    self.saveState = .failed(failure)
                } else {
                    self.savedGeneration = max(self.savedGeneration, generation)
                    self.lastSavedText = snapshot
                    self.knownModificationDate = modDate
                    self.lastSavedAt = Date()
                    if target != self.url {
                        // The file was renamed or moved while this write was in flight, so the
                        // write recreated the old path. Fold it back into the current file.
                        try? FileCoordination.write(snapshot, to: self.url)
                        self.knownModificationDate = self.url.contentModificationDate
                        if let stale = try? FileCoordination.read(target), stale == snapshot {
                            try? FileManager.default.removeItem(at: target)
                        }
                        self.library.rescan()
                    }
                    self.saveState = self.isDirty ? .dirty : .saved
                    self.savedIndicatorWork?.cancel()
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, case .saved = self.saveState else { return }
                        self.saveState = .clean
                    }
                    self.savedIndicatorWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
                }
                if self.saveAgain || self.isDirty {
                    self.saveAgain = false
                    self.scheduleAutosave()
                }
            }
        }
    }

    /// Synchronous save for app termination / window close.
    func saveNow() {
        saveDebouncer.cancel()
        guard isDirty else { return }
        let generation = editGeneration
        do {
            try FileCoordination.write(text, to: url)
            savedGeneration = generation
            lastSavedText = text
            knownModificationDate = url.contentModificationDate
            lastSavedAt = Date()
            saveState = .clean
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }

    /// Flushes pending work before the document is closed.
    func close() {
        renameDebouncer.cancel()
        saveNow()
        renameToMatchTitleIfAppropriate(force: true)
    }

    // MARK: - External changes

    /// Polled by the app. Reloads if the file changed on disk and we have no
    /// unsaved edits; closes if it vanished.
    func checkExternalChanges() {
        guard !saveInFlight else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            if !isDirty { onVanished?() }
            return
        }
        guard let mod = url.contentModificationDate else { return }
        // iCloud rounds timestamps and touches files after upload, so a date change alone
        // proves nothing. Compare content before believing anything changed.
        if let known = knownModificationDate, abs(mod.timeIntervalSince(known)) < 1.0 { return }
        guard let onDisk = try? FileCoordination.read(url) else { return }
        knownModificationDate = mod
        if onDisk == lastSavedText || onDisk == text { return }   // our own write echoing back

        guard !isDirty else {
            // Someone else wrote while we have unsaved edits. Ours win, theirs is kept beside it.
            let copy = library.uniqueURL(in: url.deletingLastPathComponent(),
                                         stem: title + " (conflict)", ext: url.pathExtension)
            try? FileCoordination.write(onDisk, to: copy)
            lastSavedText = onDisk
            scheduleAutosave()
            return
        }
        text = onDisk
        lastSavedText = onDisk
        editGeneration += 1
        savedGeneration = editGeneration
        titleAtLoad = onDisk.derivedMarkdownTitle
        lastFirstLine = titleAtLoad
        recomputeStats()
        onReloaded?()
    }

    // MARK: - Renaming

    private var isAutoNamed: Bool {
        let stem = title
        if stem == titleAtLoad { return true }
        return stem.range(of: "^Untitled( \\d+)?$", options: .regularExpression) != nil
    }

    private func renameToMatchTitleIfAppropriate(force: Bool = false) {
        guard settings.data.nameFilesFromFirstLine, isAutoNamed else { return }
        let desired = text.derivedMarkdownTitle.sanitizedFileStem
        guard !desired.isEmpty, desired != title else { return }
        if saveInFlight && !force {
            // Never move the file underneath a write; try again shortly.
            renameDebouncer.call { [weak self] in self?.renameToMatchTitleIfAppropriate() }
            return
        }
        let oldRel = relativePath
        do {
            let newRel = try library.rename(oldRel, to: desired)
            url = library.url(forRelativePath: newRel)
            relativePath = newRel
            titleAtLoad = text.derivedMarkdownTitle
            knownModificationDate = url.contentModificationDate
            onRenamed?(oldRel, newRel)
        } catch {
            // Name collision or similar; try again next time the title changes.
        }
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

    private static func stats(of text: String) -> (characters: Int, words: Int) {
        let ns = text as NSString
        var words = 0
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            words += 1
        }
        return (ns.length, words)
    }
}

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Central app state: settings, themes, the library and the open document.
final class AppState: ObservableObject {
    static let shared = AppState()

    let settings: AppSettings
    let themes: ThemeStore
    let backdrops = BackdropStore()
    let looks = LookStore()
    @Published private(set) var library: LibraryStore
    /// The library kept in a GitHub repository of the user's, when it is.
    let sync: SyncEngine
    @Published private(set) var document: DocumentModel?
    @Published var selection: String?          // relative path of the selected document
    @Published var selectedFolder: String = "" // relative path of the folder new docs go into
    @Published var tagFilter: String?
    @Published var searchText: String = ""
    @Published var pendingPrompt: Prompt?
    /// The open pages fanned across the window while ⌥ or ⌃ is held (Pages.swift).
    @Published var carousel: PageCarousel?
    /// Which way the page slides as another comes in: 1 from the right, -1
    /// from the left, 0 for the plain crossfade. Cleared once it has.
    @Published var pageSlide: Int = 0
    /// Bumped when ⌥Tab or ⌃Tab finds only one page open, for a nudge of the pips.
    @Published var carouselNudge = 0
    var pageKeyMonitor: Any?
    var pageMouseMonitor: Any?
    /// The modifier (⌥ or ⌃) that brought the carousel up; letting it go commits.
    var carouselModifier: NSEvent.ModifierFlags?
    /// Sideways scrolling adds up here until it is a step along the carousel.
    var carouselScroll: Double = 0
    /// Where the fanned cards are (Pages.swift).
    let carouselFramesBox = CarouselFrames()
    @Published var errorMessage: String?
    /// The Craft-style mosaic of every document. Also shown whenever nothing is open.
    @Published var showingGallery: Bool = false
    /// Review mode: the current document rendered read-only in a chosen style.
    @Published var reviewMode: Bool = false
    /// The line the caret is on, kept only while a page sits beside the editor,
    /// for that page to follow.
    @Published var caretLine: Int = 0
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

    /// Something is up over the content — Settings, the shortcut sheet, the
    /// command bar, a prompt, the fanned pages — so the keys and the scroll
    /// wheel belong to it, not to the view underneath. The views that listen
    /// for events of their own (the Timelapse's walker, the mosaic's
    /// navigator) check this first: scrolling the Settings card used to walk
    /// the corridor behind it instead. The tour is not an overlay: it sits
    /// beside the page and the page stays yours.
    var overlayUp: Bool {
        showingSettings || showingShortcuts || showingCommandBar || pendingPrompt != nil || errorMessage != nil || carousel != nil
    }
    /// Today's note is the document showing — for the sidebar's Today row.
    var todaysNoteOnScreen: Bool {
        guard !galleryOnScreen, !showingDaily, let doc = document else { return false }
        return dailyNotesByDay[DailyNotes.dayKey(Date())]?.id == doc.relativePath
    }

    /// The Daily timeline: today's note in front, earlier days receding behind it.
    @Published var showingDaily = false

    /// ⌘F overlay. The mosaic's inline box reports its frame so the overlay can
    /// glide out of it; the value lives outside @Published because it changes on layout.
    @Published var showingSearch = false
    /// Counts the times the search overlay has come out, so each one is its
    /// own view with its own glide, and one going down never inherits the next.
    @Published var searchSession = 0
    /// The overlay is on its way back to the header: it glides home before it goes.
    @Published var searchRetreating = false
    var searchFieldFrame: CGRect = .zero

    /// ⌘K command bar.
    @Published var showingCommandBar = false
    @Published var commandQuery = ""
    @Published var commandSelection = 0

    enum Prompt: Identifiable {
        case newFolder(parent: String)
        case rename(path: String, isFolder: Bool)
        /// "Move to the Trash?" — asked before any trip to the Trash, so a
        /// stray ⌘⌫ never takes the page with it.
        case trash(path: String, isFolder: Bool)

        var id: String {
            switch self {
            case .newFolder(let p): return "newFolder:\(p)"
            case .rename(let p, _): return "rename:\(p)"
            case .trash(let p, _): return "trash:\(p)"
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

    // MARK: - Looks

    /// The backdrop behind the glass right now.
    var backdrop: BackdropPreset { backdrops.preset(id: settings.data.backdrop) }

    /// The look the page is wearing, if it is one of the named ones — nil
    /// once a theme or a backdrop has been changed under it.
    var currentLook: Look? {
        let d = settings.data
        return looks.all.first { $0.matches(themeID: theme.id, backdropID: d.backdrop, drift: d.backdropDrift, frost: d.backdropFrost, grain: d.backdropGrain) }
    }

    /// The page takes on a look: its theme (into the slot it belongs to, when
    /// the appearance follows the system), its backdrop and its tuning — as
    /// one change, so ⌘Z takes the whole look back.
    func applyLook(_ look: Look) {
        var d = settings.data
        switch d.appearanceMode {
        case .fixed: d.themeID = look.themeID
        case .system: if themes.theme(id: look.themeID).isDark { d.darkThemeID = look.themeID } else { d.lightThemeID = look.themeID }
        }
        d.backdrop = look.backdropID
        d.backdropDrift = look.drift
        d.backdropFrost = look.frost
        d.backdropGrain = look.grain
        settings.data = d
    }

    /// What the page is wearing, as a look of the user's own under a name.
    /// A custom theme or set it wears is copied, so the look owns its makings
    /// and editing one look never changes another.
    @discardableResult
    func saveLook(named name: String) -> Look {
        let d = settings.data
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedLookName : name
        var themeID = theme.id
        if !theme.isBuiltIn { let t = theme.renamed(title); themes.update(t); themeID = t.id }
        var backdropID = d.backdrop
        if !backdrop.isBuiltIn { let b = backdrop.renamed(title); backdrops.update(b); backdropID = b.id }
        let look = Look(id: UUID().uuidString, name: title, themeID: themeID, backdropID: backdropID,
                        drift: d.backdropDrift, frost: d.backdropFrost, grain: d.backdropGrain)
        looks.add(look)
        applyLook(look)
        return look
    }

    /// A copy of a look that is the user's to change: its theme and its set
    /// copied too (a built-in set of the desktop's stays the desktop; Aurora's
    /// copy takes the colours it has under the theme), named after the look.
    @discardableResult
    func duplicateLook(_ source: Look) -> Look {
        let name = source.name + " Copy"
        let srcTheme = themes.theme(id: source.themeID)
        let t = srcTheme.renamed(name)
        themes.update(t)
        let srcBackdrop = backdrops.preset(id: source.backdropID)
        var backdropID = srcBackdrop.id
        if !srcBackdrop.isDesktop {
            var copy = backdrops.duplicate(srcBackdrop, for: srcTheme)
            copy.name = name
            backdrops.update(copy)
            backdropID = copy.id
        }
        let look = Look(id: UUID().uuidString, name: name, themeID: t.id, backdropID: backdropID,
                        drift: source.drift, frost: source.frost, grain: source.grain)
        looks.add(look)
        applyLook(look)
        return look
    }

    /// The look on screen, when it is the user's own — what the editor writes to.
    private var editableLook: Look? {
        guard let l = currentLook, !l.isBuiltIn else { return nil }
        return l
    }

    /// A change to the page's colours or glass. Through the look on screen:
    /// a theme the look shares with the built-ins (or with another look) is
    /// copied into one of the look's own first, so nothing else changes.
    func editLookTheme(_ change: (inout Theme) -> Void) {
        guard var look = editableLook else { return }
        var t = theme
        let shared = t.isBuiltIn || looks.custom.contains { $0.id != look.id && $0.themeID == t.id }
        if shared {
            t = t.renamed(look.name)
            look.themeID = t.id
        }
        change(&t)
        themes.update(t)
        if shared {
            looks.update(look)
            applyLook(look)
        }
    }

    /// A change to the colours behind the glass, the same way.
    func editLookBackdrop(_ change: (inout BackdropPreset) -> Void) {
        guard var look = editableLook else { return }
        var b = backdrop
        let shared = b.isBuiltIn || looks.custom.contains { $0.id != look.id && $0.backdropID == b.id }
        if shared {
            var copy = b.renamed(look.name)
            copy.colors = b.isDesktop ? BackdropPreset.softSky.colors : b.colors(for: theme)
            b = copy
            look.backdropID = b.id
        }
        change(&b)
        backdrops.update(b)
        if shared {
            looks.update(look)
            applyLook(look)
        }
    }

    /// The desktop behind the glass, or folds of colour: on the way back to
    /// folds, Soft Sky's colours as a set of the look's own.
    func setLookBehind(desktop: Bool) {
        guard var look = editableLook else { return }
        if desktop {
            look.backdropID = BackdropPreset.desktopID
        } else {
            let set = BackdropPreset.softSky.renamed(look.name)
            backdrops.update(set)
            look.backdropID = set.id
        }
        looks.update(look)
        applyLook(look)
    }

    /// Looks for what was made before there were looks: a custom theme or a
    /// custom set that no look uses becomes a look of its own — over the page
    /// or the folds of the moment — so nothing anyone made goes out of reach;
    /// and the page as it stands, if no tile stands for it, becomes one too.
    /// Once, on the first launch with looks.
    private func adoptOrphansIntoLooks() {
        guard !settings.data.looksAdopted else { return }
        let d = settings.data
        let taken = Set(looks.all.map(\.name))
        func name(_ base: String) -> String { taken.contains(base) ? base + " (mine)" : base }
        for b in backdrops.custom where !looks.custom.contains(where: { $0.backdropID == b.id }) {
            looks.add(Look(id: UUID().uuidString, name: name(b.name), themeID: theme.id, backdropID: b.id,
                           drift: d.backdropDrift, frost: d.backdropFrost, grain: d.backdropGrain))
        }
        for t in themes.custom where !looks.custom.contains(where: { $0.themeID == t.id }) {
            looks.add(Look(id: UUID().uuidString, name: name(t.name), themeID: t.id, backdropID: d.backdrop,
                           drift: d.backdropDrift, frost: d.backdropFrost, grain: d.backdropGrain))
        }
        if currentLook == nil {
            looks.add(Look(id: UUID().uuidString, name: suggestedLookName, themeID: theme.id, backdropID: d.backdrop,
                           drift: d.backdropDrift, frost: d.backdropFrost, grain: d.backdropGrain))
        }
        settings.data.looksAdopted = true
    }

    /// "Midnight over Soft Sky": a name for the page's look as it stands.
    var suggestedLookName: String {
        let b = backdrop
        return b.isDesktop ? "\(theme.name) over the desktop" : "\(theme.name) over \(b.name)"
    }

    /// A look of the user's goes, and its makings with it when nothing else
    /// uses them; the page puts on Soft Sky if it was wearing the look.
    func deleteLook(_ look: Look) {
        guard !look.isBuiltIn else { return }
        let wearing = currentLook?.id == look.id
        looks.delete(look)
        if let t = themes.custom.first(where: { $0.id == look.themeID }), !looks.custom.contains(where: { $0.themeID == t.id }) {
            themes.delete(t)
        }
        if let b = backdrops.custom.first(where: { $0.id == look.backdropID }), !looks.custom.contains(where: { $0.backdropID == b.id }) {
            backdrops.delete(b)
        }
        if wearing { applyLook(.softSky) }
    }

    /// Export…: the look on screen — the named one, or the page as it
    /// stands — with its theme and backdrop inside, as a .glassinelook file.
    func exportLook() {
        let look = currentLook ?? Look(id: UUID().uuidString, name: suggestedLookName, themeID: theme.id, backdropID: settings.data.backdrop,
                                       drift: settings.data.backdropDrift, frost: settings.data.backdropFrost, grain: settings.data.backdropGrain)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = look.name.sanitizedFileStem + "." + LookFile.fileExtension + ".json"
        panel.message = "A look is its theme and its backdrop together, in one file anyone with Glassine can open: Settings → Look → Import."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try LookFile.write(look: look, theme: theme, backdrop: backdrop, to: url)
            showNotice("Exported the look")
        } catch {
            errorMessage = "Couldn't export the look: \(error.localizedDescription)"
        }
    }

    /// Import…: a .glassinelook file. Its theme and backdrop join Mine unless
    /// a built-in one is the same; the look joins Mine and goes on at once.
    func importLook() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try LookFile.read(from: url)
            // The theme: a built-in that is the same (its id and its colours),
            // else one of the user's, under a fresh id if the file's is taken.
            var theme = file.theme
            if let twin = Theme.builtIns.first(where: { $0.id == theme.id }), twinOf(twin, theme) {
                theme = twin
            } else {
                theme.isBuiltIn = false
                if themes.all.contains(where: { $0.id == theme.id }) {
                    if let same = themes.custom.first(where: { twinOf($0, theme) }) { theme = same } else { theme.id = UUID().uuidString; themes.update(theme) }
                } else {
                    themes.update(theme)
                }
            }
            var backdrop = file.backdrop
            if let twin = BackdropPreset.builtIns.first(where: { $0.id == backdrop.id || (!$0.colors.isEmpty && $0.colors == backdrop.colors) }) {
                backdrop = twin
            } else {
                backdrop.isBuiltIn = false
                if backdrops.all.contains(where: { $0.id == backdrop.id }) {
                    if let same = backdrops.custom.first(where: { $0.colors == backdrop.colors }) { backdrop = same } else { backdrop.id = UUID().uuidString; backdrops.update(backdrop) }
                } else {
                    backdrops.update(backdrop)
                }
            }
            var look = file.look
            look.themeID = theme.id
            look.backdropID = backdrop.id
            look.isBuiltIn = false
            if looks.all.contains(where: { $0.id == look.id }) { look.id = UUID().uuidString }
            looks.add(look)
            applyLook(look)
            showNotice("Imported “\(look.name)”")
        } catch {
            errorMessage = "Couldn't import that look: \(error.localizedDescription)"
        }
    }

    /// The same theme, whatever it is called: every colour and the glass alike.
    private func twinOf(_ a: Theme, _ b: Theme) -> Bool {
        var x = a, y = b
        x.id = ""; y.id = ""; x.name = ""; y.name = ""; x.isBuiltIn = false; y.isBuiltIn = false
        return x == y
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
    /// The tour (TourView): a first launch, or Help → Tour of Glassine.
    @Published var showingTour = false
    /// Which settings section is up — an index into SettingsOverlay.Pane —
    /// kept here so Settings reopens where it was left; Tab and ⇧Tab walk it.
    @Published var settingsTab = 0
    /// What is typed into the search field at the top of Settings.
    @Published var settingsQuery = ""
    /// Bumped to put the keyboard in that field (⌘F while Settings is up).
    @Published var settingsSearchFocus = 0
    /// The theme as the page draws it: over a backdrop, a light theme's quiet
    /// colours lean toward the text, so a task's box stays on the page.
    var pageTheme: Theme {
        settings.data.backdrop == BackdropPreset.desktopID ? theme : theme.overBackdrop()
    }
    var styleConfig: StyleConfig { StyleConfig(theme: pageTheme, settings: settings.data) }

    private var cancellables = Set<AnyCancellable>()
    private var pollTimer: Timer?

    private init() {
        let settings = AppSettings()
        self.settings = settings
        self.themes = ThemeStore()
        let library = LibraryStore(chosen: ChosenFolder(bookmark: settings.data.libraryBookmark, path: settings.data.libraryPath))
        self.library = library
        self.sync = SyncEngine(library: library, settings: settings)
        // A bookmark that had gone stale was refreshed on the way in; keep the fresh one.
        if let fresh = library.chosenBookmark, fresh != settings.data.libraryBookmark {
            settings.data.libraryBookmark = fresh
        }

        // Republish nested object changes so views observing AppState refresh.
        settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        themes.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        backdrops.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        looks.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        sync.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        bindLibrary()

        // A set of the user's own that is now built in (Soft Sky, say) is the
        // built-in one from here on, wherever it was pointed at.
        let absorbed = backdrops.absorbBuiltIns()
        if !absorbed.isEmpty {
            if let moved = absorbed[settings.data.backdrop] { settings.data.backdrop = moved }
            for look in looks.custom {
                if let moved = absorbed[look.backdropID] { var l = look; l.backdropID = moved; looks.update(l) }
            }
        }
        // A backdrop that is gone — a set deleted, or absorbed by a copy that
        // never saved the settings — is Soft Sky from here on, not the desktop.
        if !backdrops.all.contains(where: { $0.id == settings.data.backdrop }) {
            settings.data.backdrop = BackdropPreset.softSkyID
        }
        looks.prune(themes: themes, backdrops: backdrops)
        adoptOrphansIntoLooks()

        bootstrapLibrary()
        startPolling()
        installPageKeys()

        // Sync leaves the document being edited alone until it is saved, and
        // tells the app when it has changed the library underneath it.
        sync.busyPath = { [weak self] in
            guard let doc = self?.document, doc.isDirty || doc.saveState == .saving else { return nil }
            return doc.relativePath
        }
        sync.libraryChanged = { [weak self] in
            self?.library.rescan()
            self?.document?.checkExternalChanges()
        }
        sync.start()

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

    /// The library's changes, republished as the app's; replaced, not added
    /// to, when the library is swapped for another folder.
    private var librarySink: AnyCancellable?

    private func bindLibrary() {
        librarySink = library.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    private func bootstrapLibrary() {
        if Distribution.isDemo, library.isEmptyOnDisk, DemoLibrary.seed(into: library.rootURL) {
            // The demonstration copy opens on its showcase, arranged.
            settings.data.expandedFolders = DemoLibrary.expanded
            settings.data.starred = DemoLibrary.starred
            settings.data.lastOpenedDocument = DemoLibrary.opened
            settings.data.sidebarVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { DemoLibrary.placeWindowForPictures() }
        } else if library.isEmptyOnDisk,
                  let ref = try? library.createDocument(in: "", stem: "Welcome to Glassine", contents: WelcomeDocument.text) {
            // The first page opens on its own, from its heading rather than its end.
            settings.data.lastOpenedDocument = ref.id
            openAtTop = ref.id
        }
        // A library folder that could not be made is said so, once the window
        // is up — it was kept in the library and shown nowhere.
        if let trouble = library.lastError {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.errorMessage = trouble }
        }
        // A listing is enough to open the last document and show the window; reading every
        // file for previews, tags and search happens right after, off the main thread.
        library.scanNow(readingContents: false)
        library.rescan()
        prunePages()
        if let last = settings.data.lastOpenedDocument, let ref = library.document(withID: last) {
            open(ref)
        } else if let first = settings.data.openPages.first, let ref = library.document(withID: first) {
            open(ref)
        } else {
            showingGallery = true
        }
        // Review and the Daily view are not remembered between launches, so
        // docs/appstore/screenshots.sh asks for them by launch argument, and a
        // check shot can ask for Settings, on a section, the same way:
        //   open Glassine.app --args -glassine.launchView review
        //   open Glassine.app --args -glassine.launchView settings:caret
        switch UserDefaults.standard.string(forKey: "glassine.launchView") {
        case "review": if document != nil { reviewMode = true }
        case "daily": showDaily()
        case "backdrops": showingSettings = true; settingsTab = SettingsOverlay.Pane.look.index
        case "trash": trashCurrentDocument()   // the "Move to the Trash?" sheet, for a picture of it
        case "tour": showingTour = true
        case "carousel":
            // Every document in the library open as a page, and the pages fanned out.
            for ref in library.allDocuments.reversed() { open(ref) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.stepCarousel(backward: false) }
        case let view? where view.hasPrefix("settings"):
            showingSettings = true
            let name = view.split(separator: ":").dropFirst().first.map(String.init) ?? ""
            settingsTab = (SettingsOverlay.Pane.named(name) ?? .type).index
            if let q = UserDefaults.standard.string(forKey: "glassine.settingsQuery") { settingsQuery = q }
        default: break
        }
        // A copy that has never been through the tour starts with it, once the
        // window is up — not the demonstration copy, and not a check shot.
        if !settings.data.tourSeen, !Distribution.isDemo, !ScreenshotMode.isActive,
           UserDefaults.standard.string(forKey: "glassine.launchView") == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.showingTour = true }
        }
    }

    /// The library is watched through the file system's own events (a
    /// rescan a beat after anything changes), with a slow poll behind it for
    /// what events can miss — a dataless iCloud file filling in, a volume
    /// that does not report. The poll used to be the only way, every three
    /// seconds, walking the whole tree each time.
    private func startPolling() {
        library.startWatching { [weak self] in
            self?.document?.checkExternalChanges()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self, NSApp.isActive else { return }
            self.library.rescan()
            self.document?.checkExternalChanges()
        }
        pollTimer?.tolerance = 5
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    // MARK: - Derived lists

    /// Everything that is not on the Shelf — what Recents, Starred and All
    /// Documents draw from. Search still looks at the whole library.
    /// Filtered once per scan rather than on every read: the sidebar, the
    /// mosaic, Recents and Starred all ask for this several times a render.
    private var activeMemo: (generation: Int, docs: [DocumentRef]) = (-1, [])
    var activeDocuments: [DocumentRef] {
        if activeMemo.generation == library.generation { return activeMemo.docs }
        let docs = library.allDocuments.filter { !Shelf.holds($0.id) }
        activeMemo = (library.generation, docs)
        return docs
    }

    var recentDocuments: [DocumentRef] {
        let recents = settings.data.recents
        return activeDocuments
            .filter { recents[$0.id] != nil }
            .sorted { (recents[$0.id] ?? .distantPast) > (recents[$1.id] ?? .distantPast) }
    }

    var starredDocuments: [DocumentRef] {
        var rank: [String: Int] = [:]
        for (i, id) in settings.data.starred.enumerated() where rank[id] == nil { rank[id] = i }
        return activeDocuments.compactMap { doc in rank[doc.id].map { (doc, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Folders a document can be moved into by hand; the Shelf has its own commands.
    var moveTargets: [LibraryFolder] {
        library.root.allFolders.filter { !Shelf.holds($0.id) }
    }

    func sorted(_ docs: [DocumentRef]) -> [DocumentRef] {
        switch settings.data.sortDocumentsBy {
        case .modified: return docs.sorted { $0.modified > $1.modified }
        case .created: return docs.sorted { $0.created > $1.created }
        case .name: return docs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .manual: return handSorted(docs)
        }
    }

    /// The order the documents were put in by hand — one list for the whole
    /// library, which the wall shows entire and each folder of the sidebar
    /// shows its part of. Documents that were never placed come first,
    /// newest edit at the top: a new document belongs at the top until it is
    /// put somewhere.
    private func handSorted(_ docs: [DocumentRef]) -> [DocumentRef] {
        var rank: [String: Int] = [:]
        for (i, id) in settings.data.handOrder.enumerated() where rank[id] == nil { rank[id] = i }
        return docs.sorted { a, b in
            switch (rank[a.id], rank[b.id]) {
            case let (x?, y?): return x < y
            case (nil, nil): return a.modified > b.modified
            case (nil, _): return true
            default: return false
            }
        }
    }

    /// Every document in the order it stands on screen under the sort in
    /// force. A drag starts from this, so that when the sort switches to
    /// *Your order* only what was dragged has changed places.
    private var standingOrder: [String] { sorted(library.allDocuments).map(\.id) }

    /// A row dragged to a new place among its folder's rows. `shown` is the
    /// order the folder's rows had on screen, whatever sort made it, and
    /// `index` the row among them it was let go in; the document takes that
    /// place in the library's one order — just before the row now there, or
    /// after the last — and the sort switches to it. ⌘Z puts it back.
    func placeDocument(_ id: String, at index: Int, in folder: String, shown: [DocumentRef]) {
        var order = standingOrder.filter { $0 != id }
        let siblings = shown.map(\.id).filter { $0 != id }
        guard !siblings.isEmpty else { return }
        let at: Int
        if index < siblings.count, let before = order.firstIndex(of: siblings[index]) {
            at = before
        } else if let last = order.firstIndex(of: siblings[siblings.count - 1]) {
            at = last + 1
        } else {
            at = order.count
        }
        order.insert(id, at: at)
        setHandOrder(order, sort: .manual)
    }

    /// The wall's cards as they were left after a drag — every document that
    /// is not on the Shelf, top left to bottom right. The Shelf's documents
    /// keep their own order after them.
    func placeOnWall(_ wall: [String]) {
        let onWall = Set(wall)
        let order = wall + standingOrder.filter { !onWall.contains($0) }
        guard order != settings.data.handOrder || settings.data.sortDocumentsBy != .manual else { return }
        setHandOrder(order, sort: .manual)
    }

    private func setHandOrder(_ order: [String], sort: SortMode) {
        let wasOrder = settings.data.handOrder, wasSort = settings.data.sortDocumentsBy
        settings.data.handOrder = order
        settings.data.sortDocumentsBy = sort
        libraryUndo.registerUndo(withTarget: self) { s in s.setHandOrder(wasOrder, sort: wasSort) }
        libraryUndo.setActionName("Reorder")
    }

    /// Documents matching the search box and/or the tag filter, or nil when neither is set.
    /// Every word of the query has to appear somewhere in the title, tags or text
    /// (case- and accent-insensitive). Title matches come first, then the rest in the usual order.
    private struct SearchMemo {
        let query: String, tag: String?, day: Int?, sort: SortMode, generation: Int, liveID: String?, liveEdit: Int
        let result: [DocumentRef]
    }
    private var searchMemo: SearchMemo?

    var filteredDocuments: [DocumentRef]? {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard tagFilter != nil || dayFilter != nil || !q.isEmpty else { return nil }
        if let memo = searchMemo, memo.query == q, memo.tag == tagFilter, memo.day == dayFilter, memo.sort == settings.data.sortDocumentsBy,
           memo.generation == library.generation, memo.liveID == document?.relativePath,
           memo.liveEdit == (document?.editGeneration ?? -1) {
            return memo.result
        }
        let result = computeFilteredDocuments(query: q)
        searchMemo = SearchMemo(query: q, tag: tagFilter, day: dayFilter, sort: settings.data.sortDocumentsBy, generation: library.generation,
                                liveID: document?.relativePath, liveEdit: document?.editGeneration ?? -1, result: result)
        return result
    }

    private func computeFilteredDocuments(query q: String) -> [DocumentRef] {
        var base: [DocumentRef]
        if let day = dayFilter {
            // A day's wall keeps the day's order: the note first, then by last edit.
            base = documents(onDay: day)
            if let tag = tagFilter { base = base.filter { $0.tags.contains(tag) } }
            guard !q.isEmpty else { return base }
        } else if let tag = tagFilter {
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
        dayFilter = nil
        if document != nil { showingGallery = true }
        // ⌘F while the bar is still on its way back, or gone a moment ago:
        // a fresh overlay comes out from home; the old one finishes fading.
        if !showingSearch || searchRetreating { searchSession += 1 }
        searchRetreating = false
        showingSearch = true
    }

    /// Esc, or a click beside it: the search bar glides back to its spot in
    /// the header the way it came, and is taken down once it has landed. The
    /// reverse of focusSearch(), at the same pace. The overlay says when it
    /// has landed (`searchLanded`); the timer behind it is for a glide that
    /// never reports — reduced motion, say.
    func hideSearch() {
        guard showingSearch, !searchRetreating else { return }
        searchRetreating = true
        let session = searchSession
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self, self.searchSession == session else { return }
            self.searchLanded()
        }
    }

    /// The bar is home: the overlay comes down over the header's own field,
    /// which fades up under it. The retreat flag is left standing through the
    /// same update, so the outgoing overlay is not told to come back out
    /// while it fades — that was a jump to the middle of the window before
    /// it went.
    func searchLanded() {
        guard showingSearch, searchRetreating else { return }
        showingSearch = false
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.showingSearch else { return }
            self.searchRetreating = false
        }
    }

    /// The overlay goes at once — for a change of view, where there is no
    /// header for it to return to.
    private func dropSearch() {
        showingSearch = false
        searchRetreating = false
    }

    func showDaily() {
        dropSearch()
        showingCommandBar = false
        reviewMode = false
        dayFilter = nil
        showingDaily = true
    }

    /// Esc on the Timelapse: All Documents — and Esc there comes back here.
    /// The two overviews trade places, so each is one key from the other.
    func escapeFromTimelapse() {
        showingDaily = false
        dayFilter = nil
        showingGallery = true
    }

    /// Esc on All Documents, once a search, a tag or a day has been cleared:
    /// the Timelapse.
    func escapeFromGallery() {
        if !searchText.isEmpty { searchText = ""; return }
        if tagFilter != nil { tagFilter = nil; return }
        if dayFilter != nil { dayFilter = nil; return }
        showDaily()
    }

    func toggleCommandBar() {
        showingCommandBar.toggle()
        if showingCommandBar {
            commandQuery = ""
            commandSelection = 0
            dropSearch()
        }
    }

    // MARK: - Opening documents

    /// The card a document is being opened from, while the open animation runs.
    @Published var zoomingCard: String?

    /// Whether the open document came from a day in the Timelapse, so Esc
    /// can take it back there rather than to the mosaic.
    private(set) var cameFromDaily = false

    func open(_ ref: DocumentRef, fromCard: Bool = false) {
        // Where Esc goes back to: a document opened from the Timelapse returns
        // there; one opened from the mosaic, the sidebar or anywhere else goes
        // to the mosaic. Reopening the document already showing (after a
        // rename, say) keeps whatever the answer was.
        if showingDaily {
            cameFromDaily = true
        } else if galleryOnScreen || document?.relativePath != ref.id {
            cameFromDaily = false
        }
        if fromCard, galleryOnScreen || showingDaily, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            zoomingCard = ref.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                if self?.zoomingCard == ref.id { self?.zoomingCard = nil }
            }
        }
        showingGallery = false
        showingDaily = false
        dropSearch()
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
        notePageOpened(ref.id)
        if pageSlide != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.pageSlide = 0 }
        }
    }

    /// The document showing, when it is a file from outside the library.
    var looseDocument: DocumentModel? { document?.isLoose == true ? document : nil }

    /// A file by URL — from Finder's Open With, the Dock icon, or File →
    /// Open…. One inside the library opens as itself; one from anywhere else
    /// opens in place, edited and saved where it is and never copied in.
    func openFile(at url: URL) {
        let file = url.standardizedFileURL
        let rootPath = library.rootURL.standardizedFileURL.path
        if file.path.hasPrefix(rootPath + "/") {
            let rel = library.relativePath(for: file)
            if library.document(withID: rel) == nil { library.scanNow() }
            if let ref = library.document(withID: rel) { open(ref); return }
        }
        showingGallery = false
        showingDaily = false
        reviewMode = false
        dropSearch()
        showingCommandBar = false
        cameFromDaily = false
        if let current = document, current.url.standardizedFileURL == file { return }
        closeCurrentDocument()
        let doc = DocumentModel(url: file, library: library, settings: settings)
        wire(doc)
        document = doc
        selection = nil
    }

    /// File → Open…: any Markdown or text file, opened in place.
    func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, UTType("net.daringfireball.markdown")].compactMap { $0 }
        panel.message = "Open a Markdown or text file where it is. It is not copied into the library."
        if panel.runModal() == .OK, let url = panel.url { openFile(at: url) }
    }

    /// A copy of the file from elsewhere, at the top level of the library,
    /// and that copy open in its place.
    func addLooseDocumentToLibrary() {
        guard let doc = looseDocument else { return }
        doc.saveNow()
        let ext = doc.url.pathExtension.isEmpty ? "md" : doc.url.pathExtension
        let target = library.uniqueURL(in: library.rootURL, stem: doc.title, ext: ext)
        do {
            try FileCoordination.write(doc.text, to: target)
        } catch {
            errorMessage = "Couldn't add it to the library: \(error.localizedDescription)"
            return
        }
        library.scanNow()
        if let ref = library.document(withID: library.relativePath(for: target)) { open(ref) }
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

    /// The document on screen put away without another coming up (⌘W on a
    /// file from elsewhere, or on the last page).
    func closeLooseDocument() {
        closeCurrentDocument()
        selection = nil
    }

    /// The caret has been placed on the page. (Its position used to be
    /// written into the settings here, every 0.8 s of writing, for a restore
    /// that never came — and a settings write has every view in the window
    /// redo its body. Documents open at their end; see savedCaret.)
    func caretMoved(to position: Int) {
        guard let doc = document, !doc.isLoose else { return }
        openAtTop = nil
    }

    /// The document that opens at its heading this once: the Welcome page a
    /// first launch has just written, read from the top. Cleared as soon as
    /// the caret has been placed, so it opens at the end like any other after.
    private var openAtTop: String?

    /// Documents open with the caret at the end — where the writing continues.
    /// docs/appstore/screenshots.sh can ask for a particular spot instead:
    ///   open Glassine.app --args -glassine.launchCaret 412
    func savedCaret(for relPath: String) -> Int? {
        if let s = UserDefaults.standard.string(forKey: "glassine.launchCaret"), let n = Int(s) { return n }
        if openAtTop == relPath { return 0 }
        return nil
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
            if wasOpen {
                // The page under the one that went, or the last document used.
                if let page = settings.data.openPages.first(where: { $0 != rel && !$0.hasPrefix(rel + "/") }), let ref = library.document(withID: page) { open(ref) }
                else if let next = recentDocuments.first { open(next) }
            }
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
        guard let doc = document, let lineText = doc.setTask(ordinal: ordinal, checked: checked) else { return false }
        let box = track(doc.relativePath)
        libraryUndo.registerUndo(withTarget: self) { s in
            if s.document?.relativePath != box.rel { s.open(relativePath: box.rel) }
            // The task may have sunk since; find it by what its line says now.
            s.toggleTask(ordinal: s.document?.ordinal(ofTaskLine: lineText) ?? ordinal, checked: !checked)
        }
        libraryUndo.setActionName(checked ? "Check Off Task" : "Uncheck Task")
        return true
    }

    // MARK: - Creating

    /// Where a new document goes when nobody names a folder: the folder last
    /// worked in. The Daily folder is the exception — opening a day's note
    /// makes it the folder last worked in, and a plain new document made
    /// after that would be filed as a daily note it is not. Those go to the
    /// top of the library; "New Document Here" on Daily still puts one there.
    var newDocumentFolder: String {
        let daily = DailyNotes.folder
        return selectedFolder == daily || selectedFolder.hasPrefix(daily + "/") ? "" : selectedFolder
    }

    func newDocument(in folder: String? = nil) {
        let target = folder ?? newDocumentFolder
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
    func openTodaysNote() { openNote(for: Date()) }

    /// A day's note in the Daily folder — today's, or any day the calendar
    /// points at — made on first use.
    func openNote(for date: Date) {
        if let existing = dailyNotesByDay[DailyNotes.dayKey(date)] {
            open(existing)
            reviewMode = false
            return
        }
        let title = DailyNotes.title(for: date)
        let folder = DailyNotes.folder
        do {
            if !FileManager.default.fileExists(atPath: library.url(forRelativePath: folder).path) {
                _ = try library.createFolder(named: folder, in: "")
            }
            // The heading and one line under it for the caret — not a blank
            // line and then the caret, which read as a paragraph nobody wrote.
            let contents = "# \(title)\n"
            let ref = try library.createDocument(in: folder, stem: title.sanitizedFileStem, contents: contents)
            open(ref)
            reviewMode = false
            registerCreationUndo(of: ref.id, label: Calendar.current.isDateInToday(date) ? "Today's Note" : "Day's Note")
            settings.setExpanded(folder, true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The daily notes by the day they are named for (`DailyNotes.dayKey`),
    /// as of the last scan — what the sidebar's calendar shades and opens.
    /// Built again only when the library changes; the note being written is
    /// counted live by the calendar itself.
    private var dailyNotesMemo: (generation: Int, notes: [Int: DocumentRef]) = (-1, [:])
    var dailyNotesByDay: [Int: DocumentRef] {
        if dailyNotesMemo.generation == library.generation { return dailyNotesMemo.notes }
        var notes: [Int: DocumentRef] = [:]
        for doc in library.allDocuments where doc.folder == DailyNotes.folder {
            guard let date = DailyNotes.date(fromTitle: doc.title) else { continue }
            let key = DailyNotes.dayKey(date)
            // Two notes for one day (a conflict copy, say): the longer stands for it.
            if let had = notes[key], had.words >= doc.words { continue }
            notes[key] = doc
        }
        dailyNotesMemo = (library.generation, notes)
        return notes
    }

    // MARK: - Days

    /// What was written on each day: the documents created or last edited
    /// then, with the day's note first and the rest by their last edit —
    /// keyed by `DailyNotes.dayKey`, as of the last scan. The Timelapse's
    /// Everything scope and the calendar's day view both read it; the Shelf
    /// stays out, as it does everywhere but search.
    private var dayMemo: (generation: Int, days: [Int: [DocumentRef]]) = (-1, [:])
    var documentsByDay: [Int: [DocumentRef]] {
        if dayMemo.generation == library.generation { return dayMemo.days }
        let notes = dailyNotesByDay
        var days: [Int: [DocumentRef]] = [:]
        var seen: [Int: Set<String>] = [:]
        func put(_ doc: DocumentRef, on key: Int) {
            guard key > 20000101 else { return }   // a file with no date to speak of
            if seen[key, default: []].insert(doc.id).inserted { days[key, default: []].append(doc) }
        }
        for (key, note) in notes { put(note, on: key) }
        for doc in activeDocuments {
            put(doc, on: DailyNotes.dayKey(doc.modified))
            put(doc, on: DailyNotes.dayKey(doc.created))
        }
        for (key, list) in days {
            days[key] = list.sorted { a, b in
                let an = notes[key]?.id == a.id, bn = notes[key]?.id == b.id
                if an != bn { return an }
                return a.modified > b.modified
            }
        }
        dayMemo = (library.generation, days)
        return days
    }

    /// The documents of one day, the note first; none for a day nothing was written.
    func documents(onDay key: Int) -> [DocumentRef] { documentsByDay[key] ?? [] }

    /// A day picked in the sidebar's calendar — the mosaic narrowed to what
    /// was written that day (`DailyNotes.dayKey`). Cleared by All Documents,
    /// the Timelapse, a search, or the ✕ beside the day's name.
    @Published var dayFilter: Int?

    /// The day's wall: every document written on that day, as cards, with
    /// the day's note (or the way to start it) at the top.
    func showDay(_ date: Date) {
        dropSearch()
        showingCommandBar = false
        reviewMode = false
        searchText = ""
        tagFilter = nil
        dayFilter = DailyNotes.dayKey(date)
        showingDaily = false
        showingGallery = true
    }

    /// The date a day key stands for, at the start of the day.
    static func date(forDayKey key: Int) -> Date {
        var c = DateComponents()
        c.year = key / 10000
        c.month = (key / 100) % 100
        c.day = key % 100
        return Calendar.current.date(from: c) ?? Date()
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
            // The folder may be gone — undoing an unshelve, say, after the
            // empty Shelf folders were swept up — so make it if need be.
            try FileManager.default.createDirectory(at: library.url(forRelativePath: folder), withIntermediateDirectories: true)
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
            // The last thing off the Shelf takes the empty folders with it.
            if Shelf.holds(oldFolder), !Shelf.holds(folder) { library.pruneEmptyFolders(under: Shelf.folder) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - The Shelf

    /// Puts a document or folder on the Shelf: out of Recents, Starred, the
    /// folder tree and All Documents, keeping its place in the structure
    /// underneath Shelf/ so that unshelving returns it exactly there.
    func shelve(_ rel: String) {
        guard !Shelf.holds(rel) else { return }
        let parent = Shelf.parent(of: rel)
        move(rel, toFolder: parent.isEmpty ? Shelf.folder : Shelf.folder + "/" + parent)
        libraryUndo.setActionName("Shelve")
        // New documents keep going where they went before, not onto the Shelf.
        if Shelf.holds(selectedFolder) { selectedFolder = parent }
    }

    /// Back to where it came from; the folder is recreated if it is gone.
    func unshelve(_ rel: String) {
        guard Shelf.holds(rel), rel != Shelf.folder else { return }
        move(rel, toFolder: Shelf.parent(of: Shelf.home(of: rel)))
        libraryUndo.setActionName("Unshelve")
    }

    func toggleShelved(_ rel: String) {
        if Shelf.holds(rel) { unshelve(rel) } else { shelve(rel) }
    }

    var currentDocumentIsShelved: Bool {
        document.map { Shelf.holds($0.relativePath) } ?? false
    }

    func toggleShelvedCurrentDocument() {
        guard let rel = document?.relativePath else { return }
        toggleShelved(rel)
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

    /// Every way to the Trash — ⌘⌫, the File menu, a row's menu, a card's —
    /// comes through here and asks first. The move itself is `trashNow`.
    func trash(_ rel: String) {
        let isFolder = library.url(forRelativePath: rel).isDirectoryURL
        pendingPrompt = .trash(path: rel, isFolder: isFolder)
    }

    /// The move, once the question has been answered.
    func trashNow(_ rel: String) {
        undoableTrash(track(rel), label: "Move to Trash")
    }

    func trashCurrentDocument() {
        guard let rel = document?.relativePath else { return }
        trash(rel)
    }

    func revealCurrentDocument() {
        guard let doc = document else { return }
        if doc.isLoose {
            NSWorkspace.shared.activateFileViewerSelecting([doc.url])
        } else {
            library.revealInFinder(doc.relativePath)
        }
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
            setLibrary(chosen: ChosenFolder(pickedURL: url))
        }
    }

    func resetLibraryToDefault() {
        setLibrary(chosen: nil)
    }

    /// Help → Reset Demo Library: the showcase pages written fresh, dated
    /// from today, and the first look again. What was there goes to the Trash.
    func resetDemoLibrary() {
        guard Distribution.isDemo else { return }
        closeCurrentDocument()
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: library.rootURL.path)) ?? [] {
            let item = library.rootURL.appendingPathComponent(name)
            if (try? fm.trashItem(at: item, resultingItemURL: nil)) == nil { try? fm.removeItem(at: item) }
        }
        showingGallery = false
        showingDaily = false
        reviewMode = false
        setLibrary(chosen: nil)
    }

    private func setLibrary(chosen: ChosenFolder?) {
        closeCurrentDocument()
        selection = nil
        selectedFolder = ""
        tagFilter = nil
        settings.data.libraryPath = chosen?.url.path
        settings.data.libraryBookmark = chosen?.bookmark
        settings.data.lastOpenedDocument = nil
        settings.data.recents = [:]
        settings.data.starred = []
        settings.data.expandedFolders = []
        settings.data.caretPositions = [:]
        library = LibraryStore(chosen: chosen)
        bindLibrary()
        bootstrapLibrary()
        sync.libraryDidChange(to: library)
    }

    // MARK: - View toggles

    /// All Documents, whatever is showing: from the editor the page zooms out
    /// into its card, from the Timelapse the wall takes its place. Asked for
    /// while it is already up, it stays up — a view that closed when picked
    /// again put people in a document they had not chosen. Esc is the way back.
    func showGallery() {
        dayFilter = nil
        if showingDaily { showingDaily = false; showingGallery = true; return }
        if galleryOnScreen { return }
        if document == nil { showingGallery = true; return }
        zoomOutToGallery()
    }

    /// Esc from the editor: zoom out to where the document was opened from —
    /// the Timelapse if it came from a day there, the mosaic otherwise.
    func escapeFromEditor() {
        zoomOut(toDaily: cameFromDaily)
    }

    func zoomOutToGallery() {
        zoomOut(toDaily: false)
    }

    /// The reverse of opening from a card: the page shrinks back into its
    /// card. The plate goes over the page first, so there is a frame for the
    /// card to come from; a beat later the mosaic — or the Timelapse — comes
    /// in and its card takes that frame and settles into place. From Review,
    /// or with Reduce Motion on, the view simply appears.
    private func zoomOut(toDaily daily: Bool) {
        let show: () -> Void = { [weak self] in
            guard let self else { return }
            if daily { self.showDaily() } else { self.showingGallery = true }
        }
        guard let id = document?.relativePath, !reviewMode,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            show()
            return
        }
        zoomingCard = id
        DispatchQueue.main.async(execute: show)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            if self?.zoomingCard == id { self?.zoomingCard = nil }
        }
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

    /// Review is what is on screen: not the mosaic or the Timelapse over it.
    var inReview: Bool { reviewMode && !galleryOnScreen && !showingDaily && document != nil }

    /// ⌘⇧↩: the page beside the editor, rendered as you write and following
    /// the caret — or put away. From Review it brings the editor back with
    /// the page beside it; from the mosaic it opens the document.
    func toggleReviewBeside() {
        guard document != nil else { return }
        let opening = !settings.data.reviewBeside
        if opening, let textView = GlassineTextView.current {
            caretLine = EditorView.lineIndex(at: textView.selectedRange().location, in: textView.string as NSString)
        }
        withAnimation(.easeOut(duration: 0.22)) {
            settings.data.reviewBeside = opening
            if opening {
                reviewMode = false
                showingGallery = false
                showingDaily = false
            }
        }
    }

    /// The next style along, or the one before: ⇥ and ⇧⇥ in Review.
    func cycleReviewStyle(by step: Int) {
        let all = ReviewStyle.allCases
        guard let i = all.firstIndex(of: settings.data.reviewStyle) else { return }
        settings.data.reviewStyle = all[((i + step) % all.count + all.count) % all.count]
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

    /// ⌘.: the window floats over everything else, or stops.
    func toggleFloating() {
        settings.data.floatOnTop.toggle()
        showNotice(settings.data.floatOnTop ? "Floating over other windows" : "Floating off")
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
        /// The choice in force now — the style on, the look worn, the sort
        /// in use — shown with a mark at the end of the row.
        var current: Bool = false
        let action: () -> Void
    }

    /// What ⌘K offers depends on where you are: Review styles in Review, sorting in
    /// the mosaic, writing modes in the editor. Themes ride along everywhere.
    var availableCommands: [AppCommand] {
        var cmds: [AppCommand] = []
        func add(_ id: String, _ title: String, keys: String? = nil, current: Bool = false, _ action: @escaping () -> Void) {
            cmds.append(AppCommand(id: id, title: title, keys: keys, current: current, action: action))
        }
        if inReview {
            for s in ReviewStyle.allCases {
                add("style-\(s.rawValue)", "Review style: \(s.label)", current: settings.data.reviewStyle == s) { [weak self] in self?.settings.data.reviewStyle = s }
            }
            add("leave-review", "Leave Review", keys: "⌘↩  ⌘⇧S") { [weak self] in self?.toggleReview() }
            add("beside", "Review beside the editor", keys: "⌘⇧↩") { [weak self] in self?.toggleReviewBeside() }
            add("copy-md", "Copy as Markdown", keys: "⌘⇧C") { [weak self] in self?.copyCurrentDocument(asMarkdown: true) }
            add("copy-rtf", "Copy as Rich Text", keys: "⌥⌘C") { [weak self] in self?.copyCurrentDocument(asMarkdown: false) }
            add("export-pdf", "Export as PDF…", keys: "⌘⇧E") { [weak self] in self?.exportPDF() }
            add("all-docs", "All Documents", keys: "⌘P") { [weak self] in self?.showGallery() }
        } else if galleryOnScreen || showingDaily {
            add("new-doc", "New Document", keys: "⌘N") { [weak self] in self?.newDocument() }
            add("today", "Today's Note", keys: "⌘3  ⌘D") { [weak self] in self?.openTodaysNote() }
            add("daily", showingDaily ? "All Documents" : "Timelapse", keys: showingDaily ? "⌘1  Esc" : "⌘2  Esc") { [weak self] in
                guard let self else { return }
                if self.showingDaily { self.showGallery() } else { self.showDaily() }
            }
            if showingDaily {
                let everything = settings.data.timelapseScope == .everything
                add("scope", everything ? "Timelapse: the daily notes alone" : "Timelapse: everything, day by day", keys: "⇥") { [weak self] in
                    self?.settings.data.timelapseScope = everything ? .notes : .everything
                }
            } else {
                for mode in SortMode.allCases {
                    add("sort-\(mode.rawValue)", "Sort by \(mode.label.lowercased())", current: settings.data.sortDocumentsBy == mode) { [weak self] in self?.settings.data.sortDocumentsBy = mode }
                }
            }
            add("search", "Search", keys: "⌘F") { [weak self] in self?.focusSearch() }
            if let doc = document, let ref = library.document(withID: doc.relativePath) {
                add("back", "Back to “\(ref.title)”") { [weak self] in
                    self?.showingDaily = false
                    self?.showingGallery = false
                }
            }
        } else {
            add("all-docs", "All Documents", keys: "⌘P") { [weak self] in self?.showGallery() }
            add("review", "Review", keys: "⌘↩  ⌘⇧S") { [weak self] in self?.toggleReview() }
            add("beside", settings.data.reviewBeside ? "Put away the page beside the editor" : "Review beside the editor", keys: "⌘⇧↩") { [weak self] in self?.toggleReviewBeside() }
            add("today", "Today's Note", keys: "⌘3  ⌘D") { [weak self] in self?.openTodaysNote() }
            add("daily", "Timelapse", keys: "⌘2") { [weak self] in self?.showDaily() }
            add("new-doc", "New Document", keys: "⌘N") { [weak self] in self?.newDocument() }
            add("typewriter", "\(settings.data.typewriterMode ? "Turn off" : "Turn on") typewriter scrolling", keys: "⌃⌘T") { [weak self] in self?.toggleTypewriter() }
            add("focus", "\(settings.data.focusMode ? "Turn off" : "Turn on") focus mode", keys: "⌃⌘F") { [weak self] in self?.toggleFocus() }
            add("syntax", settings.data.hideSyntax ? "Show Markdown syntax" : "Hide Markdown syntax", keys: "⌃⌘M") { [weak self] in self?.toggleHideSyntax() }
            add("copy-md", "Copy as Markdown", keys: "⌘⇧C") { [weak self] in self?.copyCurrentDocument(asMarkdown: true) }
            add("copy-rtf", "Copy as Rich Text", keys: "⌥⌘C") { [weak self] in self?.copyCurrentDocument(asMarkdown: false) }
            add("export-pdf", "Export as PDF…", keys: "⌘⇧E") { [weak self] in self?.exportPDF() }
            if let doc = document, !doc.isLoose {
                let id = doc.relativePath
                add("star", settings.isStarred(id) ? "Unstar" : "Star") { [weak self] in self?.toggleStar(id) }
                add("rename", "Rename…", keys: "⌘R") { [weak self] in self?.promptRename(id, isFolder: false) }
                add("duplicate", "Duplicate") { [weak self] in self?.duplicate(id) }
            }
            add("shelve", currentDocumentIsShelved ? "Unshelve" : "Shelve", keys: "⌘⇧⌫") { [weak self] in self?.toggleShelvedCurrentDocument() }
            if keepsPagesOpen {
                add("close-page", "Close page", keys: "⌘W") { [weak self] in self?.closeCurrentPage() }
                if openPages.count > 1 {
                    add("close-other-pages", "Close other pages", keys: "⌥⌘W") { [weak self] in self?.closeOtherPages() }
                    add("close-all-pages", "Close all pages", keys: "⌥⇧⌘W") { [weak self] in self?.closeAllPages() }
                    add("previous-page", "Previous page", keys: "⌥⇥") { [weak self] in self?.switchToPreviousPage() }
                }
                // Every open page by name, for a jump without the carousel.
                for id in openPages where id != document?.relativePath {
                    if let ref = library.document(withID: id) {
                        add("page-\(id)", "Page: \(ref.title)") { [weak self] in self?.switchToPage(id) }
                    }
                }
            }
            add("search", "Search", keys: "⌘F") { [weak self] in self?.focusSearch() }
        }

        let wearing = currentLook?.id
        for l in looks.all {
            add("look-\(l.id)", "Look: \(l.name)", current: wearing == l.id) { [weak self] in self?.applyLook(l) }
        }
        add("float", settings.data.floatOnTop ? "Stop Floating on Top" : "Float on Top", keys: "⌘.") { [weak self] in self?.toggleFloating() }
        if sync.isConnected {
            add("sync", "Sync now") { [weak self] in self?.sync.sync() }
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
        // The query and the highlight are reset when the bar next opens
        // (toggleCommandBar); clearing them here refilled the list under
        // the card as it faded.
        showingCommandBar = false
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
    /// ⌃⌘M: Markdown markers leave the page, or come back.
    func toggleHideSyntax() {
        settings.data.hideSyntax.toggle()
        showNotice(settings.data.hideSyntax ? "Markdown hidden" : "Markdown shown")
    }

    func adjustFontSize(by delta: Double) {
        if reviewMode && !showingGallery {
            settings.data.reviewFontScale = min(2.0, max(0.6, (settings.data.reviewFontScale + delta * 0.08).rounded(toPlaces: 2)))
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
        document?.closeNow()
        settings.saveNow()
    }
}

enum WelcomeDocument {
    static let text = """
    # Welcome to Glassine

    Glassine is a quiet place to write. Everything you type is saved as you go, into a plain Markdown file any other app can read — in a Glassine folder in iCloud Drive, so it is already on your other Macs. **File → Reveal Library in Finder** shows where.

    ## The window

    The colour behind this page is a backdrop — Soft Sky, three deep colours drifting slowly — and the page over it is a theme, Midnight. Together they are a look. **Settings → Look** has eight to pick from, and whatever you make of them — another theme, a set of colours of your own, the desktop instead — can be saved as a look, and exported as a file for another Mac or another person.

    ## A few things to try

    - Watch the caret glide as you type. Leave it alone for a few seconds and it may do a trick. Both are tuned under **Settings → Caret**.
    - ⌘S hides the sidebar; ⌘S brings it back. ⌘1 shows every document as a wall of cards, ⌘2 is Timelapse — today's note in front, earlier days receding behind it — ⌘3 is today's note, and ⌘F searches everything you have written.
    - ⌘K opens a command bar with whatever makes sense where you are. ⌘/ shows every shortcut on one card.
    - ⌘↩ shows this page the way a reader will see it, in any of fourteen styles; Esc comes back. ⌘⇧↩ keeps that page beside the editor, following as you write.
    - Typewriter scrolling (⌃⌘T) and focus mode (⌃⌘F) are both on. Turn either off and see which you miss.
    - The file's name follows the first line of the document. Change this heading and watch the sidebar.
    - ⌘D opens today's note, like ⌘3. Type @today, @yesterday or @tomorrow and a space anywhere.

    ## Markdown, lightly styled

    Syntax stays visible but steps back: **bold**, *italic*, `inline code`, ~~struck~~, ==a chip==, and [links](https://glassine.ink). Select a few words and a bar appears over them; type / at the start of a line for a menu of headings, lists, tasks and dates. ⌃⌘M takes the marks off the page altogether, except in the sentence you are writing.

    > Quotes get a little room to breathe.

    1. Numbered lists continue when you press Return.
    2. So do bullets.
    - [ ] Tasks too — ⌘⇧L toggles the checkbox, and a finished task sinks to the bottom of its list.

    Tags like #ideas or #draft show up in the sidebar, so a note can live in more than one place.

    ## Settings, and a second Mac

    ⌘, opens Settings: a rail of sections, a search box that finds any setting by name, and ⌘Z to take a change back. Under Library, the whole library can also be kept in a private GitHub repository of yours — for a Mac you would rather not sign into iCloud on, and a history of every version of every note.

    ---

    Write something.
    """
}

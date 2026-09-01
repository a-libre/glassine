import SwiftUI

/// Craft-style library sidebar: header, search, New Document, Recents, Starred,
/// Folders (tree), Tags.
struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @FocusState private var searchFocused: Bool
    @State private var recentsExpanded = true
    @State private var starredExpanded = true
    @State private var tagsExpanded = true

    private var theme: Theme { state.theme }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 8)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    allDocumentsRow
                    newDocumentRow
                    todayRow
                        .padding(.bottom, 8)
                    if let filtered = state.filteredDocuments {
                        filterHeader
                        if filtered.isEmpty {
                            emptyLabel("Nothing matches")
                        }
                        ForEach(keyed(filtered, "search")) { item in
                            DocumentRow(doc: item.doc, depth: 0, showsFolder: true)
                        }
                    } else {
                        if !state.recentDocuments.isEmpty {
                            SectionHeader(title: "Recents", expanded: $recentsExpanded)
                            if recentsExpanded {
                                ForEach(keyed(Array(state.recentDocuments.prefix(6)), "recent")) { item in
                                    DocumentRow(doc: item.doc, depth: 0, showsFolder: true)
                                }
                            }
                        }
                        if !state.starredDocuments.isEmpty {
                            SectionHeader(title: "Starred", expanded: $starredExpanded)
                                .padding(.top, 10)
                            if starredExpanded {
                                ForEach(keyed(state.starredDocuments, "starred")) { item in
                                    DocumentRow(doc: item.doc, depth: 0, showsFolder: true)
                                }
                            }
                        }
                        SectionHeader(title: "Documents", expanded: .constant(true), trailing: {
                            AnyView(HStack(spacing: 2) {
                                SidebarIconButton(systemName: "folder.badge.plus", help: "New Folder (⌘⇧N)") {
                                    state.promptNewFolder(in: "")
                                }
                                SortMenu()
                            })
                        })
                        .padding(.top, 10)
                        FolderContents(folder: state.library.root, depth: 0)
                        if !state.library.tags.isEmpty {
                            SectionHeader(title: "Tags", expanded: $tagsExpanded)
                                .padding(.top, 10)
                            if tagsExpanded {
                                ForEach(state.library.tags) { tag in
                                    TagRow(tag: tag)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 8)
            }
            footer
        }
        .frame(maxHeight: .infinity)
        .foregroundStyle(theme.text.color)
        .onExitCommand { searchFocused = false; state.searchText = "" }
        .onAppear { takeSearchFocusIfAsked() }
        .onChange(of: state.searchFocusRequest) { _, _ in takeSearchFocusIfAsked() }
        .background(sidebarBackground)
    }

    /// ⌘F lands here unless the mosaic is showing (it has its own box).
    private func takeSearchFocusIfAsked() {
        guard state.searchFocusPending, !state.galleryOnScreen else { return }
        state.searchFocusPending = false
        DispatchQueue.main.async { searchFocused = true }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 68) // room for the traffic lights
            Text("Glassine")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .opacity(0.55)
            Spacer()
            SidebarIconButton(systemName: "sidebar.left", help: "Hide Sidebar (⌘S)") {
                state.toggleSidebar()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .padding(.top, 6)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .opacity(0.45)
            TextField("Search", text: $state.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($searchFocused)
                .onSubmit {
                    if let first = state.filteredDocuments?.first { state.open(first) }
                }
            if !state.searchText.isEmpty {
                Button {
                    state.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).opacity(0.45)
                }
                .buttonStyle(.plain)
            } else if !searchFocused {
                Text("⌘F")
                    .font(.system(size: 10.5))
                    .opacity(0.3)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .help("Search titles, tags and text (⌘F)")
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(theme.text.color.opacity(theme.isDark ? 0.07 : 0.05))
        )
    }

    private var allDocumentsRow: some View {
        Button {
            state.toggleGallery()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accent.color)
                    .frame(width: 18)
                Text("All Documents")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("⌘P")
                    .font(.system(size: 11))
                    .opacity(0.35)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle(theme: theme, selected: state.showingGallery))
    }

    private var todayRow: some View {
        Button {
            state.showDaily()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accent.color)
                    .frame(width: 18)
                Text("Today")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("⌘⇧D")
                    .font(.system(size: 11))
                    .opacity(0.35)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle(theme: theme, selected: state.showingDaily))
        .help("The Daily timeline — today in front, earlier days behind. ⌘D jumps straight into today's note.")
    }

    private var newDocumentRow: some View {
        Button {
            state.newDocument()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accent.color)
                    .frame(width: 18)
                Text("New Document")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text("⌘N")
                    .font(.system(size: 11))
                    .opacity(0.35)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle(theme: theme, selected: false))
    }

    private var filterHeader: some View {
        HStack(spacing: 6) {
            if let tag = state.tagFilter {
                Text("#\(tag)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent.color)
                Button {
                    state.tagFilter = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).opacity(0.45)
                }
                .buttonStyle(.plain)
            } else {
                Text("Results")
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.5)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
    }

    private func emptyLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .italic()
            .opacity(0.4)
            .padding(.horizontal, 8)
            .frame(height: 26)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: state.library.isInICloud ? "icloud" : "folder")
                .font(.system(size: 11))
                .opacity(0.4)
            Text(state.library.isInICloud ? "iCloud Drive" : state.library.rootURL.lastPathComponent)
                .font(.system(size: 11))
                .opacity(0.4)
                .lineLimit(1)
            Spacer()
            Text("\(state.library.allDocuments.count)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.35)
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .opacity(0.5)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
    }

    @ViewBuilder
    private var sidebarTint: Color { theme.sidebarTintColor.asColor }
    private var dividerLine: Color { theme.text.color.opacity(theme.isDark ? 0.09 : 0.08) }

    private var sidebarBackground: some View {
        ZStack {
            VisualEffectBackground(material: .sidebar)
            LinearGradient(
                colors: [sidebarTint.opacity(theme.sidebarOpacity), sidebarTint.opacity(theme.sidebarOpacity * 0.7)],
                startPoint: .top, endPoint: .bottom
            )
            HStack {
                Spacer()
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: dividerLine, location: 0.1),
                            .init(color: dividerLine, location: 0.9), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: 1)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Rows

/// The same document can appear in several sidebar sections; SwiftUI needs
/// distinct identities for each appearance.
struct KeyedDoc: Identifiable {
    let section: String
    let doc: DocumentRef
    var id: String { section + "|" + doc.id }
}

func keyed(_ docs: [DocumentRef], _ section: String) -> [KeyedDoc] {
    docs.map { KeyedDoc(section: section, doc: $0) }
}

struct SectionHeader: View {
    let title: String
    @Binding var expanded: Bool
    var trailing: (() -> AnyView)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .semibold))
                        .kerning(0.6)
                        .opacity(0.45)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .opacity(0.3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            if let trailing { trailing() }
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
    }
}

struct FolderContents: View {
    @EnvironmentObject var state: AppState
    let folder: LibraryFolder
    let depth: Int

    var body: some View {
        ForEach(folder.folders) { sub in
            FolderRow(folder: sub, depth: depth)
        }
        ForEach(keyed(state.sorted(folder.documents), "tree")) { item in
            DocumentRow(doc: item.doc, depth: depth)
        }
        if folder.isRoot && folder.folders.isEmpty && folder.documents.isEmpty {
            Text("No documents yet")
                .font(.system(size: 12)).italic().opacity(0.4)
                .padding(.horizontal, 8).frame(height: 26)
        }
    }
}

struct FolderRow: View {
    @EnvironmentObject var state: AppState
    let folder: LibraryFolder
    let depth: Int
    @State private var hovering = false

    private var expanded: Bool { state.settings.isExpanded(folder.id) }
    private var isTarget: Bool { state.selectedFolder == folder.id }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                state.settings.setExpanded(folder.id, !expanded)
            }
            state.selectedFolder = folder.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .opacity(0.35)
                    .frame(width: 10)
                Image(systemName: expanded ? "folder" : "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(state.theme.accent.color.opacity(0.85))
                    .frame(width: 16)
                Text(folder.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text("\(folder.allDocuments.count)")
                    .font(.system(size: 10.5, design: .rounded))
                    .opacity(hovering ? 0 : 0.3)
                if hovering {
                    SidebarIconButton(systemName: "plus", help: "New Document in \(folder.name)") {
                        state.newDocument(in: folder.id)
                    }
                }
            }
            .padding(.leading, CGFloat(depth) * 14 + 6)
            .padding(.trailing, 6)
            .frame(height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle(theme: state.theme, selected: false, emphasized: isTarget))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("New Document Here") { state.newDocument(in: folder.id) }
            Button("New Subfolder…") { state.promptNewFolder(in: folder.id) }
            Divider()
            Button("Rename…") { state.promptRename(folder.id, isFolder: true) }
            Button("Reveal in Finder") { state.library.revealInFinder(folder.id) }
            Divider()
            Button("Move to Trash", role: .destructive) { state.trash(folder.id) }
        }
        if expanded {
            FolderContents(folder: folder, depth: depth + 1)
        }
    }
}

struct DocumentRow: View {
    @EnvironmentObject var state: AppState
    let doc: DocumentRef
    let depth: Int
    var showsFolder: Bool = false
    @State private var hovering = false

    private var selected: Bool { state.selection == doc.id }
    private var starred: Bool { state.settings.isStarred(doc.id) }

    var body: some View {
        Button {
            state.open(doc)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .opacity(selected ? 0.9 : 0.5)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(doc.title)
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                        .lineLimit(1)
                    if showsFolder && !doc.folder.isEmpty {
                        Text(doc.folder)
                            .font(.system(size: 10.5))
                            .opacity(0.4)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(state.theme.accent.color.opacity(0.8))
                }
            }
            .padding(.leading, CGFloat(depth) * 14 + (depth > 0 ? 22 : 8))
            .padding(.trailing, 8)
            .frame(height: showsFolder && !doc.folder.isEmpty ? 34 : 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle(theme: state.theme, selected: selected))
        .onHover { hovering = $0 }
        .help(doc.modified.shortRelative)
        .contextMenu {
            Button(starred ? "Unstar" : "Star") { state.toggleStar(doc.id) }
            Button("Rename…") { state.promptRename(doc.id, isFolder: false) }
            Button("Duplicate") { state.duplicate(doc.id) }
            Divider()
            Button("Copy as Markdown") { state.copyDocument(doc, asMarkdown: true) }
            Button("Copy as Rich Text") { state.copyDocument(doc, asMarkdown: false) }
            Divider()
            Menu("Move To") {
                Button("Documents (top level)") { state.move(doc.id, toFolder: "") }
                ForEach(state.library.root.allFolders) { f in
                    Button(f.id.replacingOccurrences(of: "/", with: " / ")) { state.move(doc.id, toFolder: f.id) }
                }
            }
            Divider()
            Button("Reveal in Finder") { state.library.revealInFinder(doc.id) }
            Button("Copy Path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(doc.url.path, forType: .string)
            }
            Divider()
            Button("Move to Trash", role: .destructive) { state.trash(doc.id) }
        }
    }
}

struct TagRow: View {
    @EnvironmentObject var state: AppState
    let tag: TagInfo

    var body: some View {
        Button {
            state.tagFilter = tag.name
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "number")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(state.theme.accent.color.opacity(0.8))
                    .frame(width: 16)
                Text(tag.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer()
                Text("\(tag.count)")
                    .font(.system(size: 10.5, design: .rounded))
                    .opacity(0.3)
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowStyle(theme: state.theme, selected: false))
    }
}

struct SortMenu: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Menu {
            Picker("Sort by", selection: Binding(
                get: { state.settings.data.sortDocumentsBy },
                set: { state.settings.data.sortDocumentsBy = $0 }
            )) {
                ForEach(SortMode.allCases) { m in Text(m.label).tag(m) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 10, weight: .semibold))
                .opacity(0.5)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20, height: 20)
        .help("Sort documents")
    }
}

struct SidebarIconButton: View {
    let systemName: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11.5, weight: .semibold))
                .opacity(hovering ? 0.9 : 0.5)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Craft-like row: neutral rounded highlight when selected, faint on hover.
struct HoverRowStyle: ButtonStyle {
    let theme: Theme
    let selected: Bool
    var emphasized: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        HoverRow(theme: theme, selected: selected, emphasized: emphasized, pressed: configuration.isPressed) {
            configuration.label
        }
    }

    private struct HoverRow<Content: View>: View {
        let theme: Theme
        let selected: Bool
        let emphasized: Bool
        let pressed: Bool
        @ViewBuilder let content: () -> Content
        @State private var hovering = false

        var body: some View {
            content()
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(theme.text.color.opacity(fillOpacity))
                )
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var fillOpacity: Double {
            let dark = theme.isDark
            if selected { return dark ? 0.13 : 0.10 }
            if pressed { return dark ? 0.10 : 0.08 }
            if hovering { return dark ? 0.06 : 0.045 }
            if emphasized { return dark ? 0.035 : 0.025 }
            return 0
        }
    }
}

extension NSColor {
    var asColor: Color { Color(nsColor: self) }
}

import AppKit
import SwiftUI

enum CaretBlink: String, Codable, CaseIterable, Identifiable {
    case soft, hard, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .soft: return "Soft"
        case .hard: return "Classic"
        case .none: return "Never"
        }
    }
}

enum FocusScope: String, Codable, CaseIterable, Identifiable {
    case paragraph, sentence
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum CounterMode: String, Codable, CaseIterable, Identifiable {
    case words, characters, readingTime, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .words: return "Words"
        case .characters: return "Characters"
        case .readingTime: return "Reading time"
        case .all: return "Everything"
        }
    }
}

enum SortMode: String, Codable, CaseIterable, Identifiable {
    case modified, name, created
    var id: String { rawValue }
    var label: String {
        switch self {
        case .modified: return "Last edited"
        case .name: return "Name"
        case .created: return "Date created"
        }
    }
}

/// Font family sentinels for system fonts.
enum SystemFontChoice {
    static let sans = "__system__"
    static let serif = "__serif__"
    static let mono = "__mono__"
    static let rounded = "__rounded__"

    static let all: [(id: String, label: String)] = [
        (serif, "New York (system serif)"),
        (sans, "San Francisco (system)"),
        (rounded, "SF Rounded"),
        (mono, "SF Mono"),
    ]
}

struct SettingsData: Codable, Equatable {
    // Library
    var libraryPath: String? = nil
    var nameFilesFromFirstLine: Bool = true
    var sortDocumentsBy: SortMode = .modified
    var lastOpenedDocument: String? = nil

    // Typography
    var fontFamily: String = SystemFontChoice.serif
    var fontSize: Double = 18
    var lineHeight: Double = 1.55
    var paragraphSpacing: Double = 0.65
    var columnWidth: Double = 660
    var letterSpacing: Double = 0
    var scaledHeadings: Bool = true
    var topInset: Double = 96

    // Caret
    var smoothCaret: Bool = true
    var caretSpeed: Double = 0.11
    var smoothWhileTyping: Bool = true
    var caretBlink: CaretBlink = .soft
    var caretWidth: Double = 2

    // Modes
    var typewriterMode: Bool = false
    var typewriterOnClick: Bool = false
    var focusMode: Bool = false
    var focusScope: FocusScope = .paragraph
    var showCounter: Bool = true
    var counterMode: CounterMode = .words

    // Text behaviors
    var smartQuotes: Bool = true
    var smartDashes: Bool = false
    var autocorrect: Bool = false
    var spellCheck: Bool = true
    var inlinePredictions: Bool = false
    var continueLists: Bool = true

    // Layout
    var sidebarVisible: Bool = true
    var sidebarWidth: Double = 250
    var expandedFolders: [String] = []
    var starred: [String] = []
    var recents: [String: Date] = [:]
    var caretPositions: [String: Int] = [:]

    // Theme
    var themeID: String = "graphite"

    // Review mode
    var reviewStyle: ReviewStyle = .glass
    var reviewFontScale: Double = 1.0

    init() {}

    // Tolerant decoding so new fields can be added without invalidating saved settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SettingsData()
        libraryPath = try c.decodeIfPresent(String.self, forKey: .libraryPath) ?? d.libraryPath
        nameFilesFromFirstLine = try c.decodeIfPresent(Bool.self, forKey: .nameFilesFromFirstLine) ?? d.nameFilesFromFirstLine
        sortDocumentsBy = try c.decodeIfPresent(SortMode.self, forKey: .sortDocumentsBy) ?? d.sortDocumentsBy
        lastOpenedDocument = try c.decodeIfPresent(String.self, forKey: .lastOpenedDocument) ?? d.lastOpenedDocument
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? d.fontFamily
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? d.lineHeight
        paragraphSpacing = try c.decodeIfPresent(Double.self, forKey: .paragraphSpacing) ?? d.paragraphSpacing
        columnWidth = try c.decodeIfPresent(Double.self, forKey: .columnWidth) ?? d.columnWidth
        letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? d.letterSpacing
        scaledHeadings = try c.decodeIfPresent(Bool.self, forKey: .scaledHeadings) ?? d.scaledHeadings
        topInset = try c.decodeIfPresent(Double.self, forKey: .topInset) ?? d.topInset
        smoothCaret = try c.decodeIfPresent(Bool.self, forKey: .smoothCaret) ?? d.smoothCaret
        caretSpeed = try c.decodeIfPresent(Double.self, forKey: .caretSpeed) ?? d.caretSpeed
        smoothWhileTyping = try c.decodeIfPresent(Bool.self, forKey: .smoothWhileTyping) ?? d.smoothWhileTyping
        caretBlink = try c.decodeIfPresent(CaretBlink.self, forKey: .caretBlink) ?? d.caretBlink
        caretWidth = try c.decodeIfPresent(Double.self, forKey: .caretWidth) ?? d.caretWidth
        typewriterMode = try c.decodeIfPresent(Bool.self, forKey: .typewriterMode) ?? d.typewriterMode
        typewriterOnClick = try c.decodeIfPresent(Bool.self, forKey: .typewriterOnClick) ?? d.typewriterOnClick
        focusMode = try c.decodeIfPresent(Bool.self, forKey: .focusMode) ?? d.focusMode
        focusScope = try c.decodeIfPresent(FocusScope.self, forKey: .focusScope) ?? d.focusScope
        showCounter = try c.decodeIfPresent(Bool.self, forKey: .showCounter) ?? d.showCounter
        counterMode = try c.decodeIfPresent(CounterMode.self, forKey: .counterMode) ?? d.counterMode
        smartQuotes = try c.decodeIfPresent(Bool.self, forKey: .smartQuotes) ?? d.smartQuotes
        smartDashes = try c.decodeIfPresent(Bool.self, forKey: .smartDashes) ?? d.smartDashes
        autocorrect = try c.decodeIfPresent(Bool.self, forKey: .autocorrect) ?? d.autocorrect
        spellCheck = try c.decodeIfPresent(Bool.self, forKey: .spellCheck) ?? d.spellCheck
        inlinePredictions = try c.decodeIfPresent(Bool.self, forKey: .inlinePredictions) ?? d.inlinePredictions
        continueLists = try c.decodeIfPresent(Bool.self, forKey: .continueLists) ?? d.continueLists
        sidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? d.sidebarVisible
        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? d.sidebarWidth
        expandedFolders = try c.decodeIfPresent([String].self, forKey: .expandedFolders) ?? d.expandedFolders
        starred = try c.decodeIfPresent([String].self, forKey: .starred) ?? d.starred
        recents = try c.decodeIfPresent([String: Date].self, forKey: .recents) ?? d.recents
        caretPositions = try c.decodeIfPresent([String: Int].self, forKey: .caretPositions) ?? d.caretPositions
        themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? d.themeID
        reviewStyle = try c.decodeIfPresent(ReviewStyle.self, forKey: .reviewStyle) ?? d.reviewStyle
        reviewFontScale = try c.decodeIfPresent(Double.self, forKey: .reviewFontScale) ?? d.reviewFontScale
    }
}

final class AppSettings: ObservableObject {
    static let defaultsKey = "glassine.settings.v1"

    @Published var data: SettingsData {
        didSet { scheduleSave() }
    }

    private let saveDebouncer = Debouncer(delay: 0.3)

    init() {
        if let raw = UserDefaults.standard.data(forKey: AppSettings.defaultsKey),
           let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded
        } else if let raw = Legacy.defaultsData(forKey: "pyrus.settings.v1"),
                  let decoded = try? JSONDecoder().decode(SettingsData.self, from: raw) {
            data = decoded
            UserDefaults.standard.set(raw, forKey: AppSettings.defaultsKey)
        } else {
            data = SettingsData()
        }
    }

    private func scheduleSave() {
        saveDebouncer.call { [weak self] in self?.saveNow() }
    }

    func saveNow() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: AppSettings.defaultsKey)
        }
    }

    // MARK: - Convenience

    func touchRecent(_ relPath: String) {
        data.recents[relPath] = Date()
        if data.recents.count > 40 {
            let sorted = data.recents.sorted { $0.value > $1.value }
            data.recents = Dictionary(uniqueKeysWithValues: sorted.prefix(40).map { ($0.key, $0.value) })
        }
    }

    func renamePath(_ old: String, to new: String) {
        if let d = data.recents.removeValue(forKey: old) { data.recents[new] = d }
        if let i = data.starred.firstIndex(of: old) { data.starred[i] = new }
        if let p = data.caretPositions.removeValue(forKey: old) { data.caretPositions[new] = p }
        if data.lastOpenedDocument == old { data.lastOpenedDocument = new }
        // Folder renames: fix children too.
        let oldPrefix = old + "/"
        let newPrefix = new + "/"
        for (k, v) in data.recents where k.hasPrefix(oldPrefix) {
            data.recents.removeValue(forKey: k)
            data.recents[newPrefix + k.dropFirst(oldPrefix.count)] = v
        }
        data.starred = data.starred.map { $0.hasPrefix(oldPrefix) ? newPrefix + $0.dropFirst(oldPrefix.count) : $0 }
        data.expandedFolders = data.expandedFolders.map { $0 == old ? new : ($0.hasPrefix(oldPrefix) ? newPrefix + $0.dropFirst(oldPrefix.count) : $0) }
    }

    func forgetPath(_ relPath: String) {
        data.recents.removeValue(forKey: relPath)
        data.starred.removeAll { $0 == relPath || $0.hasPrefix(relPath + "/") }
        data.caretPositions.removeValue(forKey: relPath)
        if data.lastOpenedDocument == relPath { data.lastOpenedDocument = nil }
    }

    func isStarred(_ relPath: String) -> Bool { data.starred.contains(relPath) }

    func toggleStar(_ relPath: String) {
        if let i = data.starred.firstIndex(of: relPath) {
            data.starred.remove(at: i)
        } else {
            data.starred.append(relPath)
        }
    }

    func isExpanded(_ folderPath: String) -> Bool { data.expandedFolders.contains(folderPath) }

    func setExpanded(_ folderPath: String, _ expanded: Bool) {
        if expanded {
            if !data.expandedFolders.contains(folderPath) { data.expandedFolders.append(folderPath) }
        } else {
            data.expandedFolders.removeAll { $0 == folderPath }
        }
    }
}

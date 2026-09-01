import AppKit
import SwiftUI

enum GlassMaterial: String, Codable, CaseIterable, Identifiable {
    case underWindow, hud, sidebar, popover, titlebar, opaque

    var id: String { rawValue }

    var label: String {
        switch self {
        case .underWindow: return "Soft glass"
        case .hud: return "Deep glass"
        case .sidebar: return "Sidebar glass"
        case .popover: return "Thin glass"
        case .titlebar: return "Frosted"
        case .opaque: return "Opaque (no glass)"
        }
    }

    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .underWindow: return .underWindowBackground
        case .hud: return .hudWindow
        case .sidebar: return .sidebar
        case .popover: return .popover
        case .titlebar: return .titlebar
        case .opaque: return .windowBackground
        }
    }
}

struct Theme: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var isBuiltIn: Bool = false
    var isDark: Bool = true

    var material: GlassMaterial = .underWindow
    var tint: HexColor
    var tintOpacity: Double
    var grain: Double = 0

    var text: HexColor
    var accent: HexColor
    var syntax: HexColor
    var heading: HexColor? = nil
    var quote: HexColor? = nil
    var code: HexColor? = nil
    var codeBackground: HexColor? = nil
    var link: HexColor? = nil
    var caret: HexColor? = nil
    var selection: HexColor? = nil
    var sidebarTint: HexColor? = nil
    var sidebarOpacity: Double = 0.3

    // Resolved colors
    var headingColor: NSColor { (heading ?? text).nsColor }
    var quoteColor: NSColor { quote?.nsColor ?? text.withAlpha(0.72) }
    var codeColor: NSColor { code?.nsColor ?? text.withAlpha(0.9) }
    var codeBackgroundColor: NSColor { codeBackground?.nsColor ?? text.withAlpha(isDark ? 0.08 : 0.06) }
    var linkColor: NSColor { (link ?? accent).nsColor }
    var caretColor: NSColor { (caret ?? accent).nsColor }
    var selectionColor: NSColor { selection?.nsColor ?? accent.withAlpha(0.32) }
    var sidebarTintColor: NSColor { (sidebarTint ?? tint).nsColor }

    var colorScheme: ColorScheme { isDark ? .dark : .light }

    func renamed(_ newName: String, id newID: String = UUID().uuidString) -> Theme {
        var t = self
        t.id = newID
        t.name = newName
        t.isBuiltIn = false
        return t
    }
}

extension Theme {
    static let graphite = Theme(
        id: "graphite", name: "Graphite", isBuiltIn: true, isDark: true,
        material: .underWindow, tint: HexColor("#141416"), tintOpacity: 0.55, grain: 0.0,
        text: HexColor("#E6E4E1"), accent: HexColor("#D0784A"), syntax: HexColor("#6B6B70"),
        heading: HexColor("#F2F0EC"), quote: HexColor("#B9B5AE"), code: HexColor("#DCD7CF"),
        codeBackground: HexColor("#FFFFFF12"), link: HexColor("#D0784A"), caret: HexColor("#D0784A"),
        selection: HexColor("#D0784A4D"), sidebarTint: HexColor("#0E0E10"), sidebarOpacity: 0.35
    )

    static let sepiaNight = Theme(
        id: "sepia-night", name: "Sepia Night", isBuiltIn: true, isDark: true,
        material: .hud, tint: HexColor("#1B1512"), tintOpacity: 0.62, grain: 0.03,
        text: HexColor("#EADBC8"), accent: HexColor("#C64B21"), syntax: HexColor("#7A6A5C"),
        heading: HexColor("#F6E9D6"), quote: HexColor("#C4B09A"), code: HexColor("#E5D3BA"),
        codeBackground: HexColor("#FFFFFF10"), link: HexColor("#E0895F"), caret: HexColor("#E0895F"),
        selection: HexColor("#C64B2155"), sidebarTint: HexColor("#120E0C"), sidebarOpacity: 0.4
    )

    static let midnight = Theme(
        id: "midnight", name: "Midnight", isBuiltIn: true, isDark: true,
        material: .underWindow, tint: HexColor("#0A0F1E"), tintOpacity: 0.5, grain: 0.0,
        text: HexColor("#DCE2F0"), accent: HexColor("#6FA8FF"), syntax: HexColor("#4E5A78"),
        heading: HexColor("#F0F4FF"), quote: HexColor("#A7B3CF"), code: HexColor("#CFE0FF"),
        codeBackground: HexColor("#FFFFFF12"), link: HexColor("#8DBBFF"), caret: HexColor("#6FA8FF"),
        selection: HexColor("#6FA8FF4D"), sidebarTint: HexColor("#060914"), sidebarOpacity: 0.35
    )

    static let moss = Theme(
        id: "moss", name: "Moss", isBuiltIn: true, isDark: true,
        material: .underWindow, tint: HexColor("#0F1512"), tintOpacity: 0.55, grain: 0.02,
        text: HexColor("#DCE7DC"), accent: HexColor("#84BF39"), syntax: HexColor("#5C6E5C"),
        heading: HexColor("#EEF6EE"), quote: HexColor("#AFC2AF"), code: HexColor("#D4E6C8"),
        codeBackground: HexColor("#FFFFFF10"), link: HexColor("#9ED35A"), caret: HexColor("#84BF39"),
        selection: HexColor("#84BF3944"), sidebarTint: HexColor("#0A0F0C"), sidebarOpacity: 0.35
    )

    static let frost = Theme(
        id: "frost", name: "Frost", isBuiltIn: true, isDark: false,
        material: .underWindow, tint: HexColor("#F6F7FA"), tintOpacity: 0.55, grain: 0.0,
        text: HexColor("#26282E"), accent: HexColor("#3F8DE0"), syntax: HexColor("#B4B8C2"),
        heading: HexColor("#141519"), quote: HexColor("#6B6F7A"), code: HexColor("#33363F"),
        codeBackground: HexColor("#00000010"), link: HexColor("#3F8DE0"), caret: HexColor("#3F8DE0"),
        selection: HexColor("#3F8DE03D"), sidebarTint: HexColor("#FFFFFF"), sidebarOpacity: 0.35
    )

    static let paper = Theme(
        id: "paper", name: "Paper", isBuiltIn: true, isDark: false,
        material: .titlebar, tint: HexColor("#FBFAF8"), tintOpacity: 0.9, grain: 0.05,
        text: HexColor("#2C1611"), accent: HexColor("#C64B21"), syntax: HexColor("#CBC3BE"),
        heading: HexColor("#1F0F0B"), quote: HexColor("#7A6560"), code: HexColor("#3D2A25"),
        codeBackground: HexColor("#0000000C"), link: HexColor("#C64B21"), caret: HexColor("#C64B21"),
        selection: HexColor("#C64B2138"), sidebarTint: HexColor("#F3F0EC"), sidebarOpacity: 0.7
    )

    static let builtIns: [Theme] = [graphite, sepiaNight, midnight, moss, frost, paper]
}

final class ThemeStore: ObservableObject {
    static let defaultsKey = "glassine.customThemes.v1"

    @Published var custom: [Theme] {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: ThemeStore.defaultsKey),
           let decoded = try? JSONDecoder().decode([Theme].self, from: data) {
            custom = decoded
        } else if let data = Legacy.defaultsData(forKey: "pyrus.customThemes.v1"),
                  let decoded = try? JSONDecoder().decode([Theme].self, from: data) {
            custom = decoded
            UserDefaults.standard.set(data, forKey: ThemeStore.defaultsKey)
        } else {
            custom = []
        }
    }

    var all: [Theme] { Theme.builtIns + custom }

    func theme(id: String) -> Theme {
        all.first(where: { $0.id == id }) ?? Theme.graphite
    }

    func update(_ theme: Theme) {
        guard !theme.isBuiltIn else { return }
        if let i = custom.firstIndex(where: { $0.id == theme.id }) {
            custom[i] = theme
        } else {
            custom.append(theme)
        }
    }

    @discardableResult
    func duplicate(_ theme: Theme) -> Theme {
        let copy = theme.renamed(theme.name + " Copy")
        custom.append(copy)
        return copy
    }

    func delete(_ theme: Theme) {
        custom.removeAll { $0.id == theme.id }
    }

    func importTheme(from url: URL) throws -> Theme {
        let data = try Data(contentsOf: url)
        var t = try JSONDecoder().decode(Theme.self, from: data)
        t.isBuiltIn = false
        if all.contains(where: { $0.id == t.id }) { t.id = UUID().uuidString }
        custom.append(t)
        return t
    }

    func export(_ theme: Theme, to url: URL) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(theme).write(to: url)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: ThemeStore.defaultsKey)
        }
    }
}

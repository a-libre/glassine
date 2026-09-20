import AppKit
import SwiftUI

// MARK: - What a paragraph is

/// The shapes a paragraph can take, as far as the formatting bar and the slash
/// menu are concerned. Everything is still Markdown underneath.
enum BlockKind: Equatable {
    case paragraph, heading(Int), bullet, numbered, task, quote
}

extension GlassineTextView {
    /// indent · heading hashes · quote mark · list marker · task state · content
    private static let partsRx = try! NSRegularExpression(
        pattern: "^([ \\t]*)(?:(#{1,6})[ \\t]+|(>)[ \\t]?|([-*+]|\\d{1,3}[.)])[ \\t]+(?:\\[([ xX])\\](?:[ \\t]+|$))?)?(.*)$")

    private struct LineParts {
        let indent: String
        let head: String      // the marker, as written
        let kind: BlockKind
        let checked: Bool
        let content: String
    }

    private static func parse(_ line: String) -> LineParts {
        let ns = line as NSString
        guard let m = partsRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return LineParts(indent: "", head: "", kind: .paragraph, checked: false, content: line)
        }
        func group(_ i: Int) -> String { m.range(at: i).location == NSNotFound ? "" : ns.substring(with: m.range(at: i)) }
        let indent = group(1)
        let content = group(6)
        let head = ns.substring(with: NSRange(location: m.range(at: 1).upperBoundValue,
                                              length: m.range(at: 6).location - m.range(at: 1).upperBoundValue))
        let kind: BlockKind
        if !group(2).isEmpty { kind = .heading(group(2).count) }
        else if !group(3).isEmpty { kind = .quote }
        else if !group(4).isEmpty {
            if m.range(at: 5).location != NSNotFound { kind = .task }
            else if group(4).first?.isNumber == true { kind = .numbered }
            else { kind = .bullet }
        } else { kind = .paragraph }
        return LineParts(indent: indent, head: head, kind: kind, checked: group(5).lowercased() == "x", content: content)
    }

    /// Makes every paragraph the selection touches into `kind`, in one undoable
    /// edit. Asking for what they all already are turns them back into plain
    /// text. A selection stays over the same words afterwards, so the bar can
    /// be used again; a caret keeps its place in its line.
    func setBlock(_ kind: BlockKind) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let sel = selectedRange()
        var span = ns.paragraphRange(for: sel)
        if span.length > 0, ns.character(at: span.upperBoundValue - 1) == 10 { span.length -= 1 }
        let old = ns.substring(with: span)
        let lines = old.components(separatedBy: "\n")
        let parsed = lines.map(Self.parse)
        let target: BlockKind = parsed.allSatisfy({ $0.kind == kind }) ? .paragraph : kind
        let keepsIndent: Bool = { if case .bullet = target { return true }; if case .numbered = target { return true }; if case .task = target { return true }; return false }()
        var number = 1
        if case .numbered = target {
            number = nextNumber(before: span.location, width: Self.indentWidth(parsed.first?.indent ?? ""))
        }
        var newLines: [String] = []
        var caret = sel.location
        var oldOffset = span.location
        var newOffset = span.location
        for (i, p) in parsed.enumerated() {
            let prefix: String
            switch target {
            case .paragraph: prefix = ""
            case .heading(let n): prefix = String(repeating: "#", count: n) + " "
            case .bullet: prefix = "- "
            case .numbered: prefix = "\(number). "; number += 1
            case .task: prefix = p.checked ? "- [x] " : "- [ ] "
            case .quote: prefix = "> "
            }
            let indent = keepsIndent ? p.indent : ""
            let line = indent + prefix + p.content
            newLines.append(line)
            let oldLength = lines[i].nsLength
            if sel.length == 0, sel.location >= oldOffset, sel.location <= oldOffset + oldLength {
                let oldHead = (p.indent + p.head).nsLength
                let newHead = (indent + prefix).nsLength
                let inLine = sel.location - oldOffset
                caret = newOffset + (inLine >= oldHead ? inLine - oldHead + newHead : newHead)
            }
            oldOffset += oldLength + 1
            newOffset += line.nsLength + 1
        }
        let text = newLines.joined(separator: "\n")
        guard text != old, shouldChangeText(in: span, replacementString: text) else { return }
        storage.replaceCharacters(in: span, with: text)
        didChangeText()
        if sel.length > 0 {
            setSelectedRange(NSRange(location: span.location, length: text.nsLength))
        } else {
            setSelectedRange(NSRange(location: min(caret, span.location + text.nsLength), length: 0))
        }
    }

    /// Puts `block` on a line of its own: in place of an empty paragraph, or on
    /// a new line after the one the caret is in. The caret lands `caretOffset`
    /// characters into the block.
    func insertOwnLine(_ block: String, caretOffset: Int) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let sel = selectedRange()
        var para = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        if para.length > 0, ns.character(at: para.upperBoundValue - 1) == 10 { para.length -= 1 }
        let empty = ns.substring(with: para).trimmingCharacters(in: .whitespaces).isEmpty
        let range = empty ? para : NSRange(location: para.upperBoundValue, length: 0)
        let text = (empty ? "" : "\n") + block + "\n"
        guard shouldChangeText(in: range, replacementString: text) else { return }
        storage.replaceCharacters(in: range, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + (empty ? 0 : 1) + caretOffset, length: 0))
    }

    /// A date capsule at the caret, like the ones `@today` makes.
    func insertDate(daysFromToday days: Int) {
        guard let storage = textStorage else { return }
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        let token = "@" + DateToken.format(date)
        let sel = selectedRange()
        guard shouldChangeText(in: sel, replacementString: token + " ") else { return }
        storage.replaceCharacters(in: sel, with: token + " ")
        didChangeText()
        setSelectedRange(NSRange(location: sel.location + token.nsLength + 1, length: 0))
        pulse(charRange: NSRange(location: sel.location, length: token.nsLength), color: config.theme.accent.nsColor, scale: 1.25, duration: 0.4)
    }
}

// MARK: - The bar over a selection

enum FormatAction: CaseIterable {
    case bold, italic, strike, code, chip, link, h1, h2, h3, bullet, numbered, task, quote

    var symbol: String? {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .strike: return "strikethrough"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .chip: return "highlighter"
        case .link: return "link"
        case .bullet: return "list.bullet"
        case .numbered: return "list.number"
        case .task: return "checklist"
        case .quote: return "text.quote"
        case .h1, .h2, .h3: return nil
        }
    }

    var glyph: String {
        switch self { case .h1: return "H1"; case .h2: return "H2"; case .h3: return "H3"; default: return "" }
    }

    var help: String {
        switch self {
        case .bold: return "Bold  ⌘B"
        case .italic: return "Italic  ⌘I"
        case .strike: return "Strikethrough  ⌘⇧X"
        case .code: return "Inline code  ⌘E"
        case .chip: return "Chip  ⌘⇧H"
        case .link: return "Link  ⌘⇧K"
        case .h1: return "Heading 1  ⌥⌘1"
        case .h2: return "Heading 2  ⌥⌘2"
        case .h3: return "Heading 3  ⌥⌘3"
        case .bullet: return "Bullet list"
        case .numbered: return "Numbered list"
        case .task: return "Task"
        case .quote: return "Quote"
        }
    }
}

/// The small bar that appears over selected text.
struct FormatBar: View {
    let theme: Theme
    let perform: (FormatAction) -> Void

    var body: some View {
        HStack(spacing: 1) {
            group([.bold, .italic, .strike, .code, .chip, .link])
            rule
            group([.h1, .h2, .h3])
            rule
            group([.bullet, .numbered, .task, .quote])
        }
        .padding(3)
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                theme.tint.color.opacity(theme.isDark ? 0.4 : 0.55)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(theme.text.color.opacity(theme.isDark ? 0.14 : 0.1), lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.38 : 0.14), radius: 12, y: 5)
        .foregroundStyle(theme.text.color)
    }

    private func group(_ actions: [FormatAction]) -> some View {
        HStack(spacing: 1) {
            ForEach(actions, id: \.self) { FormatButton(action: $0, theme: theme, perform: perform) }
        }
    }

    private var rule: some View {
        Rectangle().fill(theme.text.color.opacity(0.14)).frame(width: 1, height: 14).padding(.horizontal, 3)
    }
}

private struct FormatButton: View {
    let action: FormatAction
    let theme: Theme
    let perform: (FormatAction) -> Void
    @State private var hovering = false

    var body: some View {
        Button { perform(action) } label: {
            Group {
                if let symbol = action.symbol {
                    Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                } else {
                    Text(action.glyph).font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
            }
            .frame(width: 26, height: 24)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(theme.text.color.opacity(hovering ? 0.12 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(action.help)
    }
}

// MARK: - The slash menu

enum SlashAction {
    case block(BlockKind), codeBlock, divider, link, chip, date(Int)
}

struct SlashItem: Identifiable {
    let id: String
    let title: String
    let hint: String
    let symbol: String?
    let glyph: String
    let keywords: [String]
    let action: SlashAction

    init(_ id: String, _ title: String, hint: String, symbol: String? = nil, glyph: String = "", keywords: [String] = [], _ action: SlashAction) {
        self.id = id; self.title = title; self.hint = hint; self.symbol = symbol; self.glyph = glyph
        self.keywords = keywords; self.action = action
    }

    static let all: [SlashItem] = [
        SlashItem("h1", "Heading 1", hint: "#", glyph: "H1", keywords: ["title"], .block(.heading(1))),
        SlashItem("h2", "Heading 2", hint: "##", glyph: "H2", .block(.heading(2))),
        SlashItem("h3", "Heading 3", hint: "###", glyph: "H3", .block(.heading(3))),
        SlashItem("text", "Text", hint: "", symbol: "text.alignleft", keywords: ["paragraph", "body", "plain"], .block(.paragraph)),
        SlashItem("bullet", "Bullet list", hint: "-", symbol: "list.bullet", keywords: ["ul", "unordered"], .block(.bullet)),
        SlashItem("number", "Numbered list", hint: "1.", symbol: "list.number", keywords: ["ol", "ordered"], .block(.numbered)),
        SlashItem("task", "Task", hint: "- [ ]", symbol: "checklist", keywords: ["todo", "check", "checkbox"], .block(.task)),
        SlashItem("quote", "Quote", hint: ">", symbol: "text.quote", keywords: ["blockquote"], .block(.quote)),
        SlashItem("code", "Code block", hint: "```", symbol: "chevron.left.forwardslash.chevron.right", keywords: ["fence", "pre"], .codeBlock),
        SlashItem("divider", "Divider", hint: "---", symbol: "minus", keywords: ["rule", "hr", "line", "separator"], .divider),
        SlashItem("link", "Link", hint: "[ ]( )", symbol: "link", keywords: ["url"], .link),
        SlashItem("chip", "Chip", hint: "==", symbol: "highlighter", keywords: ["highlight", "mark", "capsule", "tag"], .chip),
        SlashItem("today", "Today", hint: "@", symbol: "calendar", keywords: ["date", "now"], .date(0)),
        SlashItem("tomorrow", "Tomorrow", hint: "@", symbol: "calendar", keywords: ["date"], .date(1)),
        SlashItem("yesterday", "Yesterday", hint: "@", symbol: "calendar", keywords: ["date"], .date(-1)),
    ]

    /// Everything, for an empty query; otherwise titles that start with it
    /// first, then titles and keywords that contain it.
    static func matching(_ query: String) -> [SlashItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        let starts = all.filter { $0.title.lowercased().hasPrefix(q) }
        let rest = all.filter { item in
            !starts.contains(where: { $0.id == item.id })
                && (item.title.lowercased().contains(q) || item.keywords.contains(where: { $0.hasPrefix(q) }))
        }
        return starts + rest
    }
}

/// The menu that opens under a slash.
struct SlashMenu: View {
    let theme: Theme
    let items: [SlashItem]
    let selection: Int
    let pick: (Int) -> Void
    let hover: (Int) -> Void

    static let rowHeight: CGFloat = 28
    static let width: CGFloat = 250
    static func height(for count: Int) -> CGFloat { CGFloat(min(count, 8)) * (rowHeight + 1) + 11 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                        Button { pick(i) } label: {
                            HStack(spacing: 9) {
                                Group {
                                    if let symbol = item.symbol {
                                        Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                                    } else {
                                        Text(item.glyph).font(.system(size: 10, weight: .bold, design: .rounded))
                                    }
                                }
                                .frame(width: 18)
                                .opacity(0.8)
                                Text(item.title).font(.system(size: 13))
                                Spacer()
                                Text(item.hint)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .opacity(0.4)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: Self.rowHeight)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(i == selection ? theme.accent.color.opacity(0.24) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { hover(i) } }
                        .id(item.id)
                    }
                }
                .padding(5)
            }
            .onChange(of: selection) { _, i in
                if i >= 0, i < items.count { proxy.scrollTo(items[i].id) }
            }
        }
        .background(
            ZStack {
                VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                theme.tint.color.opacity(theme.isDark ? 0.4 : 0.55)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(theme.text.color.opacity(theme.isDark ? 0.14 : 0.1), lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.4 : 0.15), radius: 16, y: 6)
        .foregroundStyle(theme.text.color)
    }
}

/// A hosting view that never takes the keyboard from the editor.
final class QuietHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { false }
}

import Foundation

/// The shapes a paragraph can take, as far as the formatting bar, the slash
/// menu and the Format keys are concerned. Everything is still Markdown underneath.
enum BlockKind: Equatable {
    case paragraph, heading(Int), bullet, numbered, task, quote
}

/// One change to the text and where the selection goes after it.
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

/// What a formatting key comes to: a change, only a move of the caret, or nothing.
enum EditOutcome: Equatable {
    case edit(TextEdit)
    case select(NSRange)
    case none
}

/// What the editor's keys do to Markdown, as arithmetic on a string and a
/// selection — no text view in sight, so it is the same on the Mac and on
/// iOS, and can be checked without either. A text view asks for the edit and
/// applies it through its own undoable path.
///
/// The iOS text view runs on these today. The Mac's carries the older copies
/// these were lifted from (GlassineTextView "Formatting commands", "List
/// nesting", Formatting.swift's setBlock); it moves over to these next.
enum MarkdownEdits {
    // MARK: Inline marks

    /// The span an inline mark makes, with its inner text as group 1: what the
    /// styler recognises, so toggling agrees with what is drawn.
    private static func spanRegex(for prefix: String) -> NSRegularExpression {
        let pattern: String
        switch prefix {
        case "*": pattern = "(?<![\\*\\w])\\*(?=\\S)([^*\\n]+?)(?<=\\S)\\*(?!\\*)"
        case "_": pattern = "(?<![\\w_])_(?=\\S)([^_\\n]+?)(?<=\\S)_(?![\\w_])"
        case "`": pattern = "`([^`\\n]+?)`"
        case "==": pattern = "==(?=\\S)([^=\\n]+?)(?<=\\S)=="
        default:
            let m = NSRegularExpression.escapedPattern(for: prefix)
            pattern = m + "(?=\\S)(.+?)(?<=\\S)" + m
        }
        return try! NSRegularExpression(pattern: pattern)
    }

    /// Inline marks, the way a rich-text key behaves. With a selection: wrap it,
    /// or unwrap it if it is a marked span or sits inside one. With a caret:
    /// inside a span, the key turns the mark off — at the end of the span the
    /// caret steps out past the closing mark, at the start it steps out before
    /// the opening one, in the middle the span splits around the caret. Between
    /// two marks with nothing inside, both go. Anywhere else, a placeholder
    /// arrives between fresh marks, selected, ready to be typed over.
    static func toggleMark(_ prefix: String, suffix: String? = nil, placeholder: String,
                           in ns: NSString, selection sel: NSRange) -> EditOutcome {
        let suffix = suffix ?? prefix
        // The marks right around a range, when they are exactly these and not
        // part of a longer run (so a single * is never mistaken for half of **).
        func hugged(_ range: NSRange) -> Bool {
            let before = NSRange(location: range.location - prefix.nsLength, length: prefix.nsLength)
            let after = NSRange(location: range.upperBoundValue, length: suffix.nsLength)
            guard before.location >= 0, after.upperBoundValue <= ns.length,
                  ns.substring(with: before) == prefix, ns.substring(with: after) == suffix else { return false }
            if prefix.nsLength == 1, let mark = prefix.unicodeScalars.first?.value {
                if before.location > 0, ns.character(at: before.location - 1) == mark { return false }
                if after.upperBoundValue < ns.length, ns.character(at: after.upperBoundValue) == mark { return false }
            }
            return true
        }

        if sel.length == 0 {
            // Between two marks with nothing inside: the marks go.
            if hugged(sel) {
                let whole = NSRange(location: sel.location - prefix.nsLength, length: prefix.nsLength + suffix.nsLength)
                return .edit(TextEdit(range: whole, replacement: "", selection: NSRange(location: whole.location, length: 0)))
            }
            // Inside a span: the mark comes off here.
            var para = ns.paragraphRange(for: sel)
            if para.length > 0, ns.character(at: para.upperBoundValue - 1) == 10 { para.length -= 1 }
            let text = ns.substring(with: para)
            let at = sel.location - para.location
            let spans = spanRegex(for: prefix).matches(in: text, options: [], range: NSRange(location: 0, length: text.nsLength))
            if let span = spans.first(where: { at >= $0.range(at: 1).location && at <= $0.range(at: 1).upperBoundValue }) {
                let inner = span.range(at: 1)
                if at == inner.upperBoundValue {
                    return .select(NSRange(location: para.location + span.range.upperBoundValue, length: 0))
                } else if at == inner.location {
                    return .select(NSRange(location: para.location + span.range.location, length: 0))
                }
                return .edit(TextEdit(range: sel, replacement: suffix + prefix,
                                      selection: NSRange(location: sel.location + suffix.nsLength, length: 0)))
            }
            // Fresh marks with a placeholder to type over.
            return .edit(TextEdit(range: sel, replacement: prefix + placeholder + suffix,
                                  selection: NSRange(location: sel.location + prefix.nsLength, length: placeholder.nsLength)))
        }

        let selected = ns.substring(with: sel)
        if selected.hasPrefix(prefix), selected.hasSuffix(suffix), selected.nsLength >= prefix.nsLength + suffix.nsLength {
            // The selection is a marked span, marks included: unwrap it.
            let inner = String(selected.dropFirst(prefix.count).dropLast(suffix.count))
            return .edit(TextEdit(range: sel, replacement: inner, selection: NSRange(location: sel.location, length: inner.nsLength)))
        }
        if hugged(sel) {
            // The selection is the inside of a marked span: the marks around it go.
            let whole = NSRange(location: sel.location - prefix.nsLength, length: sel.length + prefix.nsLength + suffix.nsLength)
            return .edit(TextEdit(range: whole, replacement: selected, selection: NSRange(location: whole.location, length: selected.nsLength)))
        }
        return .edit(TextEdit(range: sel, replacement: prefix + selected + suffix,
                              selection: NSRange(location: sel.location + prefix.nsLength, length: sel.length)))
    }

    /// One web or mail address, with nothing around it.
    static func isBareURL(_ s: String) -> Bool {
        guard !s.isEmpty, s.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:")
    }

    /// `[words](address)`: the selection becomes the words, an address on the
    /// clipboard becomes the address, and whichever is missing is left selected.
    static func link(in ns: NSString, selection sel: NSRange, clipboard: String?) -> TextEdit {
        let selected = sel.length > 0 ? ns.substring(with: sel) : "link text"
        var urlText = "https://"
        if let clip = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines), isBareURL(clip) { urlText = clip }
        let text = "[\(selected)](\(urlText))"
        let selection = sel.length > 0
            ? NSRange(location: sel.location + selected.nsLength + 3, length: urlText.nsLength)
            : NSRange(location: sel.location + 1, length: selected.nsLength)
        return TextEdit(range: sel, replacement: text, selection: selection)
    }

    /// A URL pasted over selected words links them instead of replacing them.
    /// Only when the clipboard is one address and nothing else, and the
    /// selection is words on one line — an address pasted over an address, or
    /// over text with brackets already in it, still replaces it.
    static func linkByPasting(_ clipboard: String?, in ns: NSString, selection sel: NSRange) -> TextEdit? {
        guard sel.length > 0, let clip = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines), isBareURL(clip) else { return nil }
        let selected = ns.substring(with: sel)
        // Any spaces at the ends stay outside the link.
        let core = selected.trimmingCharacters(in: .whitespaces)
        let lead = String(selected.prefix(while: { $0 == " " || $0 == "\t" }))
        let trail = String(selected.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
        guard !core.isEmpty, !core.contains("\n"), !core.contains("["), !core.contains("]"), !isBareURL(core) else { return nil }
        let text = "\(lead)[\(core)](\(clip))\(trail)"
        return TextEdit(range: sel, replacement: text,
                        selection: NSRange(location: sel.location + text.nsLength - trail.nsLength, length: 0))
    }

    // MARK: Paragraphs

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

    /// Makes every paragraph the selection touches into `kind`. Asking for what
    /// they all already are turns them back into plain text. A selection stays
    /// over the same words afterwards; a caret keeps its place in its line.
    static func setBlock(_ kind: BlockKind, in ns: NSString, selection sel: NSRange) -> TextEdit? {
        var span = ns.paragraphRange(for: sel)
        if span.length > 0, ns.character(at: span.upperBoundValue - 1) == 10 { span.length -= 1 }
        let old = ns.substring(with: span)
        let lines = old.components(separatedBy: "\n")
        let parsed = lines.map(parse)
        let target: BlockKind = parsed.allSatisfy({ $0.kind == kind }) ? .paragraph : kind
        let keepsIndent: Bool = { if case .bullet = target { return true }; if case .numbered = target { return true }; if case .task = target { return true }; return false }()
        var number = 1
        if case .numbered = target {
            number = nextNumber(before: span.location, width: indentWidth(parsed.first?.indent ?? ""), in: ns)
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
        guard text != old else { return nil }
        let selection = sel.length > 0
            ? NSRange(location: span.location, length: text.nsLength)
            : NSRange(location: min(caret, span.location + text.nsLength), length: 0)
        return TextEdit(range: span, replacement: text, selection: selection)
    }

    /// `[ ]` ↔ `[x]` on the caret's line; a bullet gains a box; plain text becomes a task.
    static func toggleTask(in ns: NSString, selection sel: NSRange) -> TextEdit {
        var para = ns.paragraphRange(for: sel)
        if para.length > 0 && ns.character(at: para.upperBoundValue - 1) == 10 { para.length -= 1 }
        let line = ns.substring(with: para)
        let newLine: String
        if line.range(of: "^([ \\t]*[-*+][ \\t]+)\\[ \\]", options: .regularExpression) != nil {
            newLine = line.replacingOccurrences(of: "^([ \\t]*[-*+][ \\t]+)\\[ \\]", with: "$1[x]", options: .regularExpression)
        } else if line.range(of: "^([ \\t]*[-*+][ \\t]+)\\[[xX]\\]", options: .regularExpression) != nil {
            newLine = line.replacingOccurrences(of: "^([ \\t]*[-*+][ \\t]+)\\[[xX]\\]", with: "$1[ ]", options: .regularExpression)
        } else if line.range(of: "^[ \\t]*[-*+][ \\t]+", options: .regularExpression) != nil {
            newLine = line.replacingOccurrences(of: "^([ \\t]*[-*+][ \\t]+)", with: "$1[ ] ", options: .regularExpression)
        } else {
            newLine = "- [ ] " + line
        }
        let end = para.location + newLine.nsLength
        return TextEdit(range: para, replacement: newLine,
                        selection: NSRange(location: min(sel.location + (newLine.nsLength - line.nsLength), end), length: 0))
    }

    // MARK: Lists

    private static let listLineRx = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|(\\d{1,3})[.)])([ \\t]+)(\\[[ xX]\\][ \\t]+)?(.*)$")
    private static let indentUnit = "    "

    static func indentWidth(_ s: String) -> Int { s.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }

    /// The number a numbered item should carry at `width`, judged by the item
    /// just above it at the same depth (1 when it starts a fresh list).
    static func nextNumber(before location: Int, width: Int, in ns: NSString) -> Int {
        var p = location
        while p > 0 {
            let lr = ns.lineRange(for: NSRange(location: p - 1, length: 0))
            var r = lr
            if r.length > 0, ns.character(at: r.upperBoundValue - 1) == 10 { r.length -= 1 }
            let line = ns.substring(with: r)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return 1 }
            let lineNS = line as NSString
            guard let m = listLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: lineNS.length)) else { return 1 }
            let w = indentWidth(lineNS.substring(with: m.range(at: 1)))
            if w == width {
                if m.range(at: 3).location != NSNotFound, let n = Int(lineNS.substring(with: m.range(at: 3))) { return n + 1 }
                return 1
            }
            if w < width { return 1 }
            p = lr.location
        }
        return 1
    }

    /// Return at the end of a list item starts the next one — same marker, the
    /// next number, an empty box — and Return on an empty item ends the list
    /// (a nested one steps out a level first). Nil anywhere else.
    static func continueList(in ns: NSString, selection sel: NSRange) -> TextEdit? {
        guard sel.length == 0 else { return nil }
        var lineRange = ns.paragraphRange(for: sel)
        if lineRange.length > 0 && ns.character(at: lineRange.upperBoundValue - 1) == 10 { lineRange.length -= 1 }
        // Only act when the caret is at the end of the line.
        guard sel.location == lineRange.upperBoundValue else { return nil }
        let line = ns.substring(with: lineRange)
        let lineNS = line as NSString
        guard let m = listLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: lineNS.length)) else { return nil }
        let indent = lineNS.substring(with: m.range(at: 1))
        let marker = lineNS.substring(with: m.range(at: 2))
        let gap = lineNS.substring(with: m.range(at: 4))
        let hasTask = m.range(at: 5).location != NSNotFound
        let content = lineNS.substring(with: m.range(at: 6))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            if !indent.isEmpty, let out = shiftListItems(deeper: false, in: ns, selection: sel) { return out }
            return TextEdit(range: lineRange, replacement: "", selection: NSRange(location: lineRange.location, length: 0))
        }
        var nextMarker = marker
        if m.range(at: 3).location != NSNotFound, let n = Int(lineNS.substring(with: m.range(at: 3))) {
            nextMarker = "\(n + 1)" + marker.suffix(1)
        }
        let insertion = "\n" + indent + nextMarker + gap + (hasTask ? "[ ] " : "")
        return TextEdit(range: sel, replacement: insertion, selection: NSRange(location: sel.location + insertion.nsLength, length: 0))
    }

    /// Tab nests every list item the selection touches one level deeper,
    /// Shift-Tab brings them back out, renumbering numbered items to fit their
    /// new neighbours. Nil when no touched line is a list item, so Tab keeps
    /// its ordinary meaning. One edit over the whole span of touched lines.
    static func shiftListItems(deeper: Bool, in ns: NSString, selection original: NSRange) -> TextEdit? {
        var sel = original
        let para = ns.paragraphRange(for: sel)
        var lineRanges: [NSRange] = []
        var loc = para.location
        repeat {
            let lr = ns.lineRange(for: NSRange(location: loc, length: 0))
            var r = lr
            if r.length > 0, ns.character(at: r.upperBoundValue - 1) == 10 { r.length -= 1 }
            lineRanges.append(r)
            if lr.length == 0 { break }
            loc = lr.upperBoundValue
        } while loc < para.upperBoundValue
        let isList: (NSRange) -> Bool = { r in
            let line = ns.substring(with: r)
            return listLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length)) != nil
        }
        guard lineRanges.contains(where: isList), let firstLine = lineRanges.first, let lastLine = lineRanges.last else { return nil }

        let working = NSMutableString(string: ns)
        var shift = 0   // how far earlier edits in this pass have moved later text
        for originalRange in lineRanges {
            let r = NSRange(location: originalRange.location + shift, length: originalRange.length)
            let line = working.substring(with: r)
            let lineNS = line as NSString
            guard let m = listLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: lineNS.length)) else { continue }
            let indent = lineNS.substring(with: m.range(at: 1))
            let marker = lineNS.substring(with: m.range(at: 2))
            let gap = lineNS.substring(with: m.range(at: 4))
            let task = m.range(at: 5).location == NSNotFound ? "" : lineNS.substring(with: m.range(at: 5))
            let content = lineNS.substring(with: m.range(at: 6))
            let newIndent: String
            if deeper {
                newIndent = indentUnit + indent
            } else if indent.hasPrefix("\t") {
                newIndent = String(indent.dropFirst())
            } else {
                newIndent = String(indent.dropFirst(min(4, indent.prefix { $0 == " " }.count)))
            }
            if newIndent == indent { continue }
            var newMarker = marker
            if m.range(at: 3).location != NSNotFound {
                newMarker = "\(nextNumber(before: r.location, width: indentWidth(newIndent), in: working))" + marker.suffix(1)
            }
            let newLine = newIndent + newMarker + gap + task + content
            working.replaceCharacters(in: r, with: newLine)
            let oldPrefix = (indent + marker + gap).nsLength
            let newPrefix = (newIndent + newMarker + gap).nsLength
            let delta = newLine.nsLength - line.nsLength
            // Keep the selection on the same characters it covered before.
            func adjust(_ p: Int) -> Int {
                if p < r.location { return p }
                if p > r.upperBoundValue { return p + delta }
                let off = p - r.location
                return r.location + (off >= oldPrefix ? off + (newPrefix - oldPrefix) : newPrefix)
            }
            let end = adjust(sel.upperBoundValue)
            let start = adjust(sel.location)
            sel = NSRange(location: start, length: max(0, end - start))
            shift += delta
        }
        guard shift != 0 || working as String != ns as String else {
            // A list line that cannot go any shallower: the key is still the list's, and does nothing.
            return TextEdit(range: NSRange(location: original.location, length: 0), replacement: "", selection: original)
        }
        let span = NSRange(location: firstLine.location, length: lastLine.upperBoundValue - firstLine.location)
        let replaced = working.substring(with: NSRange(location: span.location, length: span.length + shift))
        return TextEdit(range: span, replacement: replaced, selection: sel)
    }

    // MARK: Dates and dashes

    /// A finished `@today`, `@yesterday` or `@tomorrow` right before the caret, as the date it stands for.
    static func expandDateShortcut(in ns: NSString, selection sel: NSRange, now: Date = Date()) -> TextEdit? {
        guard sel.length == 0, sel.location > 0 else { return nil }
        let paragraphStart = ns.paragraphRange(for: sel).location
        let start = max(paragraphStart, sel.location - 12)
        let lookback = NSRange(location: start, length: sel.location - start)
        let tail = ns.substring(with: lookback)
        let tailNS = tail as NSString
        guard let m = DateToken.shortcutRegex.firstMatch(in: tail, options: [], range: NSRange(location: 0, length: tailNS.length)),
              let date = DateToken.date(for: tailNS.substring(with: m.range(at: 1)), now: now) else { return nil }
        let token = "@" + DateToken.format(date)
        let range = NSRange(location: lookback.location + m.range.location, length: m.range.length)
        return TextEdit(range: range, replacement: token, selection: NSRange(location: range.location + token.nsLength, length: 0))
    }

    private static let dashes: Set<Character> = ["-", "\u{2013}", "\u{2014}"]

    /// The line so far, up to the caret, is dashes and nothing else: the next
    /// hyphen is the makings of a rule, and the smart-dash substitution stands down.
    static func lineBeforeCaretIsDashes(in ns: NSString, selection sel: NSRange) -> Bool {
        let para = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        let head = ns.substring(with: NSRange(location: para.location, length: sel.location - para.location))
        return !head.isEmpty && head.allSatisfy { dashes.contains($0) }
    }

    /// A line of dashes with an em or en dash in it becomes the plain hyphens
    /// it stands for — two per long dash — so `---` is `---` in the file.
    static func straightenDashLine(in ns: NSString, selection sel: NSRange) -> TextEdit? {
        var para = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        if para.length > 0, ns.character(at: para.upperBoundValue - 1) == 10 { para.length -= 1 }
        let line = ns.substring(with: para)
        guard !line.isEmpty, line.allSatisfy({ dashes.contains($0) }), line.contains(where: { $0 != "-" }) else { return nil }
        let count = line.reduce(0) { $0 + ($1 == "-" ? 1 : 2) }
        let straight = String(repeating: "-", count: count)
        return TextEdit(range: para, replacement: straight, selection: NSRange(location: para.location + straight.nsLength, length: 0))
    }
}

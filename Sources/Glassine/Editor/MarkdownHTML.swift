import Foundation

/// A small, dependency-free Markdown → HTML renderer covering what a writing
/// app needs: headings (ATX and setext), paragraphs with hard breaks, emphasis,
/// strikethrough, inline code, fenced and indented code, nested ordered and
/// unordered lists, task lists, blockquotes, GFM tables, links, images, bare
/// URLs, thematic breaks and #tags. HTML in the source is escaped, not passed through.
///
/// One deliberate departure from CommonMark, to match what the editor shows:
/// every line break starts a new paragraph, and `---` is always a rule (never a
/// setext heading). `===` under a line still makes a level-one heading.
enum MarkdownHTML {

    static func render(_ markdown: String) -> String {
        var lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        // Hide YAML front matter.
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            if let end = lines.dropFirst().prefix(60).firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                lines.removeSubrange(0...end)
            }
        }
        return renderBlocks(lines)
    }

    // MARK: - Regexes

    private static func rx(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: []) }

    private static let headingRx = rx("^(#{1,6})[ \\t]+(.*?)[ \\t]*#*[ \\t]*$")
    private static let hrRx = rx("^[ \\t]*(?:(?:-[ \\t]*){3,}|(?:\\*[ \\t]*){3,}|(?:_[ \\t]*){3,})$")
    private static let listRx = rx("^([ \\t]*)([-*+]|\\d{1,9}[.)])([ \\t]+)(.*)$")
    private static let taskRx = rx("^\\[([ xX])\\][ \\t]+(.*)$")
    private static let fenceRx = rx("^(`{3,}|~{3,})[ \\t]*([\\w+#.-]*)")
    private static let tableSepRx = rx("^\\|?[ \\t]*:?-+:?[ \\t]*(\\|[ \\t]*:?-+:?[ \\t]*)*\\|?$")
    private static let codeSpanRx = rx("(`+)([^`\\n]+?)\\1")
    private static let escapeRx = rx("\\\\([\\\\`*_{}\\[\\]()#+\\-.!|>~])")
    private static let imageRx = rx("!\\[([^\\]]*)\\]\\(([^)\\s]+)(?:[ \\t]+\"[^\"]*\")?\\)")
    private static let linkRx = rx("(?<!!)\\[([^\\]]+)\\]\\(([^)\\s]+)(?:[ \\t]+\"[^\"]*\")?\\)")
    private static let boldRx = rx("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italicStarRx = rx("(?<![\\*\\w])\\*(?=\\S)([^*\\n]+?)(?<=\\S)\\*(?!\\*)")
    private static let italicUnderscoreRx = rx("(?<![\\w_])_(?=\\S)([^_\\n]+?)(?<=\\S)_(?![\\w_])")
    private static let strikeRx = rx("~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let autolinkRx = rx("(?<![\"=>\\w/])(https?://[^\\s<>\"]*[^\\s<>\".,;:!?)])")
    private static let tagRx = rx("(?<![\\w#/&;])#([A-Za-z_][\\w\\-/]*)")
    private static let dateRx = rx(DateToken.pattern)

    // MARK: - Helpers

    private struct Match {
        let result: NSTextCheckingResult
        let source: NSString
        func group(_ i: Int) -> String {
            let r = result.range(at: i)
            return r.location == NSNotFound ? "" : source.substring(with: r)
        }
        var range: NSRange { result.range }
    }

    private static func first(_ regex: NSRegularExpression, _ s: String) -> Match? {
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Match(result: m, source: ns)
    }

    private static func replaceAll(_ regex: NSRegularExpression, in s: String, _ f: (Match) -> String) -> String {
        let ns = NSMutableString(string: s)
        let matches = regex.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        for m in matches.reversed() {
            let replacement = f(Match(result: m, source: NSString(string: s)))
            ns.replaceCharacters(in: m.range, with: replacement)
        }
        return ns as String
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttr(_ s: String) -> String {
        escape(s).replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func slug(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        var lastDash = true
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "section" : out
    }

    private static func indentWidth(_ line: String) -> Int {
        var w = 0
        for ch in line {
            if ch == " " { w += 1 } else if ch == "\t" { w += 4 } else { break }
        }
        return w
    }

    private static func dedent(_ line: String, by columns: Int) -> String {
        var remaining = columns
        var idx = line.startIndex
        while remaining > 0, idx < line.endIndex {
            let ch = line[idx]
            if ch == " " { remaining -= 1 } else if ch == "\t" { remaining -= 4 } else { break }
            idx = line.index(after: idx)
        }
        return String(line[idx...])
    }

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Blocks

    private static func renderBlocks(_ lines: [String]) -> String {
        var html = ""
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html += "<p>" + inline(paragraph.joined(separator: "\n")) + "</p>\n"
            paragraph = []
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Fenced code
            if let m = first(fenceRx, trimmed) {
                flushParagraph()
                let marker = m.group(1)
                let lang = m.group(2)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                    code.append(lines[i])
                    i += 1
                }
                i += 1
                let cls = lang.isEmpty ? "" : " class=\"language-\(escapeAttr(lang))\""
                html += "<pre><code\(cls)>" + escape(code.joined(separator: "\n")) + "\n</code></pre>\n"
                continue
            }

            // Setext heading: a line followed by ===
            if !paragraph.isEmpty, trimmed.count >= 3, trimmed.allSatisfy({ $0 == "=" }) {
                let text = paragraph.joined(separator: " ")
                paragraph = []
                html += "<h1 id=\"\(slug(text))\">" + inline(text) + "</h1>\n"
                i += 1
                continue
            }

            // ATX heading
            if let m = first(headingRx, trimmed) {
                flushParagraph()
                let level = m.group(1).count
                let text = m.group(2)
                html += "<h\(level) id=\"\(slug(text))\">" + inline(text) + "</h\(level)>\n"
                i += 1
                continue
            }

            // Thematic break
            if first(hrRx, trimmed) != nil {
                flushParagraph()
                html += "<hr>\n"
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var inner: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") {
                        var stripped = String(t.dropFirst())
                        if stripped.hasPrefix(" ") { stripped.removeFirst() }
                        inner.append(stripped)
                        i += 1
                    } else if !t.isEmpty, let last = inner.last, !last.isEmpty, first(listRx, lines[i]) == nil, first(headingRx, t) == nil {
                        inner.append(lines[i]) // lazy continuation
                        i += 1
                    } else {
                        break
                    }
                }
                html += "<blockquote>\n" + renderBlocks(inner) + "</blockquote>\n"
                continue
            }

            // Table
            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let header = splitRow(lines[i])
                let aligns = splitRow(lines[i + 1]).map { cell -> String in
                    let c = cell.trimmingCharacters(in: .whitespaces)
                    if c.hasPrefix(":") && c.hasSuffix(":") { return "center" }
                    if c.hasSuffix(":") { return "right" }
                    return "left"
                }
                i += 2
                var rows: [[String]] = []
                while i < lines.count, lines[i].contains("|"), !isBlank(lines[i]) {
                    rows.append(splitRow(lines[i]))
                    i += 1
                }
                func cellHTML(_ tag: String, _ cells: [String]) -> String {
                    var s = "<tr>"
                    for (k, cell) in cells.enumerated() {
                        let align = k < aligns.count ? aligns[k] : "left"
                        s += "<\(tag) style=\"text-align:\(align)\">" + inline(cell) + "</\(tag)>"
                    }
                    return s + "</tr>\n"
                }
                html += "<table>\n<thead>\n" + cellHTML("th", header) + "</thead>\n<tbody>\n"
                for r in rows { html += cellHTML("td", r) }
                html += "</tbody>\n</table>\n"
                continue
            }

            // List
            if first(listRx, line) != nil {
                flushParagraph()
                let (listHTML, next) = renderList(lines, from: i)
                html += listHTML
                i = next
                continue
            }

            // Indented code
            if paragraph.isEmpty, indentWidth(line) >= 4 {
                var code: [String] = []
                while i < lines.count, indentWidth(lines[i]) >= 4 || isBlank(lines[i]) {
                    code.append(dedent(lines[i], by: 4))
                    i += 1
                }
                while let last = code.last, last.trimmingCharacters(in: .whitespaces).isEmpty { code.removeLast() }
                html += "<pre><code>" + escape(code.joined(separator: "\n")) + "\n</code></pre>\n"
                continue
            }

            // Each line is its own paragraph (see the note at the top). The previous line is
            // held back one step so a following === can still turn it into a heading.
            flushParagraph()
            paragraph = [line]
            i += 1
        }
        flushParagraph()
        return html
    }

    // MARK: - Lists

    private struct ListItemMatch {
        let indent: Int
        let ordered: Bool
        let number: Int?
        let contentIndent: Int
        let text: String
    }

    private static func listMatch(_ line: String) -> ListItemMatch? {
        guard let m = first(listRx, line) else { return nil }
        let indent = indentWidth(m.group(1))
        let marker = m.group(2)
        let gap = m.group(3).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let ordered = marker.first?.isNumber == true
        let number = ordered ? Int(marker.dropLast()) : nil
        return ListItemMatch(indent: indent, ordered: ordered, number: number,
                             contentIndent: indent + marker.count + gap, text: m.group(4))
    }

    private static func renderList(_ lines: [String], from start: Int) -> (String, Int) {
        guard let firstItem = listMatch(lines[start]) else { return ("", start + 1) }
        let baseIndent = firstItem.indent
        let ordered = firstItem.ordered
        var items: [(content: [String], tight: Bool)] = []
        var i = start

        while i < lines.count, let m = listMatch(lines[i]), m.indent == baseIndent, m.ordered == ordered {
            var content = [m.text]
            var sawBlank = false
            i += 1
            while i < lines.count {
                let l = lines[i]
                if isBlank(l) {
                    var j = i
                    while j < lines.count, isBlank(lines[j]) { j += 1 }
                    if j < lines.count, indentWidth(lines[j]) >= m.contentIndent, listMatch(lines[j])?.indent != baseIndent {
                        content.append(contentsOf: Array(repeating: "", count: j - i))
                        sawBlank = true
                        i = j
                        continue
                    }
                    if j < lines.count, let nm = listMatch(lines[j]), nm.indent == baseIndent, nm.ordered == ordered {
                        sawBlank = true // loose list: blank line between items
                        i = j
                    }
                    break
                }
                if indentWidth(l) >= m.contentIndent {
                    content.append(dedent(l, by: m.contentIndent))
                    i += 1
                    continue
                }
                if let nested = listMatch(l), nested.indent > baseIndent {
                    // A nested item with shallow indentation (e.g. "  - x" under "- item").
                    content.append(dedent(l, by: min(nested.indent, m.contentIndent)))
                    i += 1
                    continue
                }
                if listMatch(l) == nil, let last = content.last, !last.isEmpty,
                   first(headingRx, l.trimmingCharacters(in: .whitespaces)) == nil, first(hrRx, l) == nil,
                   !l.trimmingCharacters(in: .whitespaces).hasPrefix(">"), first(fenceRx, l.trimmingCharacters(in: .whitespaces)) == nil {
                    content.append(l.trimmingCharacters(in: .whitespaces)) // lazy continuation
                    i += 1
                    continue
                }
                break
            }
            items.append((content, !sawBlank))
        }

        let startAttr = (ordered && (firstItem.number ?? 1) != 1) ? " start=\"\(firstItem.number ?? 1)\"" : ""
        var out = ordered ? "<ol\(startAttr)>\n" : "<ul>\n"
        for item in items {
            var content = item.content
            var taskPrefix = ""
            var liClass = ""
            if let firstLine = content.first, let tm = first(taskRx, firstLine) {
                let checked = tm.group(1).lowercased() == "x"
                content[0] = tm.group(2)
                taskPrefix = "<input type=\"checkbox\"\(checked ? " checked" : "")> "
                liClass = checked ? " class=\"task done\"" : " class=\"task\""
            }
            var inner = renderBlocks(content)
            if item.tight, inner.hasPrefix("<p>"), let close = inner.range(of: "</p>\n") {
                inner.removeSubrange(close)
                inner.removeFirst(3)
            }
            if !taskPrefix.isEmpty, item.tight {
                // The item's own text (not a nested list) gets a span the stylesheet can strike.
                let nested = inner.range(of: "\n<ul>") ?? inner.range(of: "\n<ol")
                let end = nested?.lowerBound ?? inner.endIndex
                inner = "<span class=\"task-text\">" + inner[..<end] + "</span>" + inner[end...]
            }
            out += "<li\(liClass)>" + taskPrefix + inner + "</li>\n"
        }
        out += ordered ? "</ol>\n" : "</ul>\n"
        return (out, i)
    }

    // MARK: - Tables

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") || t.hasPrefix(":") else { return false }
        return first(tableSepRx, t) != nil
    }

    private static func splitRow(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in t {
            if escaped {
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    // MARK: - Inline

    static func inline(_ raw: String) -> String {
        var placeholders: [String] = []
        func stash(_ html: String) -> String {
            placeholders.append(html)
            return "\u{E000}\(placeholders.count - 1)\u{E001}"
        }

        var s = raw
        // Backslash escapes and code spans are protected before anything else runs.
        s = replaceAll(escapeRx, in: s) { stash(escape($0.group(1))) }
        s = replaceAll(codeSpanRx, in: s) { stash("<code>" + escape($0.group(2)) + "</code>") }
        s = escape(s)
        // `s` is already entity-escaped here, so attributes only need their quotes handled.
        func quoteSafe(_ v: String) -> String { v.replacingOccurrences(of: "\"", with: "&quot;") }
        s = replaceAll(imageRx, in: s) { m in
            stash("<img src=\"\(quoteSafe(m.group(2)))\" alt=\"\(quoteSafe(m.group(1)))\">")
        }
        s = replaceAll(linkRx, in: s) { m in
            "<a href=\"\(quoteSafe(m.group(2)))\">" + m.group(1) + "</a>"
        }
        s = replaceAll(boldRx, in: s) { "<strong>" + $0.group(2) + "</strong>" }
        s = replaceAll(italicStarRx, in: s) { "<em>" + $0.group(1) + "</em>" }
        s = replaceAll(italicUnderscoreRx, in: s) { "<em>" + $0.group(1) + "</em>" }
        s = replaceAll(strikeRx, in: s) { "<del>" + $0.group(1) + "</del>" }
        s = replaceAll(autolinkRx, in: s) { m in
            let url = m.group(1)
            return "<a href=\"\(url)\">" + url + "</a>"
        }
        s = replaceAll(tagRx, in: s) { "<span class=\"tag\">#" + $0.group(1) + "</span>" }
        s = replaceAll(dateRx, in: s) { "<span class=\"date\">" + String($0.group(0).dropFirst()) + "</span>" }
        s = s.replacingOccurrences(of: "  \n", with: "<br>\n")
        for (k, html) in placeholders.enumerated().reversed() {
            s = s.replacingOccurrences(of: "\u{E000}\(k)\u{E001}", with: html)
        }
        return s
    }

    // MARK: - Documents for the pasteboard

    /// A neutral, self-contained HTML document (system font, sensible sizes) —
    /// what "Copy as Rich Text" hands to the pasteboard.
    static func neutralDocument(title: String, body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><title>\(escape(title))</title>
        <style>
        body { font-family: -apple-system, "Helvetica Neue", Helvetica, Arial, sans-serif; font-size: 15px; line-height: 1.5; color: #1d1d1f; }
        h1 { font-size: 26px; margin: 18px 0 8px; } h2 { font-size: 21px; margin: 16px 0 6px; } h3 { font-size: 17px; margin: 14px 0 4px; }
        h4, h5, h6 { font-size: 15px; margin: 12px 0 4px; }
        p, ul, ol, blockquote, pre, table { margin: 0 0 10px; }
        code { font-family: Menlo, monospace; font-size: 13px; background: #f2f2f4; padding: 1px 4px; border-radius: 3px; }
        pre { background: #f2f2f4; padding: 10px 12px; border-radius: 6px; } pre code { background: none; padding: 0; }
        blockquote { border-left: 3px solid #c8c8cc; margin-left: 0; padding-left: 12px; color: #515154; }
        table { border-collapse: collapse; } th, td { border: 1px solid #d2d2d7; padding: 4px 8px; }
        a { color: #0a63c9; } hr { border: 0; border-top: 1px solid #d2d2d7; }
        .date { background: #e8eef8; color: #0a63c9; border-radius: 10px; padding: 1px 7px; }
        </style></head><body>\(body)</body></html>
        """
    }
}

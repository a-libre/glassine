import Foundation

/// Keeps task lists tidy when the setting is on: a task that was just checked
/// sinks below the last unfinished item among its siblings, and one that was
/// just unchecked rises back to the end of the unfinished group. Nested items
/// travel with their parent, and numbered siblings are renumbered.
enum TaskReorder {
    struct Result {
        /// The whole document's lines after the move (same count as before).
        let lines: [String]
        /// Where the toggled item's line ended up.
        let movedTo: Int
        /// The span of lines that may have changed, inclusive.
        let blockStart: Int
        let blockEnd: Int
    }

    private static let listRx = try! NSRegularExpression(
        pattern: "^([ \\t]*)([-*+]|(\\d{1,9})([.)]))([ \\t]+)(\\[([ xX])\\][ \\t]+)?(.*)$")

    private struct Item {
        let line: Int
        let indent: Int
        let isTask: Bool
        let checked: Bool
        let number: Int?
        let numberSuffix: String
    }

    static func indentWidth<S: StringProtocol>(_ s: S) -> Int {
        s.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func parse(_ line: String, at index: Int) -> Item? {
        let ns = line as NSString
        guard let m = listRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        let isTask = m.range(at: 6).location != NSNotFound
        let checked = isTask && ns.substring(with: m.range(at: 7)).lowercased() == "x"
        let number = m.range(at: 3).location == NSNotFound ? nil : Int(ns.substring(with: m.range(at: 3)))
        let suffix = m.range(at: 4).location == NSNotFound ? "" : ns.substring(with: m.range(at: 4))
        return Item(line: index, indent: indentWidth(ns.substring(with: m.range(at: 1))), isTask: isTask,
                    checked: checked, number: number, numberSuffix: suffix)
    }

    /// The document after the task on line `toggled` has just changed state.
    /// Returns nil when nothing needs to move.
    static func afterToggle(lines: [String], at toggled: Int) -> Result? {
        guard toggled >= 0, toggled < lines.count, let me = parse(lines[toggled], at: toggled), me.isTask else { return nil }

        // The list block around the item: list lines at this depth or deeper, plus
        // their indented continuation lines, bounded by blank lines and anything shallower.
        func belongs(_ i: Int) -> Bool {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if let item = parse(line, at: i) { return item.indent >= me.indent }
            return indentWidth(line.prefix { $0 == " " || $0 == "\t" }) > me.indent
        }
        var start = toggled
        while start > 0, belongs(start - 1) { start -= 1 }
        var end = toggled
        while end + 1 < lines.count, belongs(end + 1) { end += 1 }

        // Siblings and the subtree each one owns.
        let siblings = (start...end).compactMap { parse(lines[$0], at: $0) }.filter { $0.indent == me.indent }
        guard let k = siblings.firstIndex(where: { $0.line == toggled }) else { return nil }
        func subtreeEnd(_ s: Int) -> Int { s + 1 < siblings.count ? siblings[s + 1].line - 1 : end }
        let unfinished = { (s: Item) in !(s.isTask && s.checked) }

        // Where the item should go, as a sibling index it lands after (-1 = the top).
        let destAfter: Int
        if me.checked {
            guard let last = siblings.indices.last(where: { $0 > k && unfinished(siblings[$0]) }) else { return nil }
            destAfter = last
        } else {
            guard siblings.indices.contains(where: { $0 < k && !unfinished(siblings[$0]) }) else { return nil }
            destAfter = siblings.indices.last(where: { $0 < k && unfinished(siblings[$0]) }) ?? -1
        }

        // Rebuild the block: siblings in their new order, each with its subtree.
        var order = Array(siblings.indices)
        order.remove(at: k)
        order.insert(k, at: destAfter < k ? destAfter + 1 : destAfter)
        var block: [String] = []
        var movedTo = toggled
        let firstNumber = siblings.first?.number
        for (n, s) in order.enumerated() {
            let item = siblings[s]
            var lineText = lines[item.line]
            if let base = firstNumber, item.number != nil {
                // Renumber in place, keeping the item's own indent, suffix and spacing.
                let ns = lineText as NSString
                if let m = listRx.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: ns.length)) {
                    lineText = ns.replacingCharacters(in: m.range(at: 3), with: String(base + n))
                }
            }
            if s == k { movedTo = start + block.count }
            block.append(lineText)
            if item.line + 1 <= subtreeEnd(s) {
                block.append(contentsOf: lines[(item.line + 1)...subtreeEnd(s)])
            }
        }
        var out = lines
        out.replaceSubrange(start...end, with: block)
        return Result(lines: out, movedTo: movedTo, blockStart: start, blockEnd: end)
    }

    /// The task ordinal (Review's numbering: top to bottom, skipping fenced code)
    /// of the task on `line`, or nil if that line is not a task.
    static func ordinal(ofTaskAt line: Int, in lines: [String]) -> Int? {
        var inFence = false, seen = 0
        for (i, l) in lines.enumerated() {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") || t.hasPrefix("~~~") { inFence.toggle(); continue }
            if inFence { continue }
            guard let item = parse(l, at: i), item.isTask else { continue }
            if i == line { return seen }
            seen += 1
        }
        return nil
    }
}

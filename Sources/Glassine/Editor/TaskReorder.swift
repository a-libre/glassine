import Foundation

/// Moves list items around as whole units — each with the nested items it owns —
/// and keeps numbered lists numbered. Two callers: the tidy-list rule that sinks
/// a checked task and raises an unchecked one, and drag-to-reorder.
enum TaskReorder {
    struct Result {
        /// The whole document's lines after the move (same count as before).
        let lines: [String]
        /// Where the moved item's line ended up.
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
        return Item(line: index, indent: indentWidth(ns.substring(with: m.range(at: 1))), isTask: isTask, checked: checked, number: number)
    }

    /// True when `line` is a list item of any kind.
    static func isListItem(_ line: String) -> Bool { parse(line, at: 0) != nil }

    /// The character range of the list marker on a line (the "-", "3." and so on), if any.
    static func markerRange(in line: String) -> NSRange? {
        let ns = line as NSString
        guard let m = listRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return m.range(at: 2)
    }

    // MARK: - The list around an item

    private struct Context {
        let lines: [String]
        let start: Int, end: Int
        let siblings: [Item]
        let k: Int
        func subtreeEnd(_ s: Int) -> Int { s + 1 < siblings.count ? siblings[s + 1].line - 1 : end }
    }

    /// The contiguous list block around `line` at that item's depth: its siblings,
    /// each owning the deeper lines beneath it, bounded by blank lines and anything
    /// shallower.
    private static func context(_ lines: [String], at line: Int) -> Context? {
        guard line >= 0, line < lines.count, let me = parse(lines[line], at: line) else { return nil }
        func belongs(_ i: Int) -> Bool {
            let l = lines[i]
            if l.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            if let item = parse(l, at: i) { return item.indent >= me.indent }
            return indentWidth(l.prefix { $0 == " " || $0 == "\t" }) > me.indent
        }
        var start = line
        while start > 0, belongs(start - 1) { start -= 1 }
        var end = line
        while end + 1 < lines.count, belongs(end + 1) { end += 1 }
        let siblings = (start...end).compactMap { parse(lines[$0], at: $0) }.filter { $0.indent == me.indent }
        guard let k = siblings.firstIndex(where: { $0.line == line }) else { return nil }
        return Context(lines: lines, start: start, end: end, siblings: siblings, k: k)
    }

    /// Rebuilds the block with the siblings in `order` (indices into `siblings`),
    /// each followed by its subtree, renumbering numbered items.
    private static func rebuild(_ c: Context, order: [Int]) -> Result {
        var block: [String] = []
        var movedTo = c.siblings[c.k].line
        let firstNumber = c.siblings.first?.number
        for (n, s) in order.enumerated() {
            let item = c.siblings[s]
            var lineText = c.lines[item.line]
            if let base = firstNumber, item.number != nil {
                let ns = lineText as NSString
                if let m = listRx.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: ns.length)) {
                    lineText = ns.replacingCharacters(in: m.range(at: 3), with: String(base + n))
                }
            }
            if s == c.k { movedTo = c.start + block.count }
            block.append(lineText)
            if item.line + 1 <= c.subtreeEnd(s) {
                block.append(contentsOf: c.lines[(item.line + 1)...c.subtreeEnd(s)])
            }
        }
        var out = c.lines
        out.replaceSubrange(c.start...c.end, with: block)
        return Result(lines: out, movedTo: movedTo, blockStart: c.start, blockEnd: c.end)
    }

    // MARK: - Checking and unchecking

    /// Where a sunk task came from: the siblings as they stood (by text) and the
    /// slot it held among them. Unchecking it puts it back there, as long as the
    /// other siblings are still in that order.
    private struct Home { let siblings: [String]; let index: Int }
    private static var homes: [String: Home] = [:]
    private static var homeOrder: [String] = []

    /// A sibling reduced to its text, so checkbox state and numbering do not count as changes.
    private static func identity(_ line: String) -> String {
        let ns = line as NSString
        guard let m = listRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return line.trimmingCharacters(in: .whitespaces)
        }
        return ns.substring(with: m.range(at: 8)).trimmingCharacters(in: .whitespaces)
    }

    private static func remember(_ key: String, _ home: Home) {
        if homes[key] == nil { homeOrder.append(key) }
        homes[key] = home
        while homeOrder.count > 300 { homes[homeOrder.removeFirst()] = nil }
    }

    /// The document after the task on line `toggled` has just changed state: a
    /// checked task sinks below the last unfinished sibling; an unchecked one goes
    /// back to where it was, or to the end of the unfinished group. Nil when
    /// nothing needs to move.
    static func afterToggle(lines: [String], at toggled: Int) -> Result? {
        guard let c = context(lines, at: toggled), c.siblings[c.k].isTask else { return nil }
        let me = c.siblings[c.k], k = c.k
        let unfinished = { (s: Item) in !(s.isTask && s.checked) }
        let names = c.siblings.map { identity(lines[$0.line]) }
        let key = names[k]
        var others = names; others.remove(at: k)

        var order = Array(c.siblings.indices)
        order.remove(at: k)
        if me.checked {
            guard let last = c.siblings.indices.last(where: { $0 > k && unfinished(c.siblings[$0]) }) else { return nil }
            remember(key, Home(siblings: names, index: k))
            order.insert(k, at: last)
        } else if let home = homes[key], { var h = home.siblings; h.remove(at: home.index); return h == others }() {
            homes[key] = nil
            guard home.index != k else { return nil }
            order.insert(k, at: min(home.index, order.count))
        } else {
            guard c.siblings.indices.contains(where: { $0 < k && !unfinished(c.siblings[$0]) }) else { return nil }
            let destAfter = c.siblings.indices.last(where: { $0 < k && unfinished(c.siblings[$0]) }) ?? -1
            order.insert(k, at: destAfter + 1)
        }
        return rebuild(c, order: order)
    }

    // MARK: - Dragging

    /// An item and its siblings, each with the lines it owns, for showing where a
    /// drag will drop it. Positions are in line units: line 3 spans 3.0 to 4.0.
    struct Siblings {
        let spans: [ClosedRange<Int>]
        /// Which span is the item being dragged.
        let index: Int

        /// The item's place among the other siblings (0 ... count - 1) when the
        /// pointer is at `y`: it goes above every sibling whose middle is below the
        /// pointer. Equal to `index` when it would stay where it is.
        func slot(toward y: Double) -> Int {
            var slot = 0
            for (s, span) in spans.enumerated() where s != index {
                let middle = Double(span.lowerBound + span.upperBound + 1) / 2
                if y >= middle { slot += 1 } else { break }
            }
            return slot
        }

        /// The document line the item would sit above after landing in `slot`;
        /// one past the block when it goes last.
        func dropLine(for slot: Int) -> Int {
            let others = spans.indices.filter { $0 != index }
            if slot < others.count { return spans[others[slot]].lowerBound }
            return spans[others.last ?? index].upperBound + 1
        }
    }

    static func siblings(lines: [String], at line: Int) -> Siblings? {
        guard let c = context(lines, at: line) else { return nil }
        return Siblings(spans: c.siblings.indices.map { c.siblings[$0].line...c.subtreeEnd($0) }, index: c.k)
    }

    /// The document after the item on `itemLine` is dropped with the pointer at
    /// `y` (line units, see `Siblings`). Nil when it lands where it already is.
    static func drag(lines: [String], itemLine: Int, toward y: Double) -> Result? {
        guard let c = context(lines, at: itemLine) else { return nil }
        let slot = Siblings(spans: c.siblings.indices.map { c.siblings[$0].line...c.subtreeEnd($0) }, index: c.k).slot(toward: y)
        guard slot != c.k else { return nil }
        var order = c.siblings.indices.filter { $0 != c.k }
        order.insert(c.k, at: slot)
        return rebuild(c, order: order)
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

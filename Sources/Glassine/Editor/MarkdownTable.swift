import AppKit

/// A pipe table as the editor sees it.
///
/// The file keeps its `|` and `---`; the page shows a table. Each row's cells
/// are measured as styled and the narrower ones are padded — a kern on the
/// cell's last space, or on its opening pipe for a right-aligned column — so
/// every column lines up to its widest cell, whatever the font, with a little
/// room kerned onto each pipe and each cell's end for the cell's padding. The
/// table is drawn as a grid: a border round it with rounded corners, a line
/// under every row, a line where every pipe is, the header on a faint fill
/// and in the bold weight; the pipes and the separator's dashes are laid out
/// and never drawn (GlassineLayoutManager draws the grid; MarkdownStyler asks
/// for the layout). Tab moves to the next cell and ⇧Tab to the one before;
/// Tab from the last cell adds a row.
enum MarkdownTable {

    /// On every `|` of a table; the value is the line's colour.
    static let pipeKey = NSAttributedString.Key("glassine.tablePipe")
    /// On the dashes and colons of the separator row; the value is the rule's colour.
    static let ruleKey = NSAttributedString.Key("glassine.tableRule")
    /// On every character of a table row: which row of its table it is.
    static let rowKey = NSAttributedString.Key("glassine.tableRow")
    /// On every character of a table row: the table's right edge, in points
    /// from the row's left, where the border is drawn whatever line the
    /// row's closing pipe ended up on.
    static let edgeKey = NSAttributedString.Key("glassine.tableEdge")
    /// On the separator row's pipes, set small with the rest of the row:
    /// half the width of a body pipe, so the line sits where the other
    /// rows' do.
    static let pipeInsetKey = NSAttributedString.Key("glassine.tablePipeInset")
    /// On every row of a table, the newlines between them included, one
    /// object per table: how to draw its grid. One object, so the rows of a
    /// table read as one run of the attribute.
    static let gridKey = NSAttributedString.Key("glassine.tableGrid")
    /// On a row with a cell too long for its column: the position of that
    /// cell's opening pipe. The cell wraps under its column and the cells
    /// after it follow on its last line, so no column line is drawn to the
    /// right of that pipe in the row.
    static let wrapKey = NSAttributedString.Key("glassine.tableWrap")

    /// How a table's grid is drawn.
    final class Grid: NSObject {
        let line: NSColor
        let fill: NSColor
        let radius: CGFloat
        /// The width of a `|` in the body font: the lines are drawn through
        /// the middle of the pipes.
        let pipe: CGFloat
        init(line: NSColor, fill: NSColor, radius: CGFloat, pipe: CGFloat) {
            self.line = line; self.fill = fill; self.radius = radius; self.pipe = pipe
        }
    }

    enum Alignment { case left, center, right }

    struct Row {
        /// The paragraph, without its newline.
        let range: NSRange
        /// Absolute positions of the row's pipes.
        let pipes: [Int]
        /// Absolute ranges of what lies between the pipes, in column order.
        let cells: [NSRange]
    }

    struct Table {
        let rows: [Row]
        var alignments: [Alignment]
        var columns: Int { alignments.count }
    }

    // MARK: - Reading

    /// The dashes may be em or en dashes too: a separator typed with smart
    /// dashes on, before the editor learned to leave them alone, still reads.
    private static let separatorRx = try! NSRegularExpression(pattern: "^[ \\t]*\\|?[ \\t]*:?[-\u{2013}\u{2014}]+:?[ \\t]*(\\|[ \\t]*:?[-\u{2013}\u{2014}]+:?[ \\t]*)*\\|?[ \\t]*$")

    static func isSeparator(_ line: String) -> Bool {
        line.contains(where: { $0 == "-" || $0 == "\u{2013}" || $0 == "\u{2014}" })
            && separatorRx.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil
    }

    /// A line that could be a row: at least one pipe outside a code span.
    static func looksLikeRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The row's shape: its pipes (those outside code spans, and not escaped)
    /// and the cells between them. A row may leave off its first or last pipe.
    static func row(_ ns: NSString, paragraph: NSRange) -> Row {
        var pipes: [Int] = []
        var inCode = false
        var i = paragraph.location
        let end = paragraph.upperBoundValue
        while i < end {
            let c = ns.character(at: i)
            if c == 0x60 { inCode.toggle() }                      // `
            else if c == 0x7C, !inCode, i == paragraph.location || ns.character(at: i - 1) != 0x5C { pipes.append(i) }   // | not after \
            i += 1
        }
        var cells: [NSRange] = []
        var start = paragraph.location
        // A leading pipe opens the first cell; without one the line's start does.
        var bounds = pipes
        if let first = bounds.first, isBlank(ns, NSRange(location: paragraph.location, length: first - paragraph.location)) {
            start = first + 1
            bounds.removeFirst()
        }
        // A trailing pipe closes the last cell; without one the line's end does.
        var closesLast = false
        if let last = bounds.last, isBlank(ns, NSRange(location: last + 1, length: end - last - 1)) {
            closesLast = true
            bounds.removeLast()
        }
        for p in bounds {
            cells.append(NSRange(location: start, length: p - start))
            start = p + 1
        }
        let lastEnd = closesLast ? (pipes.last ?? end) : end
        cells.append(NSRange(location: start, length: max(0, lastEnd - start)))
        return Row(range: paragraph, pipes: pipes, cells: cells)
    }

    private static func isBlank(_ ns: NSString, _ r: NSRange) -> Bool {
        guard r.length > 0 else { return true }
        return ns.substring(with: r).trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A table from consecutive rows, when the second is a separator.
    static func table(_ ns: NSString, paragraphs: [NSRange]) -> Table? {
        guard paragraphs.count >= 2, isSeparator(ns.substring(with: paragraphs[1])) else { return nil }
        let rows = paragraphs.map { row(ns, paragraph: $0) }
        let alignments = rows[1].cells.map { cell -> Alignment in
            let t = ns.substring(with: cell).trimmingCharacters(in: .whitespaces)
            let l = t.hasPrefix(":"), r = t.hasSuffix(":")
            return l && r ? .center : r ? .right : .left
        }
        return Table(rows: rows, alignments: alignments)
    }

    /// The table a position is in, read from the text around it.
    static func table(_ ns: NSString, around location: Int) -> Table? {
        let block = blockRange(ns, around: location)
        var paragraphs: [NSRange] = []
        ns.enumerateSubstrings(in: block, options: [.byParagraphs, .substringNotRequired]) { _, r, _, _ in paragraphs.append(r) }
        return table(ns, paragraphs: paragraphs)
    }

    /// The run of pipe lines around a position, as one range.
    static func blockRange(_ ns: NSString, around location: Int) -> NSRange {
        var r = ns.paragraphRange(for: NSRange(location: min(location, ns.length), length: 0))
        guard looksLikeRow(ns.substring(with: r)) else { return r }
        while r.location > 0 {
            let prev = ns.paragraphRange(for: NSRange(location: r.location - 1, length: 0))
            guard looksLikeRow(ns.substring(with: prev)) else { break }
            r = NSUnionRange(r, prev)
        }
        while r.upperBoundValue < ns.length {
            let next = ns.paragraphRange(for: NSRange(location: r.upperBoundValue, length: 0))
            guard looksLikeRow(ns.substring(with: next)) else { break }
            r = NSUnionRange(r, next)
        }
        return r
    }

    // MARK: - Layout

    /// Pads the cells so the columns line up, and marks the pipes, the
    /// separator and the header for drawing. Fonts and inline styles are
    /// already on the text; the kerns go on top of whatever kern is there.
    /// The table is as wide as its widest cells, up to `availableWidth`: a
    /// last column that would run past the page is cut to what fits, and a
    /// cell longer than that wraps under its own column (the row's head
    /// indent) at the table's edge (the row's tail indent) rather than under
    /// the row or past the border.
    static func layOut(_ table: Table, in storage: NSTextStorage, config: StyleConfig, grid: Grid,
                       headerFont: NSFont, rowParagraph: NSParagraphStyle, separatorParagraph: NSParagraphStyle,
                       lastRowParagraph: NSParagraphStyle, availableWidth: CGFloat) {
        let ns = storage.ns
        let columns = table.columns
        guard columns > 0 else { return }
        let bodyPipe = grid.pipe
        // A cell's padding: room after each pipe and before the next, on top
        // of the spaces the Markdown has there.
        let inset = (config.fontSize * 0.3).rounded()

        for (index, row) in table.rows.enumerated() {
            storage.addAttribute(rowKey, value: index, range: row.range)
            if index == 1 {
                // The separator is a line across the table, not a line of text: a thin strip.
                storage.enumerateAttribute(.font, in: row.range, options: []) { value, r, _ in
                    let f = (value as? NSFont) ?? config.bodyFont
                    storage.addAttribute(.font, value: f.withSize(max(3, (f.pointSize * 0.3).rounded())), range: r)
                }
            }
            let closing = closingPipe(of: row, in: ns)
            for p in row.pipes {
                storage.addAttribute(.foregroundColor, value: grid.line, range: NSRange(location: p, length: 1))
                storage.addAttribute(pipeKey, value: grid.line, range: NSRange(location: p, length: 1))
                if index == 1 {
                    // A small pipe advances like a body pipe and is drawn centred like one.
                    let f = storage.attribute(.font, at: p, effectiveRange: nil) as? NSFont ?? config.bodyFont
                    let w = ("|" as NSString).size(withAttributes: [.font: f]).width
                    if bodyPipe - w > 0.1 { addKern(bodyPipe - w, at: p, in: storage) }
                    storage.addAttribute(pipeInsetKey, value: bodyPipe / 2, range: NSRange(location: p, length: 1))
                }
                // Room after the pipe, for the cell that follows; none after
                // the closing one, which must fit inside the border.
                if p != closing { addKern(inset, at: p, in: storage) }
            }
            if index == 0 {
                for cell in row.cells where cell.length > 0 {
                    storage.enumerateAttribute(.font, in: cell, options: []) { value, r, _ in
                        let f = (value as? NSFont) ?? headerFont
                        storage.addAttribute(.font, value: f.withTraits(.bold), range: r)
                    }
                }
            } else if index == 1 {
                for cell in row.cells where cell.length > 0 {
                    storage.addAttribute(.foregroundColor, value: grid.line, range: cell)
                    storage.addAttribute(ruleKey, value: grid.line, range: cell)
                }
            }
        }

        // Every cell measured as it will be drawn, then the widest in each column.
        var widths = [CGFloat](repeating: 0, count: columns)
        var measured: [[CGFloat]] = []
        for row in table.rows {
            var ws: [CGFloat] = []
            for (c, cell) in row.cells.enumerated() {
                let w = width(of: cell, in: storage, hideSyntax: config.hideSyntax)
                ws.append(w)
                if c < columns { widths[c] = max(widths[c], w) }
            }
            measured.append(ws)
        }
        // A cell is at least a few spaces wide, so an empty column has room to type in.
        let minimum = ("    " as NSString).size(withAttributes: [.font: config.bodyFont]).width
        for c in 0..<columns { widths[c] = max(widths[c], minimum) }
        // The pipes, and the room after each but the last and before each
        // closing one: what the table is wide beyond its cells.
        let chrome = CGFloat(columns + 1) * bodyPipe + CGFloat(2 * columns) * inset
        // A table wider than the page has its widest columns narrowed first,
        // levelled down together, no column below a floor; a cell longer
        // than its column then wraps.
        var targets = widths
        var excess = widths.reduce(0, +) + chrome + 2 - availableWidth
        if excess > 0 {
            let floor = max(minimum, (config.fontSize * 4).rounded())
            var rounds = 0
            while excess > 0.5, rounds < 64 {
                rounds += 1
                let widest = targets.max() ?? 0
                guard widest > floor + 0.5 else { break }
                let top = targets.indices.filter { targets[$0] >= widest - 0.5 }
                let next = max(floor, targets.filter { $0 < widest - 0.5 }.max() ?? floor)
                let step = min(widest - next, excess / CGFloat(top.count))
                guard step > 0 else { break }
                for i in top { targets[i] -= step }
                excess -= step * CGFloat(top.count)
            }
        }
        let last = columns - 1

        // The first cell of each row too long for its column, if any: it
        // wraps, and the cells after it follow it rather than their columns.
        var wrapAt = [Int?](repeating: nil, count: table.rows.count)
        for (r, row) in table.rows.enumerated() where r != 1 {
            for (c, _) in row.cells.enumerated() where c < columns {
                if measured[r][c] > targets[c] + 0.5 { wrapAt[r] = c; break }
            }
        }

        for (r, row) in table.rows.enumerated() {
            for (c, cell) in row.cells.enumerated() where c < columns {
                let opening: Int? = row.pipes.first { $0 == cell.location - 1 }
                let closing = cell.upperBoundValue   // the pipe after the cell, if any
                let hasClosing = row.pipes.contains(closing)
                // The cell's own last character carries the padding before its
                // pipe; the opening pipe carries padding that goes before the text.
                let tail: Int? = cell.length > 0 ? cell.upperBoundValue - 1 : opening
                if let k = wrapAt[r], c >= k {
                    // The wrapping cell, and the cells after it in its row:
                    // no padding to a column they are not in; the ones after
                    // keep their room before the pipe.
                    if c > k, let t = tail { addKern(inset, at: t, in: storage) }
                    continue
                }
                let pad = max(0, targets[c] - measured[r][c])
                switch table.alignments[c] {
                case .left:
                    if let t = tail { addKern(pad + inset, at: t, in: storage) }
                    else if hasClosing { addKern(pad + inset, at: closing - 1, in: storage) }
                case .right:
                    if let o = opening { addKern(pad, at: o, in: storage) }
                    if let t = tail { addKern(inset, at: t, in: storage) }
                    else if let o = opening { addKern(inset, at: o, in: storage) }
                case .center:
                    let half = (pad / 2).rounded()
                    if let o = opening { addKern(half, at: o, in: storage) } else if let t = tail { addKern(half, at: t, in: storage) }
                    if let t = tail { addKern(pad - half + inset, at: t, in: storage) }
                }
            }
        }

        // Where each row's wrapping column — or, when none wraps, its last —
        // begins, measured as padded, for the lines of a cell that wraps; and
        // the table's right edge, read off the first row whose cells all fit,
        // for the border and for the tail indent that wraps a longer cell
        // inside it.
        var edge: CGFloat?
        var starts: [CGFloat] = []
        for (r, row) in table.rows.enumerated() {
            let column = min(wrapAt[r] ?? last, row.cells.count - 1)
            guard column >= 0 else { starts.append(0); continue }
            let textStart = textRange(of: row.cells[column], in: ns).location
            starts.append(width(of: NSRange(location: row.range.location, length: textStart - row.range.location),
                                in: storage, hideSyntax: config.hideSyntax))
            if edge == nil, r != 1, wrapAt[r] == nil, let closing = closingPipe(of: row, in: ns) {
                edge = width(of: NSRange(location: row.range.location, length: closing - row.range.location),
                             in: storage, hideSyntax: config.hideSyntax) + bodyPipe / 2
            }
        }
        let tableEdge = edge ?? (targets.reduce(0, +) + chrome - bodyPipe / 2)
        // A row that wraps keeps the cell's padding at the border too: its
        // lines end an inset short of it, and its closing pipe — laid out,
        // never drawn — is made to take no room, so that the pipe always
        // fits on the cell's last line and never drops onto one of its own.
        for (r, row) in table.rows.enumerated() where wrapAt[r] != nil {
            guard let p = closingPipe(of: row, in: ns) else { continue }
            let f = storage.attribute(.font, at: p, effectiveRange: nil) as? NSFont ?? config.bodyFont
            storage.addAttribute(.font, value: f.withSize(1), range: NSRange(location: p, length: 1))
            if p > row.range.location, ns.character(at: p - 1) == 0x20 {
                let sf = storage.attribute(.font, at: p - 1, effectiveRange: nil) as? NSFont ?? config.bodyFont
                let w = (" " as NSString).size(withAttributes: [.font: sf]).width
                storage.addAttribute(.kern, value: -w, range: NSRange(location: p - 1, length: 1))
            }
        }
        let tableRange = NSRange(location: table.rows[0].range.location,
                                 length: table.rows[table.rows.count - 1].range.upperBoundValue - table.rows[0].range.location)
        storage.addAttribute(gridKey, value: grid, range: tableRange)
        for (r, row) in table.rows.enumerated() {
            let enclosing = NSRange(location: row.range.location,
                                    length: min(ns.length, row.range.upperBoundValue + 1) - row.range.location)
            // Rows sit flush so the lines join; the last keeps the page's spacing after it.
            let base = r == 1 ? separatorParagraph : r == table.rows.count - 1 ? lastRowParagraph : rowParagraph
            let style = base.mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = starts[r]
            // A row with a cell too long for its column wraps at the border,
            // not at the page's edge: the pipe after a cell that only just
            // overflows used to drop onto a line of its own.
            if let k = wrapAt[r] {
                if tableEdge + bodyPipe < availableWidth { style.tailIndent = tableEdge - bodyPipe / 2 - inset }
                let cell = row.cells[min(k, row.cells.count - 1)]
                let opening = row.pipes.first { $0 == cell.location - 1 } ?? row.range.location
                storage.addAttribute(wrapKey, value: opening, range: row.range)
            }
            storage.addAttribute(.paragraphStyle, value: style, range: enclosing)
            storage.addAttribute(edgeKey, value: tableEdge, range: row.range)
        }
    }

    /// The pipe that closes a row — its last, when nothing but spaces follows it.
    static func closingPipe(of row: Row, in ns: NSString) -> Int? {
        guard let p = row.pipes.last else { return nil }
        return isBlank(ns, NSRange(location: p + 1, length: row.range.upperBoundValue - p - 1)) ? p : nil
    }

    private static func addKern(_ amount: CGFloat, at index: Int, in storage: NSTextStorage) {
        guard index >= 0, index < storage.length else { return }
        let existing = storage.attribute(.kern, at: index, effectiveRange: nil) as? CGFloat ?? 0
        storage.addAttribute(.kern, value: existing + amount, range: NSRange(location: index, length: 1))
    }

    /// The width a cell's text takes as drawn: its fonts and kerns, less any
    /// marker that is hidden.
    private static func width(of range: NSRange, in storage: NSTextStorage, hideSyntax: Bool) -> CGFloat {
        guard range.length > 0 else { return 0 }
        let piece = NSMutableAttributedString(attributedString: storage.attributedSubstring(from: range))
        piece.removeAttribute(pipeKey, range: NSRange(location: 0, length: piece.length))
        if hideSyntax {
            var hidden: [NSRange] = []
            piece.enumerateAttribute(Syntax.hiddenKey, in: NSRange(location: 0, length: piece.length), options: []) { v, r, _ in
                if v != nil { hidden.append(r) }
            }
            for r in hidden.reversed() { piece.deleteCharacters(in: r) }
        }
        return piece.size().width
    }

    // MARK: - Moving between cells

    struct Move {
        /// What to select afterwards: the words of the cell moved to.
        var selection: NSRange
        /// Text to write first — a fresh row — and where.
        var insert: (at: Int, text: String)?
    }

    /// Where Tab goes from a position: the next cell's text, or nil when the
    /// position is not in a table. From the last cell a new row is added.
    static func nextCell(from location: Int, in storage: NSTextStorage, backward: Bool) -> Move? {
        let ns = storage.ns
        guard let table = table(ns, around: location) else { return nil }
        // The separator's cells are not for writing in: Tab from the last
        // heading goes to the first cell under it.
        let cells = table.rows.enumerated().filter { $0.offset != 1 }.flatMap { $0.element.cells }
        guard let here = cells.firstIndex(where: { NSLocationInRange(location, NSRange(location: $0.location, length: $0.length + 1)) })
            ?? cells.lastIndex(where: { $0.location <= location }) else { return nil }
        let target = here + (backward ? -1 : 1)
        if target < 0 { return nil }
        if target >= cells.count {
            // A fresh row under the last, shaped like the one above it.
            let last = table.rows.last!
            let text = "\n|" + Array(repeating: "  |", count: table.columns).joined()
            let at = last.range.upperBoundValue
            return Move(selection: NSRange(location: at + 3, length: 0), insert: (at, text))
        }
        return Move(selection: textRange(of: cells[target], in: ns), insert: nil)
    }

    /// The words of a cell, without the spaces that keep them off the pipes.
    static func textRange(of cell: NSRange, in ns: NSString) -> NSRange {
        var start = cell.location, end = cell.upperBoundValue
        while start < end, ns.character(at: start) == 0x20 { start += 1 }
        while end > start, ns.character(at: end - 1) == 0x20 { end -= 1 }
        // An empty cell: the caret goes after its first space, at the left,
        // where the padding (on the last space) is not.
        if start == end, cell.length >= 2 { return NSRange(location: cell.location + 1, length: 0) }
        return NSRange(location: start, length: end - start)
    }
}

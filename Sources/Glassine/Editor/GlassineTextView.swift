import AppKit
import QuartzCore

/// NSTextView subclass (TextKit 1) with a smoothly animated caret, a centered
/// text column, typewriter scrolling, focus-mode dimming and Markdown helpers.
final class GlassineTextView: NSTextView {
    var config: StyleConfig {
        didSet { if config != oldValue { applyConfig(previous: oldValue) } }
    }
    let styler: MarkdownStyler

    /// Called after every user edit (including undo/redo).
    var onTextChanged: (() -> Void)?
    /// Called when the insertion point moves.
    var onSelectionChanged: (() -> Void)?
    /// Called when Escape is pressed with nothing else to cancel.
    var onEscape: (() -> Void)?

    /// The editor currently on screen (there is only ever one).
    static weak var current: GlassineTextView?

    /// How far the viewport is scrolled through the document, 0–1.
    var scrollFraction: Double {
        guard let clip = enclosingScrollView?.contentView else { return 0 }
        let maxY = frame.height - clip.bounds.height
        guard maxY > 0 else { return 0 }
        return Double(max(0, min(1, clip.bounds.origin.y / maxY)))
    }

    // Caret
    private let caretLayer = CALayer()
    private var caretVisible = false
    private var lastCaretRect: CGRect = .zero
    private var isUpdatingCaret = false
    private var blinkWork: DispatchWorkItem?
    private var suppressAnimationOnce = false

    // Dragging a list item by its task box or marker
    private var listDrag: ListDrag?
    private let dragHighlight = CALayer()
    private let dropBar = CALayer()
    // Checked-off tasks waiting to sink, by their line text
    private var pendingSinks: [String: DispatchWorkItem] = [:]
    static let sinkDelay: TimeInterval = 1.6

    // Editing bookkeeping
    private var pendingEditRange: NSRange?
    private var lastEditAt: CFTimeInterval = 0
    private var lastTypedWasKeyboard = false
    private var lastFocusRange = NSRange(location: NSNotFound, length: 0)
    private var clipObserver: NSObjectProtocol?
    private var windowObservers: [NSObjectProtocol] = []

    static let minimumSideMargin: CGFloat = 40

    // The text system holds these weakly; keep them alive here.
    private let ownedStorage: NSTextStorage
    private let ownedLayoutManager: NSLayoutManager

    // MARK: - Init

    init(config: StyleConfig) {
        self.config = config
        self.styler = MarkdownStyler(config: config)

        let storage = NSTextStorage()
        let layoutManager = GlassineLayoutManager()
        ownedStorage = storage
        ownedLayoutManager = layoutManager
        layoutManager.allowsNonContiguousLayout = false
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        super.init(frame: NSRect(x: 0, y: 0, width: 600, height: 400), textContainer: container)
        layoutManager.delegate = self
        commonInit()
        GlassineTextView.current = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func commonInit() {
        wantsLayer = true
        isEditable = true
        isSelectable = true
        isRichText = true
        importsGraphics = false
        allowsImageEditing = false
        allowsUndo = true
        usesFontPanel = false
        usesRuler = false
        isRulerVisible = false
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        drawsBackground = false
        backgroundColor = .clear
        focusRingType = .none
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 0)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        smartInsertDeleteEnabled = true
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticTextReplacementEnabled = true
        isGrammarCheckingEnabled = false
        insertionPointColor = .clear   // the system caret is hidden; we draw our own

        caretLayer.anchorPoint = CGPoint(x: 0, y: 0)
        caretLayer.cornerRadius = 1
        caretLayer.opacity = 0
        caretLayer.zPosition = 10
        layer?.addSublayer(caretLayer)
        for l in [dragHighlight, dropBar] {
            l.anchorPoint = CGPoint(x: 0, y: 0)
            l.opacity = 0
            l.zPosition = 9
            layer?.addSublayer(l)
        }
        dragHighlight.cornerRadius = 5
        dropBar.cornerRadius = 1.5

        applyConfig(previous: nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for o in windowObservers { NotificationCenter.default.removeObserver(o) }
        windowObservers.removeAll()
        guard let window else { return }
        let nc = NotificationCenter.default
        windowObservers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.updateCaret(animated: false)
        })
        windowObservers.append(nc.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.updateCaret(animated: false)
        })
        windowObservers.append(nc.addObserver(forName: NSWindow.didChangeBackingPropertiesNotification, object: window, queue: .main) { [weak self] _ in
            self?.caretLayer.contentsScale = window.backingScaleFactor
        })
        caretLayer.contentsScale = window.backingScaleFactor
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if let o = clipObserver { NotificationCenter.default.removeObserver(o) }
        clipObserver = nil
        if let clip = superview as? NSClipView {
            clip.postsFrameChangedNotifications = true
            clipObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                self?.updateInsets()
            }
            updateInsets()
        }
    }

    deinit {
        if let o = clipObserver { NotificationCenter.default.removeObserver(o) }
        for o in windowObservers { NotificationCenter.default.removeObserver(o) }
    }

    // MARK: - Config

    private func applyConfig(previous: StyleConfig?) {
        styler.config = config
        let theme = config.theme
        selectedTextAttributes = [.backgroundColor: theme.selectionColor]
        caretLayer.backgroundColor = theme.caretColor.cgColor
        dragHighlight.backgroundColor = theme.caretColor.withAlphaComponent(0.10).cgColor
        dropBar.backgroundColor = theme.caretColor.cgColor
        linkTextAttributes = [.foregroundColor: theme.linkColor]
        typingAttributes = config.baseAttributes
        defaultParagraphStyle = config.baseParagraphStyle()
        isContinuousSpellCheckingEnabled = config.spellCheck
        isAutomaticQuoteSubstitutionEnabled = config.smartQuotes
        isAutomaticDashSubstitutionEnabled = config.smartDashes
        isAutomaticSpellingCorrectionEnabled = config.autocorrect
        isAutomaticTextCompletionEnabled = config.inlinePredictions
        if let scroll = enclosingScrollView {
            scroll.scrollerKnobStyle = theme.isDark ? .light : .dark
        }

        let typographyChanged: Bool = {
            guard let p = previous else { return true }
            return p.theme != config.theme || p.fontFamily != config.fontFamily || p.fontSize != config.fontSize
                || p.lineHeightMultiple != config.lineHeightMultiple || p.paragraphSpacingEm != config.paragraphSpacingEm
                || p.letterSpacing != config.letterSpacing || p.scaledHeadings != config.scaledHeadings
        }()
        if typographyChanged, let storage = textStorage, storage.length > 0 {
            let sel = selectedRange()
            styler.restyle(storage, range: NSRange(location: 0, length: storage.length))
            setSelectedRange(sel.clamped(to: storage.length))
        }
        updateInsets()
        updateFocusDimming(force: true)
        updateCaret(animated: false)
        if config.typewriter && previous?.typewriter == false {
            typewriterScroll(animated: true)
        }
    }

    // MARK: - Document swapping

    func load(text: String, caretAt position: Int?) {
        guard let storage = textStorage else { return }
        suppressAnimationOnce = true
        undoManager?.removeAllActions()
        pendingSinks.values.forEach { $0.cancel() }
        pendingSinks.removeAll()
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: text, attributes: config.baseAttributes))
        storage.endEditing()
        styler.restyle(storage, range: NSRange(location: 0, length: storage.length))
        let loc = min(max(0, position ?? storage.length), storage.length)
        setSelectedRange(NSRange(location: loc, length: 0))
        lastFocusRange = NSRange(location: NSNotFound, length: 0)
        updateFocusDimming(force: true)
        // Give layout a moment, then place the caret and scroll without animation.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateInsets()
            self.scrollRangeToVisible(self.selectedRange())
            if self.config.typewriter { self.typewriterScroll(animated: false) }
            self.updateCaret(animated: false)
            self.suppressAnimationOnce = false
        }
    }

    /// Replaces the text after an external change while trying to keep the caret in place.
    func replaceText(with text: String) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        storage.beginEditing()
        storage.setAttributedString(NSAttributedString(string: text, attributes: config.baseAttributes))
        storage.endEditing()
        styler.restyle(storage, range: NSRange(location: 0, length: storage.length))
        setSelectedRange(sel.clamped(to: storage.length))
        updateFocusDimming(force: true)
        updateCaret(animated: false)
    }

    // MARK: - Layout: centered column + insets

    func updateInsets() {
        let width = bounds.width
        guard width > 0 else { return }
        let usable = max(0, width - 2 * GlassineTextView.minimumSideMargin)
        let column = min(usable, config.columnWidth)
        let side = ((width - column) / 2).rounded(.down)

        var top = config.topInset
        if config.typewriter, let clip = enclosingScrollView?.contentView {
            top = max(top, (clip.bounds.height / 2 - config.bodyLineHeight / 2).rounded())
        }
        let newInset = NSSize(width: side, height: top)
        let oldInset = textContainerInset
        guard newInset != oldInset else { return }

        let clip = enclosingScrollView?.contentView
        let oldOrigin = clip?.bounds.origin
        textContainerInset = newInset
        textContainer?.containerSize = NSSize(width: column, height: CGFloat.greatestFiniteMagnitude)

        if newInset.height != oldInset.height {
            // The whole document just shifted by the inset delta. Finish layout so the frame
            // is current, then move the viewport by the same amount so nothing appears to jump.
            if let tc = textContainer { layoutManager?.ensureLayout(for: tc) }
            sizeToFit()
            if let clip, let oldOrigin {
                let delta = newInset.height - oldInset.height
                let maxY = max(0, frame.height - clip.bounds.height)
                let origin = NSPoint(x: oldOrigin.x, y: max(0, min(oldOrigin.y + delta, maxY)))
                clip.setBoundsOrigin(origin)
                enclosingScrollView?.reflectScrolledClipView(clip)
            }
        }
        needsDisplay = true
        updateCaret(animated: false)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateInsets()
        updateCaret(animated: false)
    }

    // MARK: - Editing hooks

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let ok = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        if ok, let s = replacementString {
            pendingEditRange = NSRange(location: affectedCharRange.location, length: (s as NSString).length)
            lastEditAt = CACurrentMediaTime()
        }
        return ok
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        let ok = super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings)
        if ok, let first = affectedRanges.first?.rangeValue, let last = affectedRanges.last?.rangeValue {
            let total = (replacementStrings ?? []).reduce(0) { $0 + ($1 as NSString).length }
            pendingEditRange = NSRange(location: first.location, length: max(total, last.upperBoundValue - first.location))
            lastEditAt = CACurrentMediaTime()
        }
        return ok
    }

    /// Shown in an empty document, at the caret, in the syntax colour.
    var placeholder = "Start writing"

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let font = config.bodyFont
        let color = config.theme.syntax.withAlpha(config.theme.isDark ? 0.45 : 0.5)
        let origin = NSPoint(x: textContainerOrigin.x + (textContainer?.lineFragmentPadding ?? 0) + 1,
                             y: textContainerOrigin.y + (config.bodyLineHeight - font.ascender + font.descender) / 2)
        (placeholder as NSString).draw(at: origin, withAttributes: [.font: font, .foregroundColor: color])
    }

    override func didChangeText() {
        super.didChangeText()
        if (textStorage?.length ?? 0) <= 1 { needsDisplay = true }
        if let storage = textStorage {
            let range = pendingEditRange ?? NSRange(location: selectedRange().location, length: 0)
            pendingEditRange = nil
            styler.restyle(storage, range: range)
        }
        lastTypedWasKeyboard = true
        lastEditAt = CACurrentMediaTime()
        onTextChanged?()
        updateFocusDimming(force: false)
        updateCaret(animated: config.smoothWhileTyping)
        if config.typewriter { typewriterScroll(animated: true) }
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting stillSelectingFlag: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelectingFlag)
        let byKeyboard = NSApp.currentEvent?.type == .keyDown
        lastTypedWasKeyboard = byKeyboard
        let justEdited = pendingEditRange != nil || CACurrentMediaTime() - lastEditAt < 0.05
        updateCaret(animated: !stillSelectingFlag && (config.smoothWhileTyping || !justEdited))
        if !stillSelectingFlag {
            onSelectionChanged?()
            updateFocusDimming(force: false)
            if config.typewriter && (byKeyboard || config.typewriterOnClick) {
                typewriterScroll(animated: true)
            }
        }
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        updateCaret(animated: false)
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        updateCaret(animated: false)
        return ok
    }

    override func paste(_ sender: Any?) {
        if linkSelectionFromClipboard() { return }
        pasteAsPlainText(sender)
    }

    /// A URL pasted over selected words links them instead of replacing them:
    /// select "the docs", paste, and the text reads [the docs](https://…).
    /// Only when the clipboard is one address and nothing else, and the
    /// selection is words on one line — an address pasted over an address,
    /// or over text with brackets already in it, still replaces it.
    private func linkSelectionFromClipboard() -> Bool {
        guard let storage = textStorage else { return false }
        let sel = selectedRange()
        guard sel.length > 0,
              let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              Self.isBareURL(clip) else { return false }
        let selected = (storage.string as NSString).substring(with: sel)
        // Any spaces at the ends stay outside the link.
        let core = selected.trimmingCharacters(in: .whitespaces)
        let lead = String(selected.prefix(while: { $0 == " " || $0 == "\t" }))
        let trail = String(selected.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
        guard !core.isEmpty, !core.contains("\n"), !core.contains("["), !core.contains("]"),
              !Self.isBareURL(core) else { return false }
        let text = "\(lead)[\(core)](\(clip))\(trail)"
        guard shouldChangeText(in: sel, replacementString: text) else { return false }
        storage.replaceCharacters(in: sel, with: text)
        didChangeText()
        setSelectedRange(NSRange(location: sel.location + text.nsLength - trail.nsLength, length: 0))
        return true
    }

    /// One web or mail address, with nothing around it.
    private static func isBareURL(_ s: String) -> Bool {
        guard !s.isEmpty, s.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:")
    }

    /// Escape. NSTextView would start word completion here; ⌥Esc still does that.
    override func cancelOperation(_ sender: Any?) {
        if let onEscape {
            onEscape()
        } else {
            super.cancelOperation(sender)
        }
    }

    override func insertNewline(_ sender: Any?) {
        expandDateShortcutIfNeeded()
        if config.continueLists, continueListIfNeeded() { return }
        super.insertNewline(sender)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        // A finished "@today" / "@yesterday" / "@tomorrow" becomes a date when the next
        // space or punctuation mark arrives.
        if let s = string as? String, s.count == 1, let ch = s.first,
           ch == " " || ch == "\t" || ",.;:!?)]".contains(ch) {
            expandDateShortcutIfNeeded()
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Replaces a shortcut word right before the caret with the actual date. Returns true if it did.
    @discardableResult
    private func expandDateShortcutIfNeeded() -> Bool {
        guard let storage = textStorage else { return false }
        let sel = selectedRange()
        guard sel.length == 0, sel.location > 0 else { return false }
        let ns = storage.string as NSString
        let paragraphStart = ns.paragraphRange(for: sel).location
        let start = max(paragraphStart, sel.location - 12)
        let lookback = NSRange(location: start, length: sel.location - start)
        let tail = ns.substring(with: lookback)
        let tailNS = tail as NSString
        guard let m = DateToken.shortcutRegex.firstMatch(in: tail, options: [], range: NSRange(location: 0, length: tailNS.length)),
              let date = DateToken.date(for: tailNS.substring(with: m.range(at: 1))) else { return false }
        let token = "@" + DateToken.format(date)
        let range = NSRange(location: lookback.location + m.range.location, length: m.range.length)
        guard shouldChangeText(in: range, replacementString: token) else { return false }
        storage.replaceCharacters(in: range, with: token)
        didChangeText()
        setSelectedRange(NSRange(location: range.location + token.nsLength, length: 0))
        return true
    }

    /// Markdown list continuation: Return on "- item" starts "- ", Return on an
    /// empty "- " removes the marker.
    private func continueListIfNeeded() -> Bool {
        guard let storage = textStorage else { return false }
        let ns = storage.string as NSString
        let sel = selectedRange()
        guard sel.length == 0 else { return false }
        let para = ns.paragraphRange(for: sel)
        var lineRange = para
        if lineRange.length > 0 && ns.character(at: lineRange.upperBoundValue - 1) == 10 { lineRange.length -= 1 }
        // Only act when the caret is at the end of the line.
        guard sel.location == lineRange.upperBoundValue else { return false }
        let line = ns.substring(with: lineRange)
        let regex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|(\\d{1,3})[.)])([ \\t]+)(\\[[ xX]\\][ \\t]+)?(.*)$")
        guard let m = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length)) else { return false }
        let lineNS = line as NSString
        let indent = lineNS.substring(with: m.range(at: 1))
        let marker = lineNS.substring(with: m.range(at: 2))
        let gap = lineNS.substring(with: m.range(at: 4))
        let hasTask = m.range(at: 5).location != NSNotFound
        let content = lineNS.substring(with: m.range(at: 6))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // An empty nested item steps out a level; an empty top-level item
            // ends the list by clearing the marker.
            if !indent.isEmpty, shiftListItems(deeper: false) { return true }
            if shouldChangeText(in: lineRange, replacementString: "") {
                textStorage?.replaceCharacters(in: lineRange, with: "")
                didChangeText()
            }
            return true
        }
        var nextMarker = marker
        if m.range(at: 3).location != NSNotFound, let n = Int(lineNS.substring(with: m.range(at: 3))) {
            nextMarker = "\(n + 1)" + marker.suffix(1)
        }
        let insertion = "\n" + indent + nextMarker + gap + (hasTask ? "[ ] " : "")
        insertText(insertion, replacementRange: sel)
        return true
    }

    // MARK: - List nesting

    private static let listLineRx = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|(\\d{1,3})[.)])([ \\t]+)(\\[[ xX]\\][ \\t]+)?(.*)$")
    private static let indentUnit = "    "

    private static func indentWidth(_ s: String) -> Int {
        s.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    /// Tab on a list item nests it one level deeper; Shift-Tab brings it back out.
    /// Anywhere else both keys keep their usual meaning.
    override func insertTab(_ sender: Any?) {
        if config.continueLists, shiftListItems(deeper: true) { return }
        super.insertTab(sender)
    }

    override func insertBacktab(_ sender: Any?) {
        if config.continueLists, shiftListItems(deeper: false) { return }
        super.insertBacktab(sender)
    }

    /// The number a numbered item should carry at `width`, judged by the item
    /// just above it at the same depth (1 when it starts a fresh list).
    private func nextNumber(before location: Int, width: Int) -> Int {
        guard let ns = textStorage?.string as NSString? else { return 1 }
        var p = location
        while p > 0 {
            let lr = ns.lineRange(for: NSRange(location: p - 1, length: 0))
            var r = lr
            if r.length > 0, ns.character(at: r.upperBoundValue - 1) == 10 { r.length -= 1 }
            let line = ns.substring(with: r)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return 1 }
            let lineNS = line as NSString
            guard let m = Self.listLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: lineNS.length)) else { return 1 }
            let w = Self.indentWidth(lineNS.substring(with: m.range(at: 1)))
            if w == width {
                if m.range(at: 3).location != NSNotFound, let n = Int(lineNS.substring(with: m.range(at: 3))) { return n + 1 }
                return 1
            }
            if w < width { return 1 }
            p = lr.location
        }
        return 1
    }

    /// Nests (or un-nests) every list item the selection touches by one level,
    /// renumbering numbered items to fit their new neighbors. Returns false when
    /// no touched line is a list item, so Tab can keep its ordinary meaning.
    @discardableResult
    private func shiftListItems(deeper: Bool) -> Bool {
        guard let storage = textStorage else { return false }
        var sel = selectedRange()
        let ns = storage.string as NSString
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
            return Self.listLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length)) != nil
        }
        guard lineRanges.contains(where: isList) else { return false }

        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        var shift = 0   // how far earlier edits in this pass have moved later text
        for original in lineRanges {
            let r = NSRange(location: original.location + shift, length: original.length)
            let current = storage.string as NSString
            let line = current.substring(with: r)
            let lineNS = line as NSString
            guard let m = Self.listLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: lineNS.length)) else { continue }
            let indent = lineNS.substring(with: m.range(at: 1))
            let marker = lineNS.substring(with: m.range(at: 2))
            let gap = lineNS.substring(with: m.range(at: 4))
            let task = m.range(at: 5).location == NSNotFound ? "" : lineNS.substring(with: m.range(at: 5))
            let content = lineNS.substring(with: m.range(at: 6))
            let newIndent: String
            if deeper {
                newIndent = Self.indentUnit + indent
            } else if indent.hasPrefix("\t") {
                newIndent = String(indent.dropFirst())
            } else {
                newIndent = String(indent.dropFirst(min(4, indent.prefix { $0 == " " }.count)))
            }
            if newIndent == indent { continue }
            var newMarker = marker
            if m.range(at: 3).location != NSNotFound {
                newMarker = "\(nextNumber(before: r.location, width: Self.indentWidth(newIndent)))" + marker.suffix(1)
            }
            let newLine = newIndent + newMarker + gap + task + content
            guard shouldChangeText(in: r, replacementString: newLine) else { continue }
            storage.replaceCharacters(in: r, with: newLine)
            didChangeText()
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
        setSelectedRange(sel)
        return true
    }

    // MARK: - Formatting commands (menu / shortcuts)

    private func wrapSelection(prefix: String, suffix: String? = nil, placeholder: String) {
        let suffix = suffix ?? prefix
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        var sel = selectedRange()
        if sel.length == 0 {
            // Toggle off if already inside markers.
            let before = NSRange(location: max(0, sel.location - prefix.nsLength), length: min(prefix.nsLength, sel.location))
            let after = NSRange(location: sel.location, length: min(suffix.nsLength, ns.length - sel.location))
            if before.length == prefix.nsLength, after.length == suffix.nsLength,
               ns.substring(with: before) == prefix, ns.substring(with: after) == suffix {
                let whole = NSRange(location: before.location, length: prefix.nsLength + suffix.nsLength)
                if shouldChangeText(in: whole, replacementString: "") {
                    storage.replaceCharacters(in: whole, with: "")
                    didChangeText()
                    setSelectedRange(NSRange(location: before.location, length: 0))
                }
                return
            }
            let text = prefix + placeholder + suffix
            if shouldChangeText(in: sel, replacementString: text) {
                storage.replaceCharacters(in: sel, with: text)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location + prefix.nsLength, length: placeholder.nsLength))
            }
            return
        }
        let selected = ns.substring(with: sel)
        if selected.hasPrefix(prefix), selected.hasSuffix(suffix), selected.nsLength >= prefix.nsLength + suffix.nsLength {
            let inner = String(selected.dropFirst(prefix.count).dropLast(suffix.count))
            if shouldChangeText(in: sel, replacementString: inner) {
                storage.replaceCharacters(in: sel, with: inner)
                didChangeText()
                setSelectedRange(NSRange(location: sel.location, length: inner.nsLength))
            }
            return
        }
        let wrapped = prefix + selected + suffix
        if shouldChangeText(in: sel, replacementString: wrapped) {
            storage.replaceCharacters(in: sel, with: wrapped)
            didChangeText()
            sel.location += prefix.nsLength
            setSelectedRange(sel)
        }
    }

    @objc func markdownBold(_ sender: Any?) { wrapSelection(prefix: "**", placeholder: "bold") }
    @objc func markdownItalic(_ sender: Any?) { wrapSelection(prefix: "*", placeholder: "italic") }
    @objc func markdownCode(_ sender: Any?) { wrapSelection(prefix: "`", placeholder: "code") }
    @objc func markdownStrike(_ sender: Any?) { wrapSelection(prefix: "~~", placeholder: "text") }

    @objc func markdownLink(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let sel = selectedRange()
        let ns = storage.string as NSString
        let selected = sel.length > 0 ? ns.substring(with: sel) : "link text"
        var urlText = "https://"
        if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           Self.isBareURL(clip) {
            urlText = clip
        }
        let text = "[\(selected)](\(urlText))"
        if shouldChangeText(in: sel, replacementString: text) {
            storage.replaceCharacters(in: sel, with: text)
            didChangeText()
            if sel.length > 0 {
                setSelectedRange(NSRange(location: sel.location + selected.nsLength + 3, length: urlText.nsLength))
            } else {
                setSelectedRange(NSRange(location: sel.location + 1, length: selected.nsLength))
            }
        }
    }

    @objc func markdownHeading1(_ sender: Any?) { setHeadingLevel(1) }
    @objc func markdownHeading2(_ sender: Any?) { setHeadingLevel(2) }
    @objc func markdownHeading3(_ sender: Any?) { setHeadingLevel(3) }
    @objc func markdownClearHeading(_ sender: Any?) { setHeadingLevel(0) }

    private func setHeadingLevel(_ level: Int) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let sel = selectedRange()
        var para = ns.paragraphRange(for: sel)
        if para.length > 0 && ns.character(at: para.upperBoundValue - 1) == 10 { para.length -= 1 }
        let line = ns.substring(with: para)
        let stripped = line.replacingOccurrences(of: "^#{1,6}[ \\t]+", with: "", options: .regularExpression)
        let currentLevel = line.nsLength - stripped.nsLength > 0 ? (line.prefix(while: { $0 == "#" }).count) : 0
        let newLine: String
        if level == 0 || currentLevel == level {
            newLine = stripped
        } else {
            newLine = String(repeating: "#", count: level) + " " + stripped
        }
        guard newLine != line else { return }
        if shouldChangeText(in: para, replacementString: newLine) {
            storage.replaceCharacters(in: para, with: newLine)
            didChangeText()
            let delta = newLine.nsLength - line.nsLength
            setSelectedRange(NSRange(location: max(para.location, sel.location + delta), length: 0))
        }
    }

    @objc func markdownToggleTask(_ sender: Any?) {
        guard let storage = textStorage else { return }
        let ns = storage.string as NSString
        let sel = selectedRange()
        var para = ns.paragraphRange(for: sel)
        if para.length > 0 && ns.character(at: para.upperBoundValue - 1) == 10 { para.length -= 1 }
        let line = ns.substring(with: para)
        var newLine: String
        if line.range(of: "^([ \\t]*[-*+][ \\t]+)\\[ \\]", options: .regularExpression) != nil {
            newLine = line.replacingOccurrences(of: "^([ \\t]*[-*+][ \\t]+)\\[ \\]", with: "$1[x]", options: .regularExpression)
        } else if line.range(of: "^([ \\t]*[-*+][ \\t]+)\\[[xX]\\]", options: .regularExpression) != nil {
            newLine = line.replacingOccurrences(of: "^([ \\t]*[-*+][ \\t]+)\\[[xX]\\]", with: "$1[ ]", options: .regularExpression)
        } else if line.range(of: "^[ \\t]*[-*+][ \\t]+", options: .regularExpression) != nil {
            newLine = line.replacingOccurrences(of: "^([ \\t]*[-*+][ \\t]+)", with: "$1[ ] ", options: .regularExpression)
        } else {
            newLine = "- [ ] " + line
        }
        if shouldChangeText(in: para, replacementString: newLine) {
            storage.replaceCharacters(in: para, with: newLine)
            didChangeText()
            setSelectedRange(NSRange(location: min(sel.location + (newLine.nsLength - line.nsLength), storage.length), length: 0))
        }
    }

    // MARK: - Typewriter scrolling

    func typewriterScroll(animated: Bool) {
        guard let scroll = enclosingScrollView, let rect = caretRect() else { return }
        let clip = scroll.contentView
        let viewport = clip.bounds.height
        guard viewport > 0 else { return }
        var target = rect.midY - viewport / 2
        let maxY = max(0, frame.height - viewport)
        target = max(0, min(target, maxY))
        if abs(target - clip.bounds.origin.y) < 0.5 { return }
        let origin = NSPoint(x: clip.bounds.origin.x, y: target)
        if animated && !GlassineTextView.reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clip.animator().setBoundsOrigin(origin)
            }
        } else {
            clip.setBoundsOrigin(origin)
        }
        scroll.reflectScrolledClipView(clip)
    }

    // MARK: - Focus mode

    func updateFocusDimming(force: Bool) {
        guard let lm = layoutManager, let storage = textStorage else { return }
        let full = NSRange(location: 0, length: storage.length)
        guard config.focus else {
            if lastFocusRange.location != NSNotFound || force {
                lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
                lastFocusRange = NSRange(location: NSNotFound, length: 0)
            }
            return
        }
        let sel = selectedRange()
        let ns = storage.string as NSString
        var focusRange = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        if config.focusScope == .sentence {
            var found: NSRange?
            ns.enumerateSubstrings(in: focusRange, options: [.bySentences, .substringNotRequired]) { _, r, enclosing, stop in
                if NSLocationInRange(sel.location, enclosing) || sel.location == enclosing.upperBoundValue {
                    found = r
                    stop.pointee = true
                }
            }
            if let f = found { focusRange = f }
        }
        guard force || !NSEqualRanges(focusRange, lastFocusRange) else { return }
        lastFocusRange = focusRange
        let dim = config.theme.text.withAlpha(max(0, min(1, config.focusDimming)))
        lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
        let before = NSRange(location: 0, length: focusRange.location)
        let after = NSRange(location: focusRange.upperBoundValue, length: max(0, storage.length - focusRange.upperBoundValue))
        if before.length > 0 { lm.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: before) }
        if after.length > 0 { lm.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: after) }
    }

    // MARK: - Smooth caret

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Intentionally empty: the caret is drawn by `caretLayer`.
    }

    override func updateInsertionPointStateAndRestartTimer(_ restartFlag: Bool) {
        super.updateInsertionPointStateAndRestartTimer(restartFlag)
        let justEdited = pendingEditRange != nil || CACurrentMediaTime() - lastEditAt < 0.05
        updateCaret(animated: config.smoothWhileTyping || !justEdited)
    }

    private func caretFont(at location: Int) -> NSFont {
        guard let storage = textStorage, storage.length > 0 else {
            return (typingAttributes[.font] as? NSFont) ?? config.bodyFont
        }
        let idx = min(max(0, location - 1), storage.length - 1)
        // Use the following character's font at the very start of a paragraph.
        let ns = storage.string as NSString
        let useNext = location == 0 || (location < storage.length && ns.character(at: idx) == 10)
        let probe = useNext ? min(location, storage.length - 1) : idx
        return (storage.attribute(.font, at: probe, effectiveRange: nil) as? NSFont) ?? config.bodyFont
    }

    /// Insertion point rectangle in view coordinates (TextKit 1).
    func caretRect() -> CGRect? {
        guard let lm = layoutManager, let tc = textContainer, let storage = textStorage else { return nil }
        let sel = selectedRange()
        let loc = sel.location
        let length = storage.length
        let font = caretFont(at: loc)
        let glyphHeight = (font.ascender - font.descender).rounded(.up)
        var rect: CGRect

        if length == 0 || loc >= length {
            let extra = lm.extraLineFragmentRect
            if length == 0 || (extra != .zero && lm.numberOfGlyphs > 0 && (storage.string as NSString).hasSuffix("\n")) {
                // Empty document, or caret on the empty line after a trailing newline.
                let line = extra != .zero ? extra : CGRect(x: 0, y: 0, width: 1, height: config.bodyLineHeight)
                let y = line.minY + ((line.height - glyphHeight) / 2).rounded()
                rect = CGRect(x: line.minX + tc.lineFragmentPadding, y: y, width: 1, height: glyphHeight)
            } else {
                // After the last glyph.
                let g = max(0, lm.numberOfGlyphs - 1)
                let line = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
                let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: tc)
                let baseline = lm.location(forGlyphAt: g).y
                rect = CGRect(x: glyphRect.maxX, y: line.minY + baseline - font.ascender, width: 1, height: glyphHeight)
            }
        } else {
            var g = lm.glyphIndexForCharacter(at: loc)
            var line = lm.lineFragmentRect(forGlyphAt: g, effectiveRange: nil)
            var x = line.minX + lm.location(forGlyphAt: g).x
            if selectionAffinity == .upstream && loc > 0 {
                let pg = lm.glyphIndexForCharacter(at: loc - 1)
                let prevLine = lm.lineFragmentRect(forGlyphAt: pg, effectiveRange: nil)
                let ns = storage.string as NSString
                if prevLine.minY != line.minY && ns.character(at: loc - 1) != 10 {
                    // Caret sits at the end of the previous (soft-wrapped) line.
                    g = pg
                    line = prevLine
                    x = lm.boundingRect(forGlyphRange: NSRange(location: pg, length: 1), in: tc).maxX
                }
            }
            let baseline = lm.location(forGlyphAt: g).y
            rect = CGRect(x: x, y: line.minY + baseline - font.ascender, width: 1, height: glyphHeight)
        }

        rect.origin.x += textContainerOrigin.x
        rect.origin.y += textContainerOrigin.y
        rect.size.width = config.caretWidth
        rect.size.height = glyphHeight + 2
        rect.origin.y -= 1
        let scale = window?.backingScaleFactor ?? 2
        rect.origin.x = (rect.origin.x * scale).rounded() / scale
        rect.origin.y = (rect.origin.y * scale).rounded() / scale
        return rect
    }

    func updateCaret(animated: Bool) {
        guard !isUpdatingCaret else { return }
        isUpdatingCaret = true
        defer { isUpdatingCaret = false }

        let shouldShow = window?.isKeyWindow == true
            && window?.firstResponder === self
            && selectedRange().length == 0
            && isEditable
        guard shouldShow, let rect = caretRect() else {
            hideCaret()
            return
        }
        let wasVisible = caretVisible
        caretVisible = true
        let moved = !rect.equalTo(lastCaretRect)
        lastCaretRect = rect

        let animate = animated && wasVisible && moved && config.smoothCaret && !GlassineTextView.reduceMotion && !suppressAnimationOnce
        // Sublayers of a flipped NSView's backing layer use the view's own (top-down)
        // coordinates, whatever `isGeometryFlipped` reports.
        let layerRect = rect
        CATransaction.begin()
        if animate {
            CATransaction.setAnimationDuration(config.caretDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.25, 0.8, 0.3, 1.0))
        } else {
            CATransaction.setDisableActions(true)
        }
        caretLayer.frame = layerRect
        CATransaction.commit()

        if moved || !wasVisible {
            restartBlink()
        }
    }

    private func hideCaret() {
        guard caretVisible || caretLayer.opacity != 0 else { return }
        caretVisible = false
        blinkWork?.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caretLayer.removeAllAnimations()
        caretLayer.opacity = 0
        CATransaction.commit()
    }

    private func restartBlink() {
        blinkWork?.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caretLayer.removeAnimation(forKey: "blink")
        caretLayer.opacity = 1
        CATransaction.commit()
        guard config.caretBlink != .none else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.caretVisible else { return }
            let anim = CAKeyframeAnimation(keyPath: "opacity")
            switch self.config.caretBlink {
            case .soft:
                anim.values = [1.0, 1.0, 0.12, 0.12, 1.0]
                anim.keyTimes = [0, 0.35, 0.55, 0.75, 1.0]
                anim.calculationMode = .cubic
                anim.duration = 1.25
            case .hard:
                anim.values = [1.0, 1.0, 0.0, 0.0]
                anim.keyTimes = [0, 0.5, 0.5, 1.0]
                anim.calculationMode = .discrete
                anim.duration = 1.0
            case .none:
                return
            }
            anim.repeatCount = .infinity
            self.caretLayer.add(anim, forKey: "blink")
        }
        blinkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
    }

    override func mouseDown(with event: NSEvent) {
        lastTypedWasKeyboard = false
        if event.clickCount == 1,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           let handle = listHandle(at: event) {
            // Settled on mouse up: a click toggles or places the caret, a drag moves the item.
            listDrag = ListDrag(handle: handle, start: event.locationInWindow)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var drag = listDrag else { super.mouseDragged(with: event); return }
        if !drag.dragging {
            guard abs(event.locationInWindow.y - drag.start.y) >= 4 else { return }
            drag.dragging = true
            NSCursor.closedHand.push()
        }
        _ = autoscroll(with: event)
        showDropTarget(for: drag.handle, at: event)
        listDrag = drag
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag = listDrag else { super.mouseUp(with: event); return }
        listDrag = nil
        if drag.dragging {
            NSCursor.pop()
            hideDropTarget()
            dropListItem(handleAt: drag.handle.index, toward: linePosition(at: event))
            return
        }
        switch drag.handle {
        case .box(let index):
            toggleTaskBox(at: index)
        case .marker:
            let index = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
            setSelectedRange(NSRange(location: index, length: 0))
        }
    }

    // MARK: - Task boxes and list handles

    private enum ListHandle {
        case box(Int), marker(Int)
        var index: Int { switch self { case .box(let i), .marker(let i): return i } }
    }

    private struct ListDrag {
        let handle: ListHandle
        let start: NSPoint
        var dragging = false
    }

    /// The character under the mouse, only when the pointer is really on its glyph.
    private func characterIndex(under event: NSEvent) -> Int? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        var point = convert(event.locationInWindow, from: nil)
        point.x -= textContainerOrigin.x
        point.y -= textContainerOrigin.y
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        // glyphIndex(for:) snaps to the nearest glyph; only count a click that is really on it.
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -2, dy: -1).contains(point) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return index < storage.length ? index : nil
    }

    /// The task box or list marker under the mouse: what you click to toggle, or
    /// grab to move the item within its list.
    private func listHandle(at event: NSEvent) -> ListHandle? {
        guard let storage = textStorage, let index = characterIndex(under: event) else { return nil }
        if storage.attribute(TaskBox.attributeKey, at: index, effectiveRange: nil) != nil { return .box(index) }
        let ns = storage.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
        let line = ns.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let marker = TaskReorder.markerRange(in: line), NSLocationInRange(index - lineRange.location, marker) else { return nil }
        return .marker(index)
    }

    /// `[ ]` ↔ `[x]` without moving the caret. Typing an x by hand still works, of course.
    private func toggleTaskBox(at index: Int) {
        guard let storage = textStorage else { return }
        var range = NSRange(location: 0, length: 0)
        guard let checked = storage.attribute(TaskBox.attributeKey, at: index, longestEffectiveRange: &range,
                                              in: NSRange(location: 0, length: storage.length)) as? Bool,
              range.length == 3 else { return }
        let replacement = checked ? "[ ]" : "[x]"
        let selection = selectedRange()
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        guard shouldChangeText(in: range, replacementString: replacement) else { return }
        storage.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(selection.clamped(to: storage.length))
        guard config.moveCompletedTasks else { return }
        if checked { riseUncheckedTask(boxAt: range.location) } else { scheduleSink(ofTaskAt: range.location) }
    }

    /// A task you check off waits a moment before sinking, so the check itself
    /// registers first. If the line is edited or unchecked meanwhile, it stays.
    private func scheduleSink(ofTaskAt location: Int) {
        guard let storage = textStorage else { return }
        let lines = (storage.string as NSString).components(separatedBy: "\n")
        let (lineIndex, _) = Self.line(containing: location, in: lines)
        let text = lines[lineIndex]
        pendingSinks[text]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSinks[text] = nil
            self.sinkTask(reading: text, near: lineIndex)
        }
        pendingSinks[text] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.sinkDelay, execute: work)
    }

    private func sinkTask(reading text: String, near line: Int) {
        guard config.moveCompletedTasks, let storage = textStorage else { return }
        let lines = (storage.string as NSString).components(separatedBy: "\n")
        let index: Int
        if line < lines.count, lines[line] == text { index = line }
        else if let found = lines.firstIndex(of: text) { index = found }
        else { return }
        guard let result = TaskReorder.afterToggle(lines: lines, at: index) else { return }
        let caret = selectedRange().location
        guard apply(result, from: lines) else { return }
        setSelectedRange(NSRange(location: Self.carriedCaret(caret, from: lines, to: result), length: 0))
    }

    /// An unchecked task rises straight away, back to where it came from.
    private func riseUncheckedTask(boxAt location: Int) {
        guard let storage = textStorage else { return }
        let lines = (storage.string as NSString).components(separatedBy: "\n")
        let (lineIndex, lineStart) = Self.line(containing: location, in: lines)
        let checkedForm = (lines[lineIndex] as NSString).replacingCharacters(in: NSRange(location: location - lineStart + 1, length: 1), with: "x")
        pendingSinks.removeValue(forKey: checkedForm)?.cancel()
        guard let result = TaskReorder.afterToggle(lines: lines, at: lineIndex) else { return }
        let caret = selectedRange().location
        guard apply(result, from: lines) else { return }
        setSelectedRange(NSRange(location: Self.carriedCaret(caret, from: lines, to: result), length: 0))
    }

    /// Where a caret ends up after a reorder permutes a block: on the same line
    /// (found by text) at the same column; text after the block shifts with any renumbering.
    private static func carriedCaret(_ caret: Int, from lines: [String], to result: TaskReorder.Result) -> Int {
        let bs = charOffset(ofLine: result.blockStart, in: lines)
        let be = charOffset(ofLine: result.blockEnd + 1, in: lines) - 1
        if caret < bs { return caret }
        if caret > be { return caret + (charOffset(ofLine: result.blockEnd + 1, in: result.lines) - charOffset(ofLine: result.blockEnd + 1, in: lines)) }
        let (li, lineStart) = line(containing: caret, in: lines)
        let text = lines[li], col = caret - lineStart
        var nth = 0
        for i in result.blockStart..<li where lines[i] == text { nth += 1 }
        var target = li
        for j in result.blockStart...result.blockEnd where result.lines[j] == text {
            if nth == 0 { target = j; break }
            nth -= 1
        }
        return charOffset(ofLine: target, in: result.lines) + min(col, (result.lines[target] as NSString).length)
    }

    private static func charOffset(ofLine line: Int, in lines: [String]) -> Int {
        lines.prefix(line).reduce(0) { $0 + ($1 as NSString).length + 1 }
    }

    // MARK: - Dragging list items

    /// Drops the item whose handle is at `handle` where the pointer is (`y` in
    /// line units, see `TaskReorder.Siblings`), leaving the caret on the handle.
    private func dropListItem(handleAt handle: Int, toward y: Double) {
        guard let storage = textStorage else { return }
        let lines = (storage.string as NSString).components(separatedBy: "\n")
        let (lineIndex, lineStart) = Self.line(containing: handle, in: lines)
        guard let result = TaskReorder.drag(lines: lines, itemLine: lineIndex, toward: y), apply(result, from: lines) else { return }
        let landed = Self.charOffset(ofLine: result.movedTo, in: result.lines) + (handle - lineStart)
        setSelectedRange(NSRange(location: min(landed, storage.length), length: 0))
    }

    /// Tints the item being dragged and draws a bar where it would land.
    private func showDropTarget(for handle: ListHandle, at event: NSEvent) {
        guard let storage = textStorage else { return }
        let lines = (storage.string as NSString).components(separatedBy: "\n")
        let (lineIndex, _) = Self.line(containing: handle.index, in: lines)
        guard let siblings = TaskReorder.siblings(lines: lines, at: lineIndex) else { hideDropTarget(); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dragHighlight.frame = rect(forLines: siblings.spans[siblings.index], in: lines).insetBy(dx: -6, dy: -1)
        dragHighlight.opacity = 1
        let slot = siblings.slot(toward: linePosition(at: event))
        if slot == siblings.index {
            dropBar.opacity = 0
        } else {
            let dropLine = siblings.dropLine(for: slot)
            let y = dropLine == 0
                ? rect(forLines: 0...0, in: lines).minY
                : rect(forLines: (dropLine - 1)...(dropLine - 1), in: lines).maxY
            let x = rect(forCharacters: NSRange(location: handle.index, length: 1)).minX - 4
            let right = textContainerOrigin.x + (textContainer?.size.width ?? bounds.width)
            dropBar.frame = CGRect(x: x, y: y - 1.5, width: max(0, right - x), height: 3)
            dropBar.opacity = 1
        }
        CATransaction.commit()
    }

    private func hideDropTarget() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dragHighlight.opacity = 0
        dropBar.opacity = 0
        CATransaction.commit()
    }

    /// Where the pointer is, in line units: the line under it plus how far down that line.
    private func linePosition(at event: NSEvent) -> Double {
        guard let storage = textStorage else { return 0 }
        let point = convert(event.locationInWindow, from: nil)
        let ns = storage.string as NSString
        let index = min(characterIndexForInsertion(at: point), ns.length)
        let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
        let line = Self.lineNumber(before: lineRange.location, in: ns)
        let rect = rect(forCharacters: lineRange)
        guard rect.height > 0 else { return Double(line) + 0.5 }
        return Double(line) + Double(min(max((point.y - rect.minY) / rect.height, 0), 1))
    }

    /// The layout rectangle of a run of lines, in view coordinates.
    private func rect(forLines span: ClosedRange<Int>, in lines: [String]) -> CGRect {
        let start = lines[..<span.lowerBound].reduce(0) { $0 + ($1 as NSString).length + 1 }
        let length = lines[span].reduce(0) { $0 + ($1 as NSString).length + 1 } - 1
        return rect(forCharacters: NSRange(location: start, length: max(length, 0)))
    }

    private func rect(forCharacters range: NSRange) -> CGRect {
        guard let layoutManager, let textContainer else { return .zero }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var r = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        r.origin.x += textContainerOrigin.x
        r.origin.y += textContainerOrigin.y
        return r
    }

    /// The line holding character `location`, and where that line starts.
    private static func line(containing location: Int, in lines: [String]) -> (index: Int, start: Int) {
        var lineStart = 0
        for (i, l) in lines.enumerated() {
            let len = (l as NSString).length
            if location <= lineStart + len { return (i, lineStart) }
            lineStart += len + 1
        }
        return (max(lines.count - 1, 0), max(lineStart - (lines.last ?? "").utf16.count - 1, 0))
    }

    private static func lineNumber(before location: Int, in ns: NSString) -> Int {
        var count = 0, i = 0
        while i < location {
            let r = ns.range(of: "\n", options: [], range: NSRange(location: i, length: location - i))
            if r.location == NSNotFound { break }
            count += 1
            i = r.location + 1
        }
        return count
    }

    /// Replaces the lines a reorder changed, as one undoable edit.
    private func apply(_ result: TaskReorder.Result, from lines: [String]) -> Bool {
        guard let storage = textStorage else { return false }
        let blockStart = Self.charOffset(ofLine: result.blockStart, in: lines)
        let blockLength = Self.charOffset(ofLine: result.blockEnd + 1, in: lines) - 1 - blockStart
        let newBlock = result.lines[result.blockStart...result.blockEnd].joined(separator: "\n")
        let blockRange = NSRange(location: blockStart, length: blockLength)
        guard shouldChangeText(in: blockRange, replacementString: newBlock) else { return false }
        storage.replaceCharacters(in: blockRange, with: newBlock)
        didChangeText()
        return true
    }

    // MARK: - Diagnostics

    @objc func copyDebugInfo(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(debugDescription, forType: .string)
    }

    override var debugDescription: String {
        let sel = selectedRange()
        let rect = caretRect().map { "\($0)" } ?? "nil"
        let clip = enclosingScrollView?.contentView.bounds ?? .zero
        return """
        editor
        selection: \(sel) affinity: \(selectionAffinity == .upstream ? "upstream" : "downstream")
        caretRect: \(rect) layerFrame: \(caretLayer.frame) opacity: \(caretLayer.opacity) visible: \(caretVisible)
        layerFlipped: \(layer?.isGeometryFlipped ?? false) firstResponder: \(window?.firstResponder === self) key: \(window?.isKeyWindow ?? false)
        textView frame: \(frame) inset: \(textContainerInset) container: \(textContainer?.containerSize ?? .zero)
        clip bounds: \(clip) length: \(textStorage?.length ?? -1) glyphs: \(layoutManager?.numberOfGlyphs ?? -1)
        extraLineFragment: \(layoutManager?.extraLineFragmentRect ?? .zero)
        config: font=\(config.fontFamily) \(config.fontSize)pt lh=\(config.lineHeightMultiple) col=\(config.columnWidth) top=\(config.topInset)
        caret: smooth=\(config.smoothCaret) dur=\(config.caretDuration) typing=\(config.smoothWhileTyping) blink=\(config.caretBlink) w=\(config.caretWidth)
        modes: typewriter=\(config.typewriter) focus=\(config.focus) reduceMotion=\(GlassineTextView.reduceMotion)
        """
    }

    // MARK: - Menu validation

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let markdownActions: [Selector] = [
            #selector(markdownBold(_:)), #selector(markdownItalic(_:)), #selector(markdownCode(_:)),
            #selector(markdownStrike(_:)), #selector(markdownLink(_:)), #selector(markdownHeading1(_:)),
            #selector(markdownHeading2(_:)), #selector(markdownHeading3(_:)), #selector(markdownClearHeading(_:)),
            #selector(markdownToggleTask(_:)), #selector(copyDebugInfo(_:)),
        ]
        if let action = item.action, markdownActions.contains(action) { return isEditable }
        return super.validateUserInterfaceItem(item)
    }
}

// MARK: - Vertically centered lines

extension GlassineTextView: NSLayoutManagerDelegate {
    /// TextKit 1 puts the extra space from `lineHeightMultiple` above the glyphs.
    /// Shift the baseline so the text (and therefore the caret) sits centered in
    /// its line, the way Paper does.
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        let multiple = config.lineHeightMultiple
        guard multiple > 1.0 else { return false }
        let used = lineFragmentUsedRect.pointee.height
        let natural = used / multiple
        let extra = used - natural
        guard extra > 0 else { return false }
        baselineOffset.pointee -= (extra / 2).rounded()
        return true
    }
}

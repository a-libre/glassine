import UIKit
import CoreText
import QuartzCore

/// The editor's text view on iOS: a UITextView on the same TextKit 1 stack as
/// the Mac's NSTextView — one storage, the shared GlassineLayoutManager, one
/// container — so the styler, the capsules, the hidden Markdown and the
/// caret's geometry are the same code. What is written here is what UIKit
/// spells differently: where edits are heard, how the column is inset (the
/// text view is its own scroll view), the software keyboard, and touch.
final class GlassineTextView: UITextView {
    var config: StyleConfig {
        didSet { if config != oldValue { applyConfig(previous: oldValue) } }
    }
    let styler: MarkdownStyler

    /// Called after every user edit (including undo/redo).
    var onTextChanged: (() -> Void)?
    /// Called when the insertion point moves.
    var onSelectionChanged: (() -> Void)?
    /// Called when Escape is pressed on an attached keyboard.
    var onEscape: (() -> Void)?

    /// The editor currently on screen (there is only ever one).
    static weak var current: GlassineTextView?

    /// The stretch around the caret whose Markdown shows as written; the
    /// layout manager reads it to know whether a rule's dashes are on view.
    private(set) var syntaxRevealRange = NSRange(location: NSNotFound, length: 0)

    private let caret: CaretLayers
    // The text system holds these weakly; keep them alive here.
    private let ownedStorage: NSTextStorage
    private let ownedLayoutManager: GlassineLayoutManager

    // Editing bookkeeping
    private var pendingEditRange: NSRange?
    private var lastEditAt: CFTimeInterval = 0
    private var suppressAnimationOnce = false
    private var isLoading = false

    // Focus mode: a mask over the text — the page at the dimming setting, the
    // paragraph (or sentence) being written at full strength.
    private let focusMask = CALayer()
    private let focusWindow = CALayer()
    private var lastFocusRange = NSRange(location: NSNotFound, length: 0)
    /// Focus mode steps aside while the reader scrolls — the whole page comes
    /// back — and returns the moment the caret is placed or moved again.
    private var focusLifted = false

    private lazy var taskTap = UITapGestureRecognizer(target: self, action: #selector(tappedTaskBox(_:)))
    /// When a finger last came down, to tell a tap's selection from an arrow key's.
    private var lastTouchAt: CFTimeInterval = 0

    /// How much of the view the software keyboard covers, from the bottom.
    private var keyboardOverlap: CGFloat = 0
    private var observers: [NSObjectProtocol] = []
    private let placeholderLabel = UILabel()
    /// Shown in an empty document, at the caret, in the syntax colour.
    var placeholder = "Start writing" { didSet { placeholderLabel.text = placeholder } }

    /// The margin either side of the column: a phone has less to give.
    private var minimumSideMargin: CGFloat { bounds.width < 500 ? 22 : 40 }

    // MARK: - Init

    init(config: StyleConfig) {
        self.config = config
        styler = MarkdownStyler(config: config)
        caret = CaretLayers(config: config)

        let storage = NSTextStorage()
        let layoutManager = GlassineLayoutManager()
        ownedStorage = storage
        ownedLayoutManager = layoutManager
        layoutManager.allowsNonContiguousLayout = false
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        super.init(frame: .zero, textContainer: container)
        layoutManager.owner = self
        layoutManager.delegate = self
        delegate = self
        commonInit()
        GlassineTextView.current = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func commonInit() {
        backgroundColor = .clear
        isEditable = true
        isSelectable = true
        alwaysBounceVertical = true
        keyboardDismissMode = .interactive
        contentInsetAdjustmentBehavior = .never
        dataDetectorTypes = []
        allowsEditingTextAttributes = false
        showsHorizontalScrollIndicator = false

        caret.install(in: layer)
        caret.mayPerform = { [weak self] in self?.isFirstResponder ?? false }

        focusMask.anchorPoint = .zero
        focusMask.backgroundColor = UIColor.black.cgColor
        focusWindow.anchorPoint = .zero
        focusWindow.backgroundColor = UIColor.black.cgColor
        focusWindow.opacity = 0
        focusMask.addSublayer(focusWindow)

        placeholderLabel.text = placeholder
        placeholderLabel.isUserInteractionEnabled = false
        addSubview(placeholderLabel)

        // A tap on a task's box checks it off; anywhere else the tap is the text view's.
        addGestureRecognizer(taskTap)

        let nc = NotificationCenter.default
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardWillHideNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.keyboardChanged(note)
            })
        }
        applyConfig(previous: nil)
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// How far the viewport is scrolled through the document, 0–1.
    var scrollFraction: Double {
        let maxY = contentSize.height - bounds.height
        guard maxY > 0 else { return 0 }
        return Double(max(0, min(1, contentOffset.y / maxY)))
    }

    // MARK: - What shared code asks of the text view

    var caretLocation: Int { selectedRange.location }
    var plainText: String { textStorage.string }

    // MARK: - Config

    private func applyConfig(previous: StyleConfig?) {
        styler.config = config
        caret.config = config
        let theme = config.theme
        // UIKit tints the selection and its handles from one colour; the system's
        // own caret is kept out of sight (caretRect(for:)), ours is `caret`.
        tintColor = theme.caretColor
        linkTextAttributes = [.foregroundColor: theme.linkColor]
        typingAttributes = config.baseAttributes
        indicatorStyle = theme.isDark ? .white : .black
        keyboardAppearance = theme.isDark ? .dark : .light
        spellCheckingType = config.spellCheck ? .yes : .no
        smartQuotesType = config.smartQuotes ? .yes : .no
        smartDashesType = config.smartDashes ? .yes : .no
        autocorrectionType = config.autocorrect ? .yes : .no
        inlinePredictionType = config.inlinePredictions ? .yes : .no
        placeholderLabel.font = config.bodyFont
        placeholderLabel.textColor = theme.syntax.withAlpha(theme.isDark ? 0.45 : 0.5)

        let typographyChanged: Bool = {
            guard let p = previous else { return true }
            return p.theme != config.theme || p.fontFamily != config.fontFamily || p.fontSize != config.fontSize
                || p.lineHeightMultiple != config.lineHeightMultiple || p.paragraphSpacingEm != config.paragraphSpacingEm
                || p.paragraphIndentEm != config.paragraphIndentEm
                || p.letterSpacing != config.letterSpacing || p.scaledHeadings != config.scaledHeadings
        }()
        if typographyChanged, textStorage.length > 0 {
            let sel = selectedRange
            styler.restyle(textStorage, range: NSRange(location: 0, length: textStorage.length))
            selectedRange = sel.clamped(to: textStorage.length)
        }
        updateInsets()
        if let p = previous, p.focus != config.focus { focusLifted = false }
        updateFocus(animated: previous != nil)
        if let p = previous, p.hideSyntax != config.hideSyntax, textStorage.length > 0 {
            syntaxRevealRange = NSRange(location: NSNotFound, length: 0)
            let full = NSRange(location: 0, length: textStorage.length)
            layoutManager.invalidateGlyphs(forCharacterRange: full, changeInLength: 0, actualCharacterRange: nil)
            layoutManager.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
            layoutManager.invalidateDisplay(forCharacterRange: full)
            updateSyntaxReveal()
        }
        updateCaret(animated: false)
        if config.typewriter && previous?.typewriter == false { typewriterScroll(animated: true) }
    }

    // MARK: - Document swapping

    func load(text: String, caretAt position: Int?) {
        suppressAnimationOnce = true
        isLoading = true
        undoManager?.removeAllActions()
        textStorage.beginEditing()
        textStorage.setAttributedString(NSAttributedString(string: text, attributes: config.baseAttributes))
        textStorage.endEditing()
        styler.restyle(textStorage, range: NSRange(location: 0, length: textStorage.length))
        let loc = min(max(0, position ?? textStorage.length), textStorage.length)
        selectedRange = NSRange(location: loc, length: 0)
        typingAttributes = config.baseAttributes
        isLoading = false
        lastFocusRange = NSRange(location: NSNotFound, length: 0)
        updatePlaceholder()
        // Give layout a moment, then place the caret and scroll without animation.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateInsets()
            self.updateSyntaxReveal()
            self.scrollRangeToVisible(self.selectedRange)
            if self.config.typewriter { self.typewriterScroll(animated: false) }
            self.updateFocus(animated: false)
            self.updateCaret(animated: false)
            self.suppressAnimationOnce = false
            #if targetEnvironment(simulator)
            SimulatorScript.runIfAsked(on: self)
            #endif
        }
    }

    /// Replaces the text after an external change while trying to keep the caret in place.
    func replaceText(with text: String) {
        let sel = selectedRange
        isLoading = true
        textStorage.beginEditing()
        textStorage.setAttributedString(NSAttributedString(string: text, attributes: config.baseAttributes))
        textStorage.endEditing()
        styler.restyle(textStorage, range: NSRange(location: 0, length: textStorage.length))
        selectedRange = sel.clamped(to: textStorage.length)
        isLoading = false
        updatePlaceholder()
        updateFocus(animated: false)
        updateCaret(animated: false)
    }

    // MARK: - Layout: centered column + insets

    /// The height of the view the keyboard leaves showing.
    private var viewportHeight: CGFloat { max(0, bounds.height - keyboardOverlap) }

    func updateInsets() {
        let width = bounds.width
        guard width > 0 else { return }
        let usable = max(0, width - 2 * minimumSideMargin)
        let column = min(usable, config.columnWidth)
        let side = ((width - column) / 2).rounded(.down)

        // The Mac's top margin clears a title bar's worth of glass; a phone has
        // the status bar to clear and less height to spend.
        let compact = width < 500
        var top = safeAreaInsets.top + (compact ? min(config.topInset, 28) : config.topInset)
        var bottom = safeAreaInsets.bottom + 48
        if config.typewriter, viewportHeight > 0 {
            // Room above the first line and below the last for either to sit at the middle.
            top = max(top, (viewportHeight / 2 - config.bodyLineHeight / 2).rounded())
            bottom = max(bottom, (viewportHeight / 2).rounded())
        }
        let newInset = UIEdgeInsets(top: top, left: side, bottom: bottom, right: side)
        let oldInset = textContainerInset
        if contentInset.bottom != keyboardOverlap {
            contentInset.bottom = keyboardOverlap
            verticalScrollIndicatorInsets.bottom = keyboardOverlap
        }
        guard newInset != oldInset else { return }
        let oldOffset = contentOffset
        textContainerInset = newInset
        if newInset.top != oldInset.top, oldInset != .zero {
            // The whole document just shifted by the inset delta; move the viewport
            // by the same amount so nothing appears to jump.
            layoutManager.ensureLayout(for: textContainer)
            layoutIfNeeded()
            let delta = newInset.top - oldInset.top
            let maxY = max(0, contentSize.height + contentInset.bottom - bounds.height)
            setContentOffset(CGPoint(x: oldOffset.x, y: max(0, min(oldOffset.y + delta, maxY))), animated: false)
        }
        updatePlaceholder()
        updateFocus(animated: false)
        updateCaret(animated: false)
    }

    private var lastLaidOutSize: CGSize = .zero

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastLaidOutSize {
            lastLaidOutSize = bounds.size
            updateInsets()
            updateCaret(animated: false)
        }
        layoutFocusMask()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateInsets()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        caret.setScale(window?.screen.scale ?? traitCollection.displayScale)
        updateCaret(animated: false)
    }

    private func keyboardChanged(_ note: Notification) {
        guard let window, let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let hidden = note.name == UIResponder.keyboardWillHideNotification
        let inView = convert(window.convert(end, from: nil), from: nil)
        let visible = CGRect(origin: contentOffset, size: bounds.size)
        let overlap = hidden ? 0 : max(0, visible.maxY - inView.minY)
        guard abs(overlap - keyboardOverlap) > 0.5 else { return }
        keyboardOverlap = overlap
        updateInsets()
        if config.typewriter { typewriterScroll(animated: true) } else { scrollRangeToVisible(selectedRange) }
    }

    private func updatePlaceholder() {
        placeholderLabel.isHidden = textStorage.length > 0 || placeholder.isEmpty
        guard !placeholderLabel.isHidden else { return }
        placeholderLabel.sizeToFit()
        let font = config.bodyFont
        placeholderLabel.frame.origin = CGPoint(
            x: textContainerInset.left + config.paragraphIndent + 1,
            y: textContainerInset.top + (config.bodyLineHeight - font.ascender + font.descender) / 2)
    }

    // MARK: - The system's caret

    /// The system caret keeps its place — scrolling to it and the keyboard's
    /// own bookkeeping depend on that — but has no width to be seen by.
    override func caretRect(for position: UITextPosition) -> CGRect {
        var rect = super.caretRect(for: position)
        rect.size.width = 0
        return rect
    }

    // MARK: - Smooth caret

    private var textContainerOrigin: CGPoint { CGPoint(x: textContainerInset.left, y: textContainerInset.top) }

    private func caretFont(at location: Int) -> UIFont {
        let storage = textStorage
        guard storage.length > 0 else { return (typingAttributes[.font] as? UIFont) ?? config.bodyFont }
        let idx = min(max(0, location - 1), storage.length - 1)
        // Use the following character's font at the very start of a paragraph.
        let ns = storage.string as NSString
        let useNext = location == 0 || (location < storage.length && ns.character(at: idx) == 10)
        let probe = useNext ? min(location, storage.length - 1) : idx
        return (storage.attribute(.font, at: probe, effectiveRange: nil) as? UIFont) ?? config.bodyFont
    }

    /// Insertion point rectangle in the view's (content) coordinates — the
    /// Mac's arithmetic, on the same layout manager.
    func insertionRect() -> CGRect? {
        let lm = layoutManager, tc = textContainer, storage = textStorage
        let loc = min(selectedRange.location, storage.length)
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
                rect = CGRect(x: line.minX + tc.lineFragmentPadding + (length == 0 ? config.paragraphIndent : 0), y: y, width: 1, height: glyphHeight)
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
            if selectionAffinity == .backward && loc > 0 {
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
        let scale = window?.screen.scale ?? 3
        rect.origin.x = (rect.origin.x * scale).rounded() / scale
        rect.origin.y = (rect.origin.y * scale).rounded() / scale
        return rect
    }

    /// The width of the character after the caret, for a shape that sits over
    /// it, or a stand-in — half an em — at the end of a line, before a tab, or
    /// where the next glyph is one of the hidden marks.
    private func nextSlotWidth() -> CGFloat {
        let fallback = (config.fontSize * 0.5).rounded()
        let lm = layoutManager, storage = textStorage
        let loc = selectedRange.location
        guard loc < storage.length else { return fallback }
        let ch = (storage.string as NSString).character(at: loc)
        guard ch != 10, ch != 9 else { return fallback }
        let g = lm.glyphIndexForCharacter(at: loc)
        guard lm.propertyForGlyph(at: g) != .null else { return fallback }
        let width = lm.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: textContainer).width
        return width > 1 ? width : fallback
    }

    func updateCaret(animated: Bool) {
        let shouldShow = isFirstResponder && selectedRange.length == 0 && isEditable && window != nil
        guard shouldShow, let rect = insertionRect() else { caret.hide(); return }
        let typing = pendingEditRange != nil || CACurrentMediaTime() - lastEditAt < 0.05
        let font = caretFont(at: selectedRange.location)
        caret.place(.init(rect: rect, baseline: font.ascender + 1, slot: nextSlotWidth()),
                    animated: animated && !suppressAnimationOnce, typing: typing)
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        updateCaret(animated: false)
        return ok
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        updateCaret(animated: false)
        return ok
    }

    // MARK: - Typewriter scrolling

    func typewriterScroll(animated: Bool) {
        guard let rect = insertionRect(), viewportHeight > 0 else { return }
        var target = rect.midY - viewportHeight / 2
        let maxY = max(0, contentSize.height + contentInset.bottom - bounds.height)
        target = max(0, min(target, maxY))
        if abs(target - contentOffset.y) < 0.5 { return }
        let offset = CGPoint(x: contentOffset.x, y: target)
        if animated && !Platform.reduceMotion {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.setContentOffset(offset, animated: false)
            }
        } else {
            setContentOffset(offset, animated: false)
        }
    }

    // MARK: - Focus mode

    /// The mask is as large as the content and moves with it; the window in it
    /// is the paragraph — or the sentence — the caret is in, full width.
    private func layoutFocusMask() {
        guard layer.mask === focusMask else { return }
        let size = CGSize(width: bounds.width, height: max(contentSize.height, bounds.height) + bounds.height)
        if focusMask.bounds.size != size {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            focusMask.frame = CGRect(origin: CGPoint(x: 0, y: -bounds.height / 2), size: size)
            CATransaction.commit()
        }
    }

    private func focusRange() -> NSRange {
        let ns = textStorage.string as NSString
        let sel = selectedRange.clamped(to: textStorage.length)
        var range = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        if config.focusScope == .sentence {
            var found: NSRange?
            ns.enumerateSubstrings(in: range, options: [.bySentences, .substringNotRequired]) { _, r, enclosing, stop in
                if NSLocationInRange(sel.location, enclosing) || sel.location == enclosing.upperBoundValue {
                    found = r
                    stop.pointee = true
                }
            }
            if let f = found { range = f }
        }
        return range
    }

    /// Dims the page around the caret's paragraph, or lifts the dimming. The
    /// Mac recolours the text; UIKit's layout manager has no temporary
    /// attributes to do that with, so here the page is masked instead: the
    /// same floor, the same fades.
    func updateFocus(animated: Bool) {
        let on = config.focus && !focusLifted
        if on || layer.mask === focusMask {
            if layer.mask !== focusMask { layer.mask = focusMask }
            layoutFocusMask()
        }
        guard layer.mask === focusMask else { return }
        let floor = Float(max(0, min(1, config.focusDimming)))
        CATransaction.begin()
        if animated && !Platform.reduceMotion {
            CATransaction.setAnimationDuration(0.25)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        if on {
            let range = focusRange()
            lastFocusRange = range
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = range.length > 0
                ? layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
                : (insertionRect()?.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y) ?? .zero)
            rect = rect.offsetBy(dx: 0, dy: textContainerOrigin.y - focusMask.frame.minY).insetBy(dx: 0, dy: -4)
            focusWindow.frame = CGRect(x: 0, y: rect.minY, width: focusMask.bounds.width, height: rect.height)
            focusWindow.opacity = 1
            focusMask.backgroundColor = UIColor.black.withAlphaComponent(CGFloat(floor)).cgColor
        } else {
            lastFocusRange = NSRange(location: NSNotFound, length: 0)
            focusMask.backgroundColor = UIColor.black.cgColor
        }
        CATransaction.commit()
    }

    // MARK: - Hidden Markdown

    /// What stays as written while the syntax is hidden: the sentence the
    /// caret is in — finish it and move on, and its marks go too. A selection
    /// keeps its whole paragraph span open. A rule's line is a sentence of its own.
    private func revealRange(in storage: NSTextStorage) -> NSRange {
        let ns = storage.string as NSString
        let sel = selectedRange.clamped(to: storage.length)
        let para = ns.paragraphRange(for: sel)
        guard sel.length == 0 else { return para }
        var found: NSRange?
        ns.enumerateSubstrings(in: para, options: [.bySentences, .substringNotRequired]) { _, _, enclosing, stop in
            if NSLocationInRange(sel.location, enclosing) || sel.location == enclosing.upperBoundValue {
                found = enclosing
                stop.pointee = true
            }
        }
        return found ?? para
    }

    private func updateSyntaxReveal() {
        let lm = layoutManager, storage = textStorage
        let ns = storage.string as NSString
        let new = revealRange(in: storage)
        let old = syntaxRevealRange
        syntaxRevealRange = new
        func paragraphs(_ r: NSRange) -> Int {
            guard r.location != NSNotFound, r.length > 0 else { return 0 }
            return ns.substring(with: r.clamped(to: storage.length)).components(separatedBy: "\n").count
        }
        guard new.location != old.location || paragraphs(new) != paragraphs(old) else { return }
        // Only a paragraph whose glyphs change with the reveal is worth
        // re-laying out; a rule's dashes change only in whether they are drawn.
        func has(_ key: NSAttributedString.Key, in r: NSRange) -> Bool {
            var found = false
            storage.enumerateAttribute(key, in: r, options: []) { value, _, stop in
                if value != nil { found = true; stop.pointee = true }
            }
            return found
        }
        for r in [old, new] where r.location != NSNotFound {
            let range = r.clamped(to: storage.length)
            guard range.length > 0 else { continue }
            if has(Syntax.ruleKey, in: range) { lm.invalidateDisplay(forCharacterRange: range) }
            guard config.hideSyntax, has(Syntax.hiddenKey, in: range) || has(Syntax.bulletKey, in: range) else { continue }
            lm.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
            lm.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
            lm.invalidateDisplay(forCharacterRange: range)
            lm.ensureLayout(forCharacterRange: range)
        }
        updateCaret(animated: false)
    }

    // MARK: - Editing

    /// An edit made on the user's behalf — a date, a list marker, a task's box —
    /// through the text input system, so it is undoable like typing, followed by
    /// everything a keystroke is followed by.
    private func edit(_ range: NSRange, with string: String, caretAt caret: Int? = nil) {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end) else { return }
        pendingEditRange = NSRange(location: range.location, length: string.nsLength)
        lastEditAt = CACurrentMediaTime()
        replace(textRange, withText: string)
        if let caret { selectedRange = NSRange(location: min(caret, textStorage.length), length: 0) }
        textDidChange()
    }

    /// AppKit and UIKit both refresh the typing attributes when the selection
    /// moves, which during typing is before the styler has run. After each
    /// restyle they follow the character before the caret; at the start of a
    /// paragraph, the base.
    private func syncTypingAttributes() {
        let storage = textStorage
        let loc = selectedRange.location
        var attrs = config.baseAttributes
        if loc > 0, loc <= storage.length, (storage.string as NSString).character(at: loc - 1) != 10 {
            let styled = storage.attributes(at: loc - 1, effectiveRange: nil)
            for key in [NSAttributedString.Key.font, .foregroundColor, .paragraphStyle, .kern] {
                if let value = styled[key] { attrs[key] = value }
            }
        }
        typingAttributes = attrs
    }

    private func textDidChange() {
        // While an input method is composing, the marked text is the keyboard's; style it once it lands.
        if markedTextRange == nil {
            let range = pendingEditRange ?? NSRange(location: selectedRange.location, length: 0)
            styler.restyle(textStorage, range: range.clamped(to: textStorage.length))
            syncTypingAttributes()
        }
        pendingEditRange = nil
        updatePlaceholder()
        updateSyntaxReveal()
        lastEditAt = CACurrentMediaTime()
        onTextChanged?()
        focusLifted = false
        updateFocus(animated: true)
        updateCaret(animated: config.smoothWhileTyping)
        if config.typewriter { typewriterScroll(animated: true) }
    }

    /// Replaces a shortcut word right before the caret with the actual date.
    @discardableResult
    private func expandDateShortcutIfNeeded() -> Bool {
        let sel = selectedRange
        guard sel.length == 0, sel.location > 0 else { return false }
        let ns = textStorage.string as NSString
        let paragraphStart = ns.paragraphRange(for: sel).location
        let start = max(paragraphStart, sel.location - 12)
        let lookback = NSRange(location: start, length: sel.location - start)
        let tail = ns.substring(with: lookback)
        let tailNS = tail as NSString
        guard let m = DateToken.shortcutRegex.firstMatch(in: tail, options: [], range: NSRange(location: 0, length: tailNS.length)),
              let date = DateToken.date(for: tailNS.substring(with: m.range(at: 1))) else { return false }
        let token = "@" + DateToken.format(date)
        let range = NSRange(location: lookback.location + m.range.location, length: m.range.length)
        edit(range, with: token, caretAt: range.location + token.nsLength)
        return true
    }

    private static let listLineRx = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+]|(\\d{1,3})[.)])([ \\t]+)(\\[[ xX]\\][ \\t]+)?(.*)$")

    /// Markdown list continuation: Return on "- item" starts "- ", Return on an
    /// empty "- " removes the marker.
    private func continueListIfNeeded() -> Bool {
        let ns = textStorage.string as NSString
        let sel = selectedRange
        guard sel.length == 0 else { return false }
        var lineRange = ns.paragraphRange(for: sel)
        if lineRange.length > 0 && ns.character(at: lineRange.upperBoundValue - 1) == 10 { lineRange.length -= 1 }
        // Only act when the caret is at the end of the line.
        guard sel.location == lineRange.upperBoundValue else { return false }
        let line = ns.substring(with: lineRange)
        let lineNS = line as NSString
        guard let m = Self.listLineRx.firstMatch(in: line, options: [], range: NSRange(location: 0, length: lineNS.length)) else { return false }
        let indent = lineNS.substring(with: m.range(at: 1))
        let marker = lineNS.substring(with: m.range(at: 2))
        let gap = lineNS.substring(with: m.range(at: 4))
        let hasTask = m.range(at: 5).location != NSNotFound
        let content = lineNS.substring(with: m.range(at: 6))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            // An empty item ends the list by clearing the marker.
            edit(lineRange, with: "", caretAt: lineRange.location)
            return true
        }
        var nextMarker = marker
        if m.range(at: 3).location != NSNotFound, let n = Int(lineNS.substring(with: m.range(at: 3))) {
            nextMarker = "\(n + 1)" + marker.suffix(1)
        }
        let insertion = "\n" + indent + nextMarker + gap + (hasTask ? "[ ] " : "")
        edit(sel, with: insertion, caretAt: sel.location + insertion.nsLength)
        return true
    }

    // MARK: - Task boxes

    /// The character under a point, only when the point is really on its glyph.
    private func characterIndex(at viewPoint: CGPoint) -> Int? {
        guard textStorage.length > 0 else { return nil }
        let point = CGPoint(x: viewPoint.x - textContainerOrigin.x, y: viewPoint.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs else { return nil }
        // A finger is blunter than a pointer: the box answers a little beyond its glyphs.
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -10, dy: -6).contains(point) else { return nil }
        let index = layoutManager.characterIndexForGlyph(at: glyph)
        return index < textStorage.length ? index : nil
    }

    private func taskBox(at point: CGPoint) -> NSRange? {
        guard let index = characterIndex(at: point) else { return nil }
        var range = NSRange(location: 0, length: 0)
        guard textStorage.attribute(TaskBox.attributeKey, at: index, longestEffectiveRange: &range,
                                    in: NSRange(location: 0, length: textStorage.length)) != nil, range.length == 3 else { return nil }
        return range
    }

    /// `[ ]` ↔ `[x]` without moving the caret.
    @objc private func tappedTaskBox(_ tap: UITapGestureRecognizer) {
        guard let range = taskBox(at: tap.location(in: self)),
              let checked = textStorage.attribute(TaskBox.attributeKey, at: range.location, effectiveRange: nil) as? Bool else { return }
        let selection = selectedRange
        edit(range, with: checked ? "[ ]" : "[x]")
        selectedRange = selection.clamped(to: textStorage.length)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - An attached keyboard

    override var keyCommands: [UIKeyCommand]? {
        let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escapePressed))
        escape.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [escape]
    }

    @objc private func escapePressed() { onEscape?() }
}

// MARK: - Hearing edits

extension GlassineTextView: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // A finished "@today" / "@yesterday" / "@tomorrow" becomes a date when the
        // next space or punctuation mark arrives, or the line ends.
        if text.count == 1, let ch = text.first, ch == " " || ch == "\t" || ch == "\n" || ",.;:!?)]".contains(ch),
           range.length == 0, expandDateShortcutIfNeeded() {
            // The date took the caret with it; the character lands after it.
            let sel = selectedRange
            if text == "\n", config.continueLists, continueListIfNeeded() { return false }
            edit(sel, with: text, caretAt: sel.location + text.nsLength)
            return false
        }
        if text == "\n", range.length == 0, config.continueLists, continueListIfNeeded() { return false }
        pendingEditRange = NSRange(location: range.location, length: text.nsLength)
        lastEditAt = CACurrentMediaTime()
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        guard !isLoading else { return }
        textDidChange()
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard !isLoading else { return }
        let justEdited = pendingEditRange != nil || CACurrentMediaTime() - lastEditAt < 0.05
        updateCaret(animated: config.smoothWhileTyping || !justEdited)
        onSelectionChanged?()
        // A tap or a caret move after scrolling brings focus back, there.
        focusLifted = false
        if pendingEditRange == nil {
            updateSyntaxReveal()
            updateFocus(animated: true)
            // A tap moves the line to the middle only if asked to; the arrow keys always do.
            let byTouch = CACurrentMediaTime() - lastTouchAt < 0.6
            if config.typewriter, config.typewriterOnClick || !byTouch { typewriterScroll(animated: true) }
        }
    }

    /// Scrolling is reading, so the dimming lifts and the whole page is there
    /// to read. It comes back with the next tap or keystroke. Only a finger on
    /// the glass counts — not the scrolling the typewriter does by itself.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard config.focus, !focusLifted else { return }
        focusLifted = true
        updateFocus(animated: true)
    }
}

extension GlassineTextView {
    /// The tap is ours only when it lands on a task's box.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === taskTap { return taskBox(at: gestureRecognizer.location(in: self)) != nil }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        lastTouchAt = CACurrentMediaTime()
        return super.hitTest(point, with: event)
    }
}

// MARK: - Glyphs: vertically centred lines, hidden Markdown

extension GlassineTextView: NSLayoutManagerDelegate {
    /// TextKit 1 puts the extra space from `lineHeightMultiple` above the glyphs.
    /// Shift the baseline so the text (and therefore the caret) sits centered in
    /// its line, the way Paper does.
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
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

    /// Hidden Markdown: a marker outside the sentence being written becomes a
    /// glyph that is not drawn and takes no room, so `**bold**` reads as bold
    /// and `# Title` as a title. A bullet's `-` is drawn as a bullet. The
    /// characters are all still there; only their glyphs change.
    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: UIFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard glyphRange.length > 0, config.hideSyntax else { return 0 }
        let storage = textStorage
        let count = glyphRange.length
        let first = characterIndexes[0], last = characterIndexes[count - 1]
        let charRange = NSRange(location: first, length: last - first + 1).clamped(to: storage.length)
        guard charRange.length > 0 else { return 0 }
        let reveal = revealRange(in: storage)
        var hidden: [NSRange] = []
        var bullets: [NSRange] = []
        storage.enumerateAttribute(Syntax.hiddenKey, in: charRange, options: []) { value, r, _ in
            if value != nil, !NSLocationInRange(r.location, reveal) { hidden.append(r) }
        }
        storage.enumerateAttribute(Syntax.bulletKey, in: charRange, options: []) { value, r, _ in
            if value != nil, !NSLocationInRange(r.location, reveal) { bullets.append(r) }
        }
        guard !hidden.isEmpty || !bullets.isEmpty else { return 0 }
        var newGlyphs = Array(UnsafeBufferPointer(start: glyphs, count: count))
        var newProps = Array(UnsafeBufferPointer(start: props, count: count))
        var bullet: CGGlyph = 0
        if !bullets.isEmpty {
            var dot: UniChar = 0x2022
            let ctFont = CTFontCreateWithFontDescriptor(font.fontDescriptor as CTFontDescriptor, font.pointSize, nil)
            CTFontGetGlyphsForCharacters(ctFont, &dot, &bullet, 1)
        }
        for i in 0..<count {
            let c = characterIndexes[i]
            if hidden.contains(where: { NSLocationInRange(c, $0) }) {
                newProps[i] = .null
            } else if bullet != 0, bullets.contains(where: { NSLocationInRange(c, $0) }) {
                newGlyphs[i] = bullet
            }
        }
        layoutManager.setGlyphs(newGlyphs, properties: newProps, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return count
    }
}

import AppKit
import SwiftUI
import WebKit

enum ReviewStyle: String, Codable, CaseIterable, Identifiable {
    case glass, reader, gallery, editorial, newspaper, book, bookDark, typewriter, notebook, thesis, verse, github, mono, blueprint
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glass: return "Glass"
        case .reader: return "Reader"
        case .gallery: return "Gallery"
        case .editorial: return "Editorial"
        case .newspaper: return "Newspaper"
        case .book: return "Book"
        case .bookDark: return "Book Dark"
        case .typewriter: return "Typewriter"
        case .notebook: return "Notebook"
        case .thesis: return "Thesis"
        case .verse: return "Verse"
        case .github: return "GitHub"
        case .mono: return "Mono"
        case .blueprint: return "Blueprint"
        }
    }
    /// A style that brings its own paper is light or dark whatever the
    /// theme; nil follows the theme.
    var fixedLight: Bool? {
        switch self {
        case .book, .typewriter, .notebook: return true
        case .bookDark, .blueprint: return false
        default: return nil
        }
    }
}

/// Review mode: the document rendered as real HTML in a web view, in one of a
/// few typographic styles. Read-only; Esc or ⌘↩ goes back to the editor.
///
/// `beside` is the same page to the right of the editor (⌘⇧↩): it is redrawn
/// in place as the text changes and scrolls to the block the caret is in,
/// and Esc stays the editor's.
struct ReviewView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var document: DocumentModel
    let initialScrollFraction: Double
    var beside: Bool = false

    private var theme: Theme { state.pageTheme }
    private var style: ReviewStyle { state.settings.data.reviewStyle }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ReviewWebView(
                html: ReviewHTML.document(markdown: document.text, title: document.title, style: style,
                                          theme: theme, scale: state.settings.data.reviewFontScale,
                                          centerHeadings: state.settings.data.centerHeadings),
                scale: state.settings.data.reviewFontScale,
                initialScrollFraction: initialScrollFraction,
                baseURL: document.url.deletingLastPathComponent(),
                onToggleTask: { index, checked in state.toggleTask(ordinal: index, checked: checked) },
                live: beside,
                followLine: beside ? state.caretLine : nil
            )
            .ignoresSafeArea()

            controls
                .padding(.top, 10)
                .padding(.trailing, 14)
        }
        .background(
            Group {
                if !beside {
                    Button("") { state.reviewMode = false }
                        .keyboardShortcut(.cancelAction)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                }
            }
        )
    }

    private var controls: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("Style", selection: Binding(
                    get: { state.settings.data.reviewStyle },
                    set: { state.settings.data.reviewStyle = $0 }
                )) {
                    ForEach(ReviewStyle.allCases) { s in Text(s.label).tag(s) }
                }
                .pickerStyle(.inline)
                Divider()
                Button("Copy as Markdown") { state.copyCurrentDocument(asMarkdown: true) }
                Button("Copy as Rich Text") { state.copyCurrentDocument(asMarkdown: false) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "eyeglasses").font(.system(size: 11, weight: .semibold))
                    Text("Review · \(style.label)").font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.6)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                if beside { state.toggleReviewBeside() } else { state.reviewMode = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(beside ? "Put the page away (⌘⇧↩)" : "Back to editing (Esc or ⌘↩)")
        }
        .foregroundStyle(styleIsLight ? Color.black.opacity(0.75) : Color.white.opacity(0.85))
        .padding(.leading, 4)
        .background(Capsule().fill(styleIsLight ? Color.black.opacity(0.07) : Color.white.opacity(0.12)))
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(styleIsLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12)))
    }

    /// Whether the rendered page behind the controls is light, so the pill stays legible.
    private var styleIsLight: Bool {
        style.fixedLight ?? !theme.isDark
    }
}

// MARK: - Web view

struct ReviewWebView: NSViewRepresentable {
    let html: String
    let scale: Double
    let initialScrollFraction: Double
    let baseURL: URL
    /// A checkbox was clicked: the n-th task in the document, and its new state.
    /// Returns false when the document could not follow, so the page is put back.
    var onToggleTask: (Int, Bool) -> Bool = { _, _ in false }
    /// Beside the editor: a change to the text is put into the page in place, a
    /// beat after typing pauses, instead of reloading it — no blink, the scroll
    /// kept — and the page scrolls to keep the block on `followLine` in view.
    var live: Bool = false
    var followLine: Int? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Report scroll position so style switches and re-renders keep the reader's place.
        let tracker = """
        window.addEventListener('scroll', function() {
          var max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
          window.webkit.messageHandlers.glassineScroll.postMessage(window.scrollY / max);
        }, { passive: true });
        """
        config.userContentController.addUserScript(WKUserScript(source: tracker, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: "glassineScroll")
        // Task checkboxes are live: a click reports the item's ordinal, and the
        // document answers with the states to show (see updateNSView).
        let tasks = """
        (function() {
          function boxes() { return document.querySelectorAll('li.task > input[type=checkbox]'); }
          function paint(box, on) { var li = box.closest('li'); if (li) li.classList.toggle('done', on); }
          function bind() {
            boxes().forEach(function(box, i) {
              box.addEventListener('change', function() {
                paint(box, box.checked);
                window.webkit.messageHandlers.glassineTask.postMessage({ index: i, checked: box.checked });
              });
            });
          }
          bind();
          window.glassineSetTasks = function(states) {
            boxes().forEach(function(box, i) {
              if (i < states.length) { box.checked = states[i]; paint(box, states[i]); }
            });
          };
          // Beside the editor: the new body put in place of the old, the boxes rebound.
          window.glassineSetBody = function(html) {
            var a = document.querySelector('article');
            if (!a) return;
            a.innerHTML = html;
            bind();
          };
          // The block that starts on or before a source line, brought a third of
          // the way down the window — the caret's paragraph, as the editor moves.
          window.glassineFollow = function(line, smooth) {
            var blocks = document.querySelectorAll('article > [data-line]');
            var target = null;
            for (var i = 0; i < blocks.length; i++) {
              var n = parseInt(blocks[i].getAttribute('data-line'), 10);
              if (n <= line) target = blocks[i]; else break;
            }
            if (!target) return;
            var top = target.getBoundingClientRect().top + window.scrollY - window.innerHeight * 0.3;
            var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
            window.scrollTo({ top: Math.max(0, top), behavior: (smooth && !still) ? 'smooth' : 'auto' });
          };
        })();
        """
        config.userContentController.addUserScript(WKUserScript(source: tasks, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        config.userContentController.add(context.coordinator, name: "glassineTask")
        context.coordinator.onToggleTask = onToggleTask
        let web = WKWebView(frame: .zero, configuration: config)
        context.coordinator.web = web
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        web.allowsBackForwardNavigationGestures = false
        web.allowsMagnification = true
        context.coordinator.pendingScrollFraction = initialScrollFraction
        context.coordinator.followLine = followLine
        context.coordinator.load(html, into: web, baseURL: baseURL)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.onToggleTask = onToggleTask
        c.web = web
        if let line = followLine, line != c.followLine {
            c.followLine = line
            if c.loaded { c.follow(smooth: true) }
        }
        guard c.lastHTML != html else { return }
        let bare = ReviewHTML.stripScale(html)
        if c.lastHTMLWithoutScale == bare {
            // Only the text scale changed: adjust in place, no reload.
            web.evaluateJavaScript("document.documentElement.style.setProperty('--scale', '\(scale)')", completionHandler: nil)
            c.lastHTML = html
        } else if ReviewHTML.stripTasks(c.lastHTMLWithoutScale) == ReviewHTML.stripTasks(bare) {
            // Only checkboxes changed (a click here, or an edit elsewhere): flip them in place.
            c.showTaskStates(ReviewHTML.taskStates(html))
            web.evaluateJavaScript("document.documentElement.style.setProperty('--scale', '\(scale)')", completionHandler: nil)
            c.lastHTML = html
            c.lastHTMLWithoutScale = bare
        } else if live, c.loaded, ReviewHTML.stripBody(c.lastHTMLWithoutScale) == ReviewHTML.stripBody(bare) {
            // The text changed and nothing else: the new body goes into the page
            // in place once typing pauses, and the page follows the caret.
            c.lastHTML = html
            c.lastHTMLWithoutScale = bare
            c.pendingBody = ReviewHTML.body(of: html)
            c.bodyDebouncer.call { [weak c] in c?.applyPendingBody() }
        } else {
            c.pendingScrollFraction = c.knownFraction
            c.load(html, into: web, baseURL: baseURL)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML = ""
        var lastHTMLWithoutScale = ""
        var pendingScrollFraction: Double?
        var knownFraction: Double = 0
        var onToggleTask: (Int, Bool) -> Bool = { _, _ in false }
        weak var web: WKWebView?
        /// Beside the editor: the line to keep in view, the body waiting to go
        /// in, and whether the page is there to take it.
        var followLine: Int?
        var pendingBody: String?
        var loaded = false
        let bodyDebouncer = Debouncer(delay: 0.12)

        func applyPendingBody() {
            guard let body = pendingBody, let web, loaded else { return }
            pendingBody = nil
            guard let data = try? JSONSerialization.data(withJSONObject: [body]),
                  let json = String(data: data, encoding: .utf8) else { return }
            web.evaluateJavaScript("if (window.glassineSetBody) glassineSetBody(\(json)[0])") { [weak self] _, _ in
                self?.follow(smooth: true)
            }
        }

        func follow(smooth: Bool) {
            guard let line = followLine, let web, loaded else { return }
            web.evaluateJavaScript("if (window.glassineFollow) glassineFollow(\(line), \(smooth))", completionHandler: nil)
        }

        func showTaskStates(_ states: [Bool]) {
            let list = states.map { $0 ? "true" : "false" }.joined(separator: ",")
            web?.evaluateJavaScript("if (window.glassineSetTasks) glassineSetTasks([\(list)])", completionHandler: nil)
        }

        func load(_ html: String, into web: WKWebView, baseURL: URL) {
            lastHTML = html
            lastHTMLWithoutScale = ReviewHTML.stripScale(html)
            loaded = false
            pendingBody = nil
            bodyDebouncer.cancel()
            // Dip out before a reload and back in once it has rendered: a style switch
            // reads as a crossfade instead of a blink.
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                web.animator().alphaValue = 0
            }
            web.loadHTMLString(html, baseURL: baseURL)
            ScreenshotMode.note("load: \(html.count) chars, base \(baseURL.path)")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ScreenshotMode.note("didFinish")
            loaded = true
            if followLine != nil {
                pendingScrollFraction = nil
                follow(smooth: false)
            } else if let f = pendingScrollFraction, f > 0 {
                pendingScrollFraction = nil
                let js = "window.scrollTo(0, \(f) * Math.max(0, document.documentElement.scrollHeight - window.innerHeight));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
            reveal(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { ScreenshotMode.note("didFail \(error)"); reveal(webView) }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { ScreenshotMode.note("didFailProvisional \(error)"); reveal(webView) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { ScreenshotMode.note("content process terminated") }

        private func reveal(_ webView: WKWebView) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                webView.animator().alphaValue = 1
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "glassineScroll", let f = message.body as? Double {
                knownFraction = f
            } else if message.name == "glassineTask", let body = message.body as? [String: Any],
                      let index = body["index"] as? Int, let checked = body["checked"] as? Bool {
                if !onToggleTask(index, checked) {
                    // The document did not follow: show what it actually says.
                    showTaskStates(ReviewHTML.taskStates(lastHTML))
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Open external links in the browser instead of navigating the review pane away.
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if url.scheme == "http" || url.scheme == "https" || url.scheme == "mailto" {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - HTML + CSS

enum ReviewHTML {
    private struct RenderKey: Equatable {
        let markdown: String, title: String, style: ReviewStyle, theme: Theme, scale: Double, centerHeadings: Bool
    }
    private static var lastRender: (key: RenderKey, html: String)?

    /// The page for a document. SwiftUI asks for this on every state change while Review
    /// is up, so the last result is kept; comparing the inputs is far cheaper than rendering.
    static func document(markdown: String, title: String, style: ReviewStyle, theme: Theme, scale: Double,
                         centerHeadings: Bool = true, forExport: Bool = false) -> String {
        if forExport { return build(markdown: markdown, title: title, style: style, theme: theme, scale: scale, centerHeadings: centerHeadings, export: true) }
        let key = RenderKey(markdown: markdown, title: title, style: style, theme: theme, scale: scale, centerHeadings: centerHeadings)
        if let last = lastRender, last.key == key { return last.html }
        let html = build(markdown: markdown, title: title, style: style, theme: theme, scale: scale, centerHeadings: centerHeadings)
        lastRender = (key, html)
        return html
    }

    private static func build(markdown: String, title: String, style: ReviewStyle, theme: Theme, scale: Double,
                              centerHeadings: Bool, export: Bool = false) -> String {
        let body = MarkdownHTML.render(markdown)
        // On paper the page needs a colour of its own (styles with their own background
        // override it), less room at the top, and no lingering edge fades.
        let exportCSS = export ? "body { background: \(theme.tint.hex); } article { padding: 1rem 0 2rem; max-width: none; }" : ""
        let vars = """
        :root { --scale: \(scale); --accent: \(theme.accent.hex); --text: \(theme.text.hex); --tint: \(theme.tint.hex); \
        --heading: \((theme.heading ?? theme.text).hex); --syntax: \(theme.syntax.hex); --link: \((theme.link ?? theme.accent).hex); }
        """
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(MarkdownHTML.escape(title))</title>
        <style>
        \(vars)
        \(baseCSS)
        \(exportCSS)
        \(centerHeadings ? "h1, h2, h3, h4, h5, h6 { text-align: center; }" : "")
        \(css(for: style, dark: theme.isDark))
        \(export && style != .notebook ? "article { padding-top: 1rem; }" : "")
        </style></head><body class="\(style.rawValue) \(theme.isDark ? "dark" : "light")"><article>\(body)</article></body></html>
        """
    }

    /// The document with the scale variable removed, to detect "only the scale changed".
    static func stripScale(_ html: String) -> String {
        guard let r = html.range(of: "--scale: "), let end = html[r.upperBound...].firstIndex(of: ";") else { return html }
        return html.replacingCharacters(in: r.lowerBound..<end, with: "--scale: X")
    }

    /// What is inside `<article>`: the rendered text, without the page around it.
    static func body(of html: String) -> String {
        guard let open = html.range(of: "<article>"), let close = html.range(of: "</article>", options: .backwards),
              open.upperBound <= close.lowerBound else { return "" }
        return String(html[open.upperBound..<close.lowerBound])
    }

    /// The page with its article emptied: equal for two renders that differ only
    /// in the text, so a page beside the editor can take the new text in place.
    static func stripBody(_ html: String) -> String {
        guard let open = html.range(of: "<article>"), let close = html.range(of: "</article>", options: .backwards),
              open.upperBound <= close.lowerBound else { return html }
        var page = String(html[..<open.upperBound]) + String(html[close.lowerBound...])
        // The title follows the first line as it is typed; it is not on the page.
        if let t = page.range(of: "<title>"), let end = page.range(of: "</title>", range: t.upperBound..<page.endIndex) {
            page.replaceSubrange(t.upperBound..<end.lowerBound, with: "")
        }
        return page
    }

    /// The same page with every task unchecked, to tell "a box was ticked" from a real edit.
    static func stripTasks(_ html: String) -> String {
        html.replacingOccurrences(of: "<input type=\"checkbox\" checked>", with: "<input type=\"checkbox\">")
            .replacingOccurrences(of: "class=\"task done\"", with: "class=\"task\"")
    }

    /// Checked state of each task checkbox in the page, top to bottom.
    static func taskStates(_ html: String) -> [Bool] {
        var states: [Bool] = []
        var search = html.startIndex
        while let r = html.range(of: "<input type=\"checkbox\"", range: search..<html.endIndex) {
            states.append(html[r.upperBound...].hasPrefix(" checked>"))
            search = r.upperBound
        }
        return states
    }

    static let baseCSS = """
    * { box-sizing: border-box; }
    html { font-size: calc(17px * var(--scale)); -webkit-text-size-adjust: 100%; }
    body { margin: 0; padding: 0; background: transparent; -webkit-font-smoothing: antialiased; }
    article { max-width: 42rem; margin: 0 auto; padding: 5.2rem 2rem 8rem; line-height: 1.6; }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.5em; font-weight: 700; }
    h1 { font-size: 2em; margin-top: 0.4em; } h2 { font-size: 1.5em; } h3 { font-size: 1.2em; } h4 { font-size: 1.05em; }
    h5, h6 { font-size: 1em; }
    p, ul, ol, blockquote, pre, table, hr { margin: 0 0 1em; }
    li { margin: 0.2em 0; } li > ul, li > ol { margin: 0.2em 0 0.2em; }
    ul, ol { padding-left: 1.5em; }
    li.task { list-style: none; margin-left: -1.5em; }
    li.task > ul, li.task > ol { margin-left: 1.5em; }
    li.task input { margin: 0 0.5em 0 0; vertical-align: -1px; cursor: pointer; accent-color: var(--accent); }
    li.task { transition: opacity 0.45s ease-out; }
    li.task.done { opacity: 0.6; }
    li.task.done:not(:has(.task-text)) { text-decoration: line-through; }
    li.task .task-text { background-image: linear-gradient(90deg, var(--accent), color-mix(in srgb, var(--accent) 30%, var(--syntax))); \
    background-repeat: no-repeat; background-size: 0% 1.5px; background-position: 0 57%; \
    transition: background-size 0.45s cubic-bezier(0.2, 0.7, 0.2, 1); \
    -webkit-box-decoration-break: clone; box-decoration-break: clone; }
    li.task.done .task-text { background-size: 100% 1.5px; }
    @media (prefers-reduced-motion: reduce) { li.task, li.task .task-text { transition: none; } }
    a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
    img { max-width: 100%; height: auto; border-radius: 6px; }
    code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.86em; padding: 0.12em 0.35em; border-radius: 4px; }
    pre { padding: 1em 1.1em; border-radius: 10px; overflow-x: auto; line-height: 1.5; }
    pre code { padding: 0; font-size: 0.82em; background: none; }
    blockquote { padding: 0.1em 0 0.1em 1.1em; border-left: 3px solid var(--accent); font-style: italic; \
    border-image: linear-gradient(180deg, var(--accent), color-mix(in srgb, var(--accent) 25%, transparent)) 1; }
    blockquote p:last-child { margin-bottom: 0; }
    hr { border: 0; height: 1px; margin: 2.2em auto; width: 40%; }
    table { border-collapse: collapse; width: 100%; font-size: 0.92em; }
    th, td { padding: 0.5em 0.8em; text-align: left; vertical-align: top; }
    th { font-weight: 600; }
    .tag { color: var(--accent); }
    .date, .chip { display: inline-block; color: var(--accent); border-radius: 999px; padding: 0 0.55em; font-size: 0.92em; line-height: 1.5; white-space: nowrap; \
    text-indent: 0; text-align: center; hyphens: manual; \
    background: linear-gradient(180deg, color-mix(in srgb, var(--accent) 24%, transparent), color-mix(in srgb, var(--accent) 12%, transparent)); \
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 18%, transparent); }
    ::selection { background: color-mix(in srgb, var(--accent) 35%, transparent); }
    """

    static func css(for style: ReviewStyle, dark: Bool) -> String {
        switch style {
        case .glass:
            return """
            body { color: var(--text); font-family: ui-serif, "New York", Charter, Georgia, serif; }
            h1, h2, h3, h4, h5, h6 { color: var(--heading); }
            code { background: color-mix(in srgb, var(--text) 10%, transparent); }
            pre { background: color-mix(in srgb, var(--text) 8%, transparent); }
            hr { background: linear-gradient(90deg, transparent, color-mix(in srgb, var(--text) 30%, transparent), transparent); }
            th, td { border-bottom: 1px solid color-mix(in srgb, var(--text) 14%, transparent); }
            blockquote { color: color-mix(in srgb, var(--text) 78%, transparent); }
            """
        case .github:
            let bg = dark ? "#0d1117" : "#ffffff"
            let text = dark ? "#e6edf3" : "#1f2328"
            let muted = dark ? "#8d96a0" : "#59636e"
            let border = dark ? "#3d444d" : "#d1d9e0"
            let code = dark ? "#151b23" : "#f6f8fa"
            let link = dark ? "#4493f8" : "#0969da"
            return """
            body { background: \(bg); color: \(text); font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif; }
            html { font-size: calc(16px * var(--scale)); }
            article { max-width: 52rem; line-height: 1.5; }
            h1, h2 { padding-bottom: 0.3em; border-bottom: 1px solid \(border); font-weight: 600; }
            h1 { font-size: 2em; } h2 { font-size: 1.5em; } h3 { font-size: 1.25em; font-weight: 600; }
            a { color: \(link); }
            code { background: \(code); font-size: 85%; padding: 0.2em 0.4em; border-radius: 6px; }
            pre { background: \(code); border-radius: 6px; }
            blockquote { color: \(muted); border-left: 0.25em solid \(border); border-image: none; font-style: normal; padding: 0 1em; }
            hr { height: 0.25em; width: 100%; background: \(border); margin: 1.5em 0; border-radius: 2px; }
            table { display: table; width: auto; }
            th, td { border: 1px solid \(border); padding: 6px 13px; }
            tr:nth-child(2n) { background: \(code); }
            .tag { color: \(link); }
            """
        case .book:
            return """
            body { background: transparent; color: #2b2118; font-family: "Iowan Old Style", "Palatino", ui-serif, "New York", Georgia, serif; }
            html { font-size: calc(18px * var(--scale)); }
            article { max-width: 38rem; background: #f6f0e4; margin: 3.4rem auto 4rem; padding: 4rem 3.6rem 4.5rem; border-radius: 9px; \
            box-shadow: 0 30px 60px rgba(0,0,0,0.35), 0 2px 8px rgba(0,0,0,0.2); line-height: 1.72; text-align: justify; hyphens: auto; }
            h1, h2, h3, h4 { text-align: center; font-weight: 500; letter-spacing: 0.02em; color: #1e160f; }
            h1 { font-size: 1.9em; margin: 0.2em 0 1.2em; font-variant: small-caps; letter-spacing: 0.08em; }
            h2 { font-size: 1.35em; margin-top: 2.2em; font-variant: small-caps; letter-spacing: 0.06em; }
            h3 { font-size: 1.1em; font-style: italic; }
            article > p:first-of-type::first-letter, h1 + p::first-letter { float: left; font-size: 3.6em; line-height: 0.85; padding: 0.08em 0.1em 0 0; color: #7a3b1e; }
            p { margin: 0 0 0 0; } p + p { text-indent: 1.5em; } p:has(+ h2), p:has(+ h3), p:has(+ hr) { margin-bottom: 1em; }
            ul, ol, blockquote, pre, table { margin: 1em 0; text-align: left; }
            blockquote { border: 0; font-style: italic; padding: 0 2em; color: #4a3b30; }
            hr { border: 0; background: none; height: auto; text-align: center; margin: 2em 0; }
            hr::after { content: "❧"; color: #7a3b1e; font-size: 1.3em; }
            a { color: #7a3b1e; border-bottom: 1px solid rgba(122,59,30,0.35); }
            code { background: rgba(0,0,0,0.06); font-size: 0.82em; } pre { background: rgba(0,0,0,0.05); }
            th, td { border-bottom: 1px solid rgba(43,33,24,0.2); }
            .tag { color: #7a3b1e; }
            """
        case .bookDark:
            // The same page after dark: warm charcoal paper, cream type, and a
            // terracotta for the drop cap and the ornaments.
            return """
            body { --accent: #d97757; background: transparent; color: #e7dfd0; font-family: "Iowan Old Style", "Palatino", ui-serif, "New York", Georgia, serif; }
            html { font-size: calc(18px * var(--scale)); }
            article { max-width: 38rem; background: #2a2622; margin: 3.4rem auto 4rem; padding: 4rem 3.6rem 4.5rem; border-radius: 9px; \
            box-shadow: 0 30px 60px rgba(0,0,0,0.55), 0 0 0 1px rgba(255,255,255,0.04); line-height: 1.72; text-align: justify; hyphens: auto; }
            h1, h2, h3, h4 { text-align: center; font-weight: 500; letter-spacing: 0.02em; color: #f3ecdc; }
            h1 { font-size: 1.9em; margin: 0.2em 0 1.2em; font-variant: small-caps; letter-spacing: 0.08em; }
            h2 { font-size: 1.35em; margin-top: 2.2em; font-variant: small-caps; letter-spacing: 0.06em; }
            h3 { font-size: 1.1em; font-style: italic; }
            article > p:first-of-type::first-letter, h1 + p::first-letter { float: left; font-size: 3.6em; line-height: 0.85; padding: 0.08em 0.1em 0 0; color: #d97757; }
            p { margin: 0 0 0 0; } p + p { text-indent: 1.5em; } p:has(+ h2), p:has(+ h3), p:has(+ hr) { margin-bottom: 1em; }
            ul, ol, blockquote, pre, table { margin: 1em 0; text-align: left; }
            blockquote { border: 0; font-style: italic; padding: 0 2em; color: #b9af9e; }
            hr { border: 0; background: none; height: auto; text-align: center; margin: 2em 0; }
            hr::after { content: "❧"; color: #d97757; font-size: 1.3em; }
            a { color: #e39271; border-bottom: 1px solid rgba(227,146,113,0.35); }
            code { background: rgba(255,255,255,0.07); font-size: 0.82em; color: #ede6d8; } pre { background: rgba(0,0,0,0.28); }
            th, td { border-bottom: 1px solid rgba(231,223,208,0.2); }
            .tag { color: #d97757; }
            """
        case .editorial:
            let bg = dark ? "#141416" : "#fafaf8"
            let text = dark ? "#e8e6e2" : "#1a1a1a"
            let muted = dark ? "#9a9891" : "#6b6b66"
            let rule = dark ? "#2c2c30" : "#e3e1dc"
            return """
            body { background: \(bg); color: \(text); font-family: "Helvetica Neue", ui-sans-serif, -apple-system, sans-serif; }
            html { font-size: calc(17px * var(--scale)); }
            article { max-width: 44rem; line-height: 1.65; padding-top: 6rem; }
            h1, h2, h3 { font-family: ui-sans-serif, -apple-system, "Helvetica Neue", sans-serif; letter-spacing: -0.03em; }
            h1 { font-size: 3.1em; line-height: 1.02; font-weight: 800; margin: 0 0 0.35em; }
            h1::after { content: ""; display: block; width: 3.2rem; height: 4px; background: var(--accent); margin-top: 0.5em; border-radius: 2px; }
            h2 { font-size: 1.7em; font-weight: 700; margin-top: 2em; }
            h3 { font-size: 1.15em; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; color: var(--accent); }
            p { font-size: 1.05em; }
            blockquote { border: 0; padding: 0.4em 0 0.4em 0; margin: 1.6em 0; font-size: 1.45em; line-height: 1.3; font-weight: 300; \
            letter-spacing: -0.01em; font-style: normal; color: \(text); border-top: 1px solid \(rule); border-bottom: 1px solid \(rule); }
            blockquote p::before { content: "“"; color: var(--accent); margin-right: 0.1em; }
            hr { width: 100%; background: \(rule); }
            code { background: color-mix(in srgb, \(text) 8%, transparent); } pre { background: color-mix(in srgb, \(text) 6%, transparent); }
            th { text-transform: uppercase; font-size: 0.8em; letter-spacing: 0.06em; color: \(muted); }
            th, td { border-bottom: 1px solid \(rule); }
            a { color: var(--accent); }
            """
        case .reader:
            // A quiet page, the way a reading app sets one: a serif, a narrow
            // measure, air between the lines, and nothing else on the page.
            let bg = dark ? "#1b1a18" : "#fbfaf6"
            let text = dark ? "#d8d3c8" : "#2d2a25"
            let muted = dark ? "#8f8a80" : "#77716a"
            return """
            body { background: \(bg); color: \(text); font-family: Charter, "Iowan Old Style", Georgia, serif; }
            html { font-size: calc(19px * var(--scale)); }
            article { max-width: 36rem; line-height: 1.75; padding-top: 5rem; }
            h1, h2, h3, h4 { font-weight: 600; letter-spacing: -0.01em; color: \(text); }
            h1 { font-size: 1.85em; line-height: 1.15; margin-bottom: 0.8em; }
            h2 { font-size: 1.3em; margin-top: 2em; } h3 { font-size: 1.05em; }
            p { margin-bottom: 1.25em; }
            a { color: \(text); text-decoration: underline; text-decoration-color: var(--accent); text-underline-offset: 0.15em; }
            blockquote { color: \(muted); border-left: 2px solid var(--accent); border-image: none; padding-left: 1.4em; }
            hr { width: 100%; background: none; height: auto; margin: 2.4em 0; text-align: center; }
            hr::after { content: "· · ·"; color: \(muted); letter-spacing: 0.4em; }
            code { background: color-mix(in srgb, \(text) 8%, transparent); } pre { background: color-mix(in srgb, \(text) 6%, transparent); }
            th, td { border-bottom: 1px solid color-mix(in srgb, \(text) 16%, transparent); }
            """
        case .gallery:
            // Wall text: small sans type, headings as spaced capitals, and
            // white space as most of the page.
            let bg = dark ? "#111111" : "#ffffff"
            let text = dark ? "#e4e4e4" : "#1b1b1b"
            let muted = dark ? "#8a8a8a" : "#8c8c8c"
            return """
            body { background: \(bg); color: \(text); font-family: "Avenir Next", "Helvetica Neue", ui-sans-serif, sans-serif; }
            html { font-size: calc(15px * var(--scale)); }
            article { max-width: 30rem; line-height: 1.8; padding-top: 9rem; padding-bottom: 12rem; }
            h1, h2, h3, h4 { font-weight: 500; text-transform: uppercase; letter-spacing: 0.18em; }
            h1 { font-size: 0.95em; margin: 0 0 4em; color: \(text); }
            h1::after { content: ""; display: block; width: 1.6rem; height: 1px; background: \(text); margin: 2.2em 0 0; }
            h2 { font-size: 0.8em; margin: 3.5em 0 1.2em; color: \(muted); }
            h3, h4 { font-size: 0.75em; margin: 2.5em 0 1em; color: \(muted); letter-spacing: 0.14em; }
            p { margin-bottom: 1.6em; }
            strong { font-weight: 600; }
            blockquote { border: 0; border-image: none; padding: 0; margin: 2.4em 0; font-style: normal; color: \(muted); }
            hr { width: 1.6rem; margin: 3.5em auto; background: \(text); }
            a { color: \(text); text-decoration: underline; text-underline-offset: 0.2em; text-decoration-color: \(muted); }
            code { background: color-mix(in srgb, \(text) 6%, transparent); } pre { background: color-mix(in srgb, \(text) 5%, transparent); }
            th { font-weight: 500; text-transform: uppercase; letter-spacing: 0.1em; font-size: 0.75em; color: \(muted); }
            th, td { border-bottom: 1px solid color-mix(in srgb, \(text) 12%, transparent); }
            """
        case .newspaper:
            // A broadsheet: the headline across the page, the text in two
            // justified columns of small Times with a rule between them, a
            // drop cap on the first paragraph. One column when the page is narrow.
            let bg = dark ? "#1c1b18" : "#f2ede3"
            let text = dark ? "#e3dccd" : "#1a1815"
            let rule = dark ? "rgba(227,220,205,0.4)" : "rgba(26,24,21,0.45)"
            return """
            body { background: \(bg); color: \(text); font-family: "Times New Roman", Times, "Iowan Old Style", serif; }
            html { font-size: calc(15.5px * var(--scale)); }
            article { max-width: 58rem; padding-top: 4rem; line-height: 1.42; text-align: justify; hyphens: auto; \
            columns: 2; column-gap: 2.4rem; column-rule: 1px solid \(rule); }
            @media (max-width: 46rem) { article { columns: 1; } }
            h1 { column-span: all; font-family: "Bodoni 72", "Didot", "Times New Roman", serif; font-size: 3.2em; line-height: 1.05; font-weight: 700; \
            text-align: center; letter-spacing: -0.01em; margin: 0 0 0.5em; padding: 0.25em 0 0.35em; border-top: 3px double \(rule); border-bottom: 1px solid \(rule); }
            h2 { font-size: 1.3em; font-weight: 700; line-height: 1.2; margin: 1.2em 0 0.4em; break-after: avoid; }
            h3, h4 { font-size: 1em; font-weight: 700; font-variant: small-caps; letter-spacing: 0.06em; margin: 1em 0 0.3em; break-after: avoid; }
            p { margin: 0; } p + p { text-indent: 1.3em; }
            p:has(+ h2), p:has(+ h3), p:has(+ hr), p:has(+ ul), p:has(+ ol), p:has(+ blockquote), p:has(+ pre), p:has(+ table) { margin-bottom: 0.8em; }
            article > h1 + p::first-letter { float: left; font-size: 3.4em; line-height: 0.8; padding: 0.06em 0.08em 0 0; font-weight: 700; }
            ul, ol, blockquote, pre, table, img { margin: 0.8em 0; text-align: left; break-inside: avoid; }
            blockquote { border: 0; border-image: none; border-top: 1px solid \(rule); border-bottom: 1px solid \(rule); padding: 0.5em 0; \
            font-size: 1.15em; line-height: 1.3; font-style: italic; text-align: center; }
            hr { width: 100%; height: 1px; background: \(rule); margin: 1.2em 0; }
            a { color: \(text); text-decoration: underline; }
            code { background: color-mix(in srgb, \(text) 8%, transparent); font-size: 0.8em; } pre { background: color-mix(in srgb, \(text) 6%, transparent); font-size: 0.9em; }
            th, td { border-bottom: 1px solid \(rule); padding: 0.3em 0.5em; font-size: 0.9em; }
            img { border-radius: 0; }
            """
        case .typewriter:
            // A manuscript: Courier struck on cream paper, double spaced,
            // paragraphs indented, headings in underlined capitals, emphasis
            // underlined the way a typewriter had to.
            return """
            body { background: transparent; color: #2c2a26; font-family: "Courier Prime", "Courier New", Courier, monospace; }
            html { font-size: calc(15px * var(--scale)); }
            article { max-width: 42rem; background: #f8f4e9; margin: 3.4rem auto 4rem; padding: 4rem 3.4rem 4.5rem; border-radius: 3px; \
            box-shadow: 0 30px 60px rgba(0,0,0,0.35), 0 2px 8px rgba(0,0,0,0.2); line-height: 2; text-align: left; hyphens: none; \
            text-shadow: 0 0 0.6px rgba(44,42,38,0.5); }
            h1, h2, h3, h4 { font-family: inherit; font-weight: 700; font-size: 1em; text-transform: uppercase; letter-spacing: 0.1em; line-height: 2; color: inherit; }
            h1 { text-align: center; margin: 0 0 2em; text-decoration: underline; text-underline-offset: 0.25em; }
            h2 { margin: 2em 0 0; text-decoration: underline; text-underline-offset: 0.25em; }
            h3, h4 { margin: 2em 0 0; text-transform: none; letter-spacing: 0; }
            p { margin: 0; text-indent: 5ch; }
            ul, ol, blockquote, pre, table { margin: 1em 0; }
            ul { list-style: none; padding-left: 5ch; } ul li::before { content: "-"; margin-left: -2ch; margin-right: 1ch; } li.task::before { content: none; }
            blockquote { border: 0; border-image: none; padding: 0 5ch; font-style: normal; color: inherit; }
            em { font-style: normal; text-decoration: underline; text-underline-offset: 0.2em; }
            hr { width: 100%; background: none; height: auto; margin: 1em 0; text-align: center; } hr::after { content: "* * *"; letter-spacing: 0.5em; }
            code { background: none; padding: 0; font-family: inherit; font-size: 1em; }
            pre { background: none; border: 1px dashed rgba(44,42,38,0.35); border-radius: 0; font-family: inherit; }
            a { color: inherit; text-decoration: underline; }
            th, td { border-bottom: 1px solid rgba(44,42,38,0.35); }
            .tag { color: inherit; text-decoration: underline; }
            """
        case .notebook:
            // Ruled paper: blue lines a line apart, a red margin, blue-black
            // ink. Everything keeps to the ruling — one line height for every
            // block, margins in whole lines — so the writing sits on the lines.
            return """
            body { background: transparent; color: #1e2a63; font-family: "Baskerville", "Hoefler Text", "Iowan Old Style", Georgia, serif; }
            html { font-size: calc(17px * var(--scale)); }
            article { --lh: 1.85rem; --accent: #b23a3a; max-width: 42rem; margin: 3.4rem auto 4rem; padding: calc(var(--lh) * 2) 2.4rem calc(var(--lh) * 3) 4.6rem; \
            border-radius: 4px; line-height: var(--lh); background-color: #fdfcf5; \
            background-image: linear-gradient(90deg, transparent 3.6rem, #f2a9a9 3.6rem, #f2a9a9 calc(3.6rem + 1.5px), transparent calc(3.6rem + 1.5px)), \
            repeating-linear-gradient(180deg, transparent 0, transparent calc(var(--lh) - 1px), #cfe0f1 calc(var(--lh) - 1px), #cfe0f1 var(--lh)); \
            background-attachment: local; box-shadow: 0 30px 60px rgba(0,0,0,0.3), 0 2px 8px rgba(0,0,0,0.15); }
            h1, h2, h3, h4, p, li, blockquote, pre, pre code, table, th, td { line-height: var(--lh); }
            h1, h2, h3, h4 { font-weight: 600; color: #15205a; margin: var(--lh) 0 0; }
            h1 { font-size: 1.7em; line-height: calc(var(--lh) * 2); margin-top: 0; }
            h2 { font-size: 1.25em; } h3, h4 { font-size: 1.05em; font-style: italic; }
            p, ul, ol, blockquote, pre, table { margin: 0 0 var(--lh); }
            li { margin: 0; } li > ul, li > ol { margin: 0; }
            blockquote { border: 0; border-left: 2px solid #f2a9a9; border-image: none; padding: 0 0 0 1em; font-style: italic; color: #3a4478; }
            hr { width: 40%; height: var(--lh); margin: 0 auto var(--lh); \
            background: linear-gradient(180deg, transparent calc(50% - 1px), rgba(30,42,99,0.6) calc(50% - 1px), rgba(30,42,99,0.6) calc(50% + 1px), transparent calc(50% + 1px)); }
            code { background: rgba(30,42,99,0.08); font-size: 0.85em; }
            pre { background: rgba(30,42,99,0.05); padding: 0 0.8em; border-radius: 0; }
            a { color: #1e2a63; text-decoration: underline; text-decoration-color: #f2a9a9; }
            table { margin-bottom: var(--lh); } th, td { border-bottom: 1px solid rgba(30,42,99,0.25); padding: 0 0.6em; }
            img { display: block; margin: 0 0 var(--lh); }
            .tag { color: #b23a3a; }
            """
        case .thesis:
            // A dissertation: Times, double spaced, numbered sections, the
            // first line of every paragraph indented, quotations set in a
            // single-spaced block.
            let bg = dark ? "#151515" : "#ffffff"
            let text = dark ? "#d6d6d6" : "#111111"
            return """
            body { background: \(bg); color: \(text); font-family: "Times New Roman", Times, serif; }
            html { font-size: calc(17px * var(--scale)); }
            article { max-width: 40rem; line-height: 2; padding-top: 6rem; counter-reset: sec; }
            h1, h2, h3, h4 { font-weight: 700; font-size: 1em; line-height: 2; color: \(text); }
            h1 { font-size: 1.25em; text-align: center; text-transform: uppercase; letter-spacing: 0.04em; margin: 0 0 2em; }
            h2 { margin: 2em 0 0; counter-increment: sec; counter-reset: sub; }
            h2::before { content: counter(sec) ".  "; }
            h3 { font-style: italic; margin: 1.5em 0 0; counter-increment: sub; }
            h3::before { content: counter(sec) "." counter(sub) "  "; font-style: normal; }
            p { margin: 0; text-indent: 2.5em; }
            h1 + p, h2 + p, h3 + p, h4 + p, hr + p, blockquote + p, ul + p, ol + p, pre + p, table + p { text-indent: 0; }
            blockquote { border: 0; border-image: none; font-style: normal; margin: 1em 2.5em; padding: 0; line-height: 1.35; font-size: 0.95em; color: \(text); }
            blockquote p { text-indent: 0; }
            ul, ol { margin: 0.5em 0; } li { margin: 0; }
            hr { width: 100%; height: 1px; background: color-mix(in srgb, \(text) 40%, transparent); margin: 1.5em 0; }
            pre { line-height: 1.4; background: color-mix(in srgb, \(text) 6%, transparent); font-size: 0.95em; border-radius: 0; margin: 1em 0; }
            code { background: color-mix(in srgb, \(text) 8%, transparent); font-family: "Courier New", Courier, monospace; }
            a { color: \(text); text-decoration: underline; }
            table { line-height: 1.4; margin: 1em 0; } th, td { border-top: 1px solid \(text); border-bottom: 1px solid \(text); padding: 0.3em 0.6em; }
            """
        case .verse:
            // For poems: centred, airy, an old-style serif, every line its
            // own line, and a blank line in the source a stanza's space.
            let bg = dark ? "#16151a" : "#faf7f1"
            let text = dark ? "#e4dfd6" : "#2a2622"
            let muted = dark ? "#8d877e" : "#8a837a"
            return """
            body { background: \(bg); color: \(text); font-family: "Cochin", "Hoefler Text", "Baskerville", Georgia, serif; }
            html { font-size: calc(19px * var(--scale)); }
            article { max-width: 34rem; line-height: 1.7; padding-top: 7rem; padding-bottom: 10rem; text-align: center; }
            h1, h2, h3, h4 { font-weight: 400; text-align: center; color: \(text); }
            h1 { font-size: 1.6em; letter-spacing: 0.06em; font-variant: small-caps; margin: 0 0 2.2em; }
            h2 { font-size: 1.15em; font-style: italic; margin: 2.6em 0 1.2em; }
            h3, h4 { font-size: 0.95em; letter-spacing: 0.14em; text-transform: uppercase; color: \(muted); margin: 2.2em 0 1em; }
            p { margin: 0; }
            p[data-gap], ul[data-gap], ol[data-gap], blockquote[data-gap], pre[data-gap], hr[data-gap], table[data-gap] { margin-top: 1.7em; }
            strong { font-weight: 600; }
            ul, ol { list-style: none; padding: 0; margin: 0; } li { margin: 0; } li.task { margin-left: 0; }
            blockquote { border: 0; border-image: none; padding: 0; margin: 0; font-style: italic; color: \(muted); }
            hr { width: 100%; background: none; height: auto; margin: 1.7em 0; } hr::after { content: "❦"; color: \(muted); font-size: 1.1em; }
            a { color: \(text); text-decoration: underline; text-decoration-color: \(muted); }
            code { background: color-mix(in srgb, \(text) 8%, transparent); } pre { background: color-mix(in srgb, \(text) 6%, transparent); text-align: left; margin: 1.7em 0; }
            table { text-align: left; margin: 1.7em 0; } th, td { border-bottom: 1px solid color-mix(in srgb, \(text) 15%, transparent); }
            """
        case .blueprint:
            // A drawing sheet: white line type on blueprint blue, a fine grid
            // behind it, a double-ruled border, headings as spaced capitals.
            return """
            body { --accent: #ffd97a; --link: #ffffff; background: #1a3f7a; color: #eaf2ff; font-family: "Avenir Next", "Futura", ui-sans-serif, sans-serif; \
            background-image: linear-gradient(rgba(255,255,255,0.07) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.07) 1px, transparent 1px), \
            linear-gradient(rgba(255,255,255,0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px); \
            background-size: 8rem 8rem, 8rem 8rem, 1rem 1rem, 1rem 1rem; }
            html { font-size: calc(15.5px * var(--scale)); }
            article { max-width: 44rem; line-height: 1.7; padding: 3.2rem 2.6rem 4rem; margin: 3rem auto 4rem; background: rgba(18,52,108,0.6); \
            border: 1px solid rgba(255,255,255,0.5); outline: 1px solid rgba(255,255,255,0.5); outline-offset: 5px; }
            h1, h2, h3, h4 { font-weight: 500; text-transform: uppercase; letter-spacing: 0.16em; color: #ffffff; }
            h1 { font-size: 1.5em; margin: 0 0 1.2em; padding-bottom: 0.5em; border-bottom: 1px solid rgba(255,255,255,0.6); }
            h2 { font-size: 1.05em; margin-top: 2.2em; } h2::before { content: "▸ "; opacity: 0.7; }
            h3, h4 { font-size: 0.9em; letter-spacing: 0.12em; color: #cfe0ff; }
            p { margin-bottom: 1.1em; }
            strong { color: #fff; font-weight: 600; } em { color: #cfe0ff; }
            a { color: #ffffff; text-decoration: underline; text-decoration-style: dotted; }
            blockquote { border: 1px dashed rgba(255,255,255,0.5); border-image: none; padding: 0.7em 1em; font-style: normal; color: #eaf2ff; }
            hr { width: 100%; height: 1px; background: rgba(255,255,255,0.5); margin: 2em 0; }
            code { background: rgba(255,255,255,0.12); color: #fff; } pre { background: rgba(0,0,0,0.25); border: 1px solid rgba(255,255,255,0.3); border-radius: 2px; }
            table { display: table; } th, td { border: 1px solid rgba(255,255,255,0.4); padding: 0.4em 0.7em; }
            th { text-transform: uppercase; letter-spacing: 0.1em; font-size: 0.8em; font-weight: 500; }
            img { border-radius: 0; border: 1px solid rgba(255,255,255,0.4); }
            .tag { color: #ffd97a; }
            """
        case .mono:
            let bg = dark ? "#0b0c0f" : "#f4f4f2"
            let text = dark ? "#d5d7d0" : "#22241f"
            let dim = dark ? "#6f7370" : "#8a8d86"
            return """
            body { background: \(bg); color: \(text); font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
            html { font-size: calc(14.5px * var(--scale)); }
            article { max-width: 78ch; line-height: 1.7; }
            h1, h2, h3, h4 { font-weight: 700; color: var(--accent); }
            h1 { font-size: 1.6em; text-transform: uppercase; letter-spacing: 0.06em; }
            h1::before { content: "# "; color: \(dim); } h2::before { content: "## "; color: \(dim); } h3::before { content: "### "; color: \(dim); }
            h2 { font-size: 1.25em; } h3 { font-size: 1.05em; }
            ul { list-style: none; padding-left: 1.4em; } ul li::before { content: "–"; color: var(--accent); margin-left: -1.4em; margin-right: 0.8em; }
            li.task::before { content: none; }
            blockquote { border-left: 2px solid \(dim); border-image: none; font-style: normal; color: \(dim); }
            code { background: color-mix(in srgb, \(text) 10%, transparent); } pre { background: color-mix(in srgb, \(text) 7%, transparent); border: 1px solid color-mix(in srgb, \(text) 14%, transparent); }
            hr { width: 100%; background: none; height: auto; }
            hr::after { content: "────────────────────────"; color: \(dim); display: block; text-align: center; }
            th, td { border-bottom: 1px solid color-mix(in srgb, \(text) 18%, transparent); }
            strong { color: var(--accent); } em { color: \(dim); }
            a { color: var(--accent); text-decoration: underline; }
            """
        }
    }
}

import AppKit
import SwiftUI
import WebKit

enum ReviewStyle: String, Codable, CaseIterable, Identifiable {
    case glass, github, book, editorial, mono
    var id: String { rawValue }
    var label: String {
        switch self {
        case .glass: return "Glass"
        case .github: return "GitHub"
        case .book: return "Book"
        case .editorial: return "Editorial"
        case .mono: return "Mono"
        }
    }
}

/// Review mode: the document rendered as real HTML in a web view, in one of a
/// few typographic styles. Read-only; Esc or ⌘↩ goes back to the editor.
struct ReviewView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var document: DocumentModel
    let initialScrollFraction: Double

    private var theme: Theme { state.theme }
    private var style: ReviewStyle { state.settings.data.reviewStyle }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ReviewWebView(
                html: ReviewHTML.document(markdown: document.text, title: document.title, style: style,
                                          theme: theme, scale: state.settings.data.reviewFontScale),
                scale: state.settings.data.reviewFontScale,
                initialScrollFraction: initialScrollFraction,
                baseURL: document.url.deletingLastPathComponent(),
                onToggleTask: { index, checked in document.setTask(ordinal: index, checked: checked) }
            )
            .ignoresSafeArea()

            controls
                .padding(.top, 10)
                .padding(.trailing, 14)
        }
        .background(
            Button("") { state.reviewMode = false }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
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
                state.reviewMode = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Back to editing (Esc or ⌘↩)")
        }
        .foregroundStyle(styleIsLight ? Color.black.opacity(0.75) : Color.white.opacity(0.85))
        .padding(.leading, 4)
        .background(Capsule().fill(styleIsLight ? Color.black.opacity(0.07) : Color.white.opacity(0.12)))
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(styleIsLight ? Color.black.opacity(0.08) : Color.white.opacity(0.12)))
    }

    /// Whether the rendered page behind the controls is light, so the pill stays legible.
    private var styleIsLight: Bool {
        style == .book || !theme.isDark
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
          boxes().forEach(function(box, i) {
            box.addEventListener('change', function() {
              paint(box, box.checked);
              window.webkit.messageHandlers.glassineTask.postMessage({ index: i, checked: box.checked });
            });
          });
          window.glassineSetTasks = function(states) {
            boxes().forEach(function(box, i) {
              if (i < states.length) { box.checked = states[i]; paint(box, states[i]); }
            });
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
        context.coordinator.load(html, into: web, baseURL: baseURL)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.onToggleTask = onToggleTask
        c.web = web
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

        func showTaskStates(_ states: [Bool]) {
            let list = states.map { $0 ? "true" : "false" }.joined(separator: ",")
            web?.evaluateJavaScript("if (window.glassineSetTasks) glassineSetTasks([\(list)])", completionHandler: nil)
        }

        func load(_ html: String, into web: WKWebView, baseURL: URL) {
            lastHTML = html
            lastHTMLWithoutScale = ReviewHTML.stripScale(html)
            web.loadHTMLString(html, baseURL: baseURL)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let f = pendingScrollFraction, f > 0 {
                pendingScrollFraction = nil
                let js = "window.scrollTo(0, \(f) * Math.max(0, document.documentElement.scrollHeight - window.innerHeight));"
                webView.evaluateJavaScript(js, completionHandler: nil)
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
    static func document(markdown: String, title: String, style: ReviewStyle, theme: Theme, scale: Double) -> String {
        let body = MarkdownHTML.render(markdown)
        let vars = """
        :root { --scale: \(scale); --accent: \(theme.accent.hex); --text: \(theme.text.hex); --tint: \(theme.tint.hex); \
        --heading: \((theme.heading ?? theme.text).hex); --syntax: \(theme.syntax.hex); --link: \((theme.link ?? theme.accent).hex); }
        """
        return """
        <!doctype html><html><head><meta charset="utf-8"><title>\(MarkdownHTML.escape(title))</title>
        <style>
        \(vars)
        \(baseCSS)
        \(css(for: style, dark: theme.isDark))
        </style></head><body class="\(style.rawValue) \(theme.isDark ? "dark" : "light")"><article>\(body)</article></body></html>
        """
    }

    /// The document with the scale variable removed, to detect "only the scale changed".
    static func stripScale(_ html: String) -> String {
        guard let r = html.range(of: "--scale: "), let end = html[r.upperBound...].firstIndex(of: ";") else { return html }
        return html.replacingCharacters(in: r.lowerBound..<end, with: "--scale: X")
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
    li.task input { margin: 0 0.5em 0 0; vertical-align: -1px; cursor: pointer; accent-color: var(--accent); }
    li.task.done { opacity: 0.6; text-decoration: line-through; }
    a { color: var(--link); text-decoration: none; } a:hover { text-decoration: underline; }
    img { max-width: 100%; height: auto; border-radius: 6px; }
    code { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 0.86em; padding: 0.12em 0.35em; border-radius: 4px; }
    pre { padding: 1em 1.1em; border-radius: 10px; overflow-x: auto; line-height: 1.5; }
    pre code { padding: 0; font-size: 0.82em; background: none; }
    blockquote { padding: 0.1em 0 0.1em 1.1em; border-left: 3px solid var(--accent); font-style: italic; }
    blockquote p:last-child { margin-bottom: 0; }
    hr { border: 0; height: 1px; margin: 2.2em auto; width: 40%; }
    table { border-collapse: collapse; width: 100%; font-size: 0.92em; }
    th, td { padding: 0.5em 0.8em; text-align: left; vertical-align: top; }
    th { font-weight: 600; }
    .tag { color: var(--accent); }
    .date { display: inline-block; background: color-mix(in srgb, var(--accent) 16%, transparent); color: var(--accent); \
    border-radius: 999px; padding: 0 0.55em; font-size: 0.92em; line-height: 1.5; white-space: nowrap; }
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
            hr { background: color-mix(in srgb, var(--text) 22%, transparent); }
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
            blockquote { color: \(muted); border-left: 0.25em solid \(border); font-style: normal; padding: 0 1em; }
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
            article { max-width: 38rem; background: #f6f0e4; margin: 3.4rem auto 4rem; padding: 4rem 3.6rem 4.5rem; border-radius: 4px; \
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
            article > h1 + p { font-size: 1.28em; line-height: 1.5; color: \(muted); font-weight: 300; }
            blockquote { border: 0; padding: 0.4em 0 0.4em 0; margin: 1.6em 0; font-size: 1.45em; line-height: 1.3; font-weight: 300; \
            letter-spacing: -0.01em; font-style: normal; color: \(text); border-top: 1px solid \(rule); border-bottom: 1px solid \(rule); }
            blockquote p::before { content: "“"; color: var(--accent); margin-right: 0.1em; }
            hr { width: 100%; background: \(rule); }
            code { background: color-mix(in srgb, \(text) 8%, transparent); } pre { background: color-mix(in srgb, \(text) 6%, transparent); }
            th { text-transform: uppercase; font-size: 0.8em; letter-spacing: 0.06em; color: \(muted); }
            th, td { border-bottom: 1px solid \(rule); }
            a { color: var(--accent); }
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
            blockquote { border-left: 2px solid \(dim); font-style: normal; color: \(dim); }
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

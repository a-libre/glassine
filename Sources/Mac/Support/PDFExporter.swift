import AppKit
import WebKit

/// Renders a Review page to a paginated PDF through WebKit's print path.
/// The web view lives in a window that is never shown; the print operation is
/// run modally against the main window with every panel turned off.
final class PDFExporter: NSObject, WKNavigationDelegate {
    private static var active: [PDFExporter] = []

    private let web: WKWebView
    private let holder: NSWindow
    private let target: URL
    private let completion: (Error?) -> Void
    private var finished = false

    static func export(html: String, baseURL: URL, to url: URL, completion: @escaping (Error?) -> Void) {
        let exporter = PDFExporter(html: html, baseURL: baseURL, target: url, completion: completion)
        active.append(exporter)
    }

    private init(html: String, baseURL: URL, target: URL, completion: @escaping (Error?) -> Void) {
        self.target = target
        self.completion = completion
        // US Letter at 96 dpi; the print info's own paper size decides the pages.
        let frame = NSRect(x: 0, y: 0, width: 816, height: 1056)
        holder = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        holder.isReleasedWhenClosed = false
        web = WKWebView(frame: frame)
        holder.contentView?.addSubview(web)
        super.init()
        web.navigationDelegate = self
        web.loadHTMLString(html, baseURL: baseURL)
        // Nothing should hang forever if WebKit never reports back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.finish(NSError(domain: "Glassine", code: 1, userInfo: [NSLocalizedDescriptionKey: "The page took too long to render."]))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Give fonts and images a moment to settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.print() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }

    private func print() {
        let info = NSPrintInfo(dictionary: NSPrintInfo.shared.dictionary() as! [NSPrintInfo.AttributeKey: Any])
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = target
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 40
        info.bottomMargin = 40
        info.leftMargin = 44
        info.rightMargin = 44

        let op = web.printOperation(with: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.jobTitle = target.deletingPathExtension().lastPathComponent
        // WebKit's printing view needs a frame or it renders nothing.
        op.view?.frame = NSRect(origin: .zero, size: info.paperSize)
        let parent = NSApp.mainWindow ?? holder
        op.runModal(for: parent, delegate: self, didRun: #selector(printDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc private func printDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        finish(success ? nil : NSError(domain: "Glassine", code: 2, userInfo: [NSLocalizedDescriptionKey: "The PDF could not be written."]))
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        completion(error)
        web.navigationDelegate = nil
        holder.close()
        PDFExporter.active.removeAll { $0 === self }
    }
}

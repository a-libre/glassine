import UIKit
import WebKit

/// Renders a Review page to a paginated PDF. The Mac goes through WebKit's
/// print operation; iOS has the same pages by another door: the web view's
/// print formatter, laid out by a page renderer onto a PDF context.
final class PDFExporter: NSObject, WKNavigationDelegate {
    private static var active: [PDFExporter] = []

    private let web: WKWebView
    private let target: URL
    private let completion: (Error?) -> Void
    private var finished = false

    // US Letter in points, with the margins the Mac's export uses.
    private static let paper = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margins = UIEdgeInsets(top: 40, left: 44, bottom: 40, right: 44)

    static func export(html: String, baseURL: URL, to url: URL, completion: @escaping (Error?) -> Void) {
        let exporter = PDFExporter(html: html, baseURL: baseURL, target: url, completion: completion)
        active.append(exporter)
    }

    private init(html: String, baseURL: URL, target: URL, completion: @escaping (Error?) -> Void) {
        self.target = target
        self.completion = completion
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 816, height: 1056))
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.write() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish(error) }

    private func write() {
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(web.viewPrintFormatter(), startingAtPageAt: 0)
        let paper = PDFExporter.paper
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper.inset(by: PDFExporter.margins), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        do {
            try (data as Data).write(to: target, options: .atomic)
            finish(nil)
        } catch {
            finish(error)
        }
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        completion(error)
        web.navigationDelegate = nil
        PDFExporter.active.removeAll { $0 === self }
    }
}

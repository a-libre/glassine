import AppKit
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

// Pictures on the page. The file stays plain Markdown: a pasted or dropped
// image is written as a file of its own into an `Images` folder at the top of
// the library, and the document gets an ordinary `![](../Images/name.png)`
// line, which any other Markdown app reads. The editor draws the picture in
// place of that line (GlassineLayoutManager), scaled to the column; Review,
// the PDF and a rich-text copy carry the picture inside the page.

enum ImageEmbed {
    /// The folder at the top of the library that pasted pictures go into.
    /// Visible in Finder; kept out of the sidebar and the wall, like the Shelf.
    static let folder = "Images"
    /// What counts as a picture, for a drop, a file in the Images folder, or sync.
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tiff", "tif", "webp", "bmp"]
    /// On the whole paragraph of an image line; the value is a `Placement`.
    static let key = NSAttributedString.Key("glassine.image")
    /// Room between the picture and the caption line under it.
    static let gap: CGFloat = 8
    /// A picture is never taller than this on the page; a tall one is scaled down.
    static let maxHeight: CGFloat = 480
    static let cornerRadius: CGFloat = 8

    /// Where a paragraph's picture goes: the file, and the size it is drawn at.
    final class Placement: NSObject {
        let url: URL?
        let size: CGSize
        let alt: String
        init(url: URL?, size: CGSize, alt: String) { self.url = url; self.size = size; self.alt = alt }
    }

    /// A paragraph that is one image and nothing else: `![alt](path "title")`,
    /// with spaces either side allowed.
    static let paragraphRx = try! NSRegularExpression(
        pattern: "^[ \\t]*!\\[([^\\]\\n]*)\\]\\(([^)\\s]+)(?:[ \\t]+\"[^\"]*\")?\\)[ \\t]*$")

    // MARK: - Where a path points

    /// A link's destination as a file, when it is one on this Mac: a path
    /// relative to the document's folder, as the editor writes it; failing
    /// that, relative to the library's root; failing that, a file of that
    /// name in the Images folder — a document moved by hand still finds its
    /// pictures. Web addresses are left to Review's web view.
    static func resolve(_ raw: String, documentURL: URL?, libraryRoot: URL?) -> URL? {
        let path = raw.removingPercentEncoding ?? raw
        if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("data:") { return nil }
        let fm = FileManager.default
        if path.hasPrefix("file://"), let u = URL(string: raw) ?? URL(string: path) { return fm.fileExists(atPath: u.path) ? u : nil }
        if path.hasPrefix("/") { return fm.fileExists(atPath: path) ? URL(fileURLWithPath: path) : nil }
        if path.hasPrefix("~") {
            let expanded = (path as NSString).expandingTildeInPath
            return fm.fileExists(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        var candidates: [URL] = []
        if let documentURL {
            candidates.append(documentURL.deletingLastPathComponent().appendingPathComponent(path).standardizedFileURL)
        }
        if let libraryRoot {
            candidates.append(libraryRoot.appendingPathComponent(path).standardizedFileURL)
            let name = (path as NSString).lastPathComponent
            if !name.isEmpty { candidates.append(libraryRoot.appendingPathComponent(folder).appendingPathComponent(name)) }
        }
        return candidates.first { fm.fileExists(atPath: $0.path) }
    }

    /// `to`, written relative to the folder `from` is in: `../Images/a.png`.
    static func relativePath(to target: URL, fromDocumentAt document: URL) -> String {
        let base = document.deletingLastPathComponent().standardizedFileURL.pathComponents
        let dest = target.standardizedFileURL.pathComponents
        var common = 0
        while common < base.count, common < dest.count, base[common] == dest[common] { common += 1 }
        let ups = Array(repeating: "..", count: base.count - common)
        let rest = dest[common...]
        let path = (ups + rest).joined(separator: "/")
        return encode(path)
    }

    /// A path as a Markdown destination: spaces and the characters that
    /// would end or confuse the link, percent-encoded; the rest left alone.
    static func encode(_ path: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "()")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }

    // MARK: - Where a new picture goes

    /// The folder a picture pasted into `document` is written to: the
    /// library's Images folder, or beside a document from outside the library.
    static func targetFolder(for document: URL, libraryRoot: URL?, isLoose: Bool) -> URL {
        if isLoose || libraryRoot == nil { return document.deletingLastPathComponent() }
        return libraryRoot!.appendingPathComponent(folder, isDirectory: true)
    }

    /// A name for a pasted picture: the document's name, slugged, and the
    /// moment, so a folder of them sorts by when they were pasted — unique
    /// within its folder.
    static func newFileURL(in folderURL: URL, documentTitle: String, ext: String, preferredStem: String? = nil) -> URL {
        let stem: String
        if let preferredStem, !preferredStem.isEmpty {
            stem = preferredStem
        } else {
            let slug = documentTitle.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }.prefix(5).joined(separator: "-")
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd-HHmmss"
            stem = (slug.isEmpty ? "image" : slug) + "-" + f.string(from: Date())
        }
        var candidate = folderURL.appendingPathComponent(stem).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folderURL.appendingPathComponent("\(stem)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }

    // MARK: - The clipboard

    /// Image files on a pasteboard — a drop from Finder, a copy of files.
    static func imageFileURLs(on pb: NSPasteboard) -> [URL] {
        guard let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return [] }
        return urls.filter { extensions.contains($0.pathExtension.lowercased()) }
    }

    /// The picture a pasteboard holds as data — a screenshot, a copy out of
    /// Preview or a browser — when the paste is a picture and not text that
    /// happens to carry one: there is image data, and the plain string is
    /// nothing, or only the picture's own address.
    static func imageData(on pb: NSPasteboard) -> (data: Data, ext: String)? {
        let types = pb.types ?? []
        guard types.contains(.png) || types.contains(.tiff) || types.contains(NSPasteboard.PasteboardType("public.jpeg")) else { return nil }
        if types.contains(PasteMarkdown.ownType) { return nil }
        if let plain = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty {
            let lower = plain.lowercased()
            let isAddress = (lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file://"))
                && !plain.contains(where: { $0.isWhitespace })
            if !isAddress { return nil }
        }
        if let data = pb.data(forType: .png) { return (data, "png") }
        if let data = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) { return (data, "jpg") }
        if let tiff = pb.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { return (png, "png") }
        return nil
    }

    static var pasteboardTypes: [NSPasteboard.PasteboardType] {
        [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg"), .fileURL]
    }
}

// MARK: - Links that move with the document

/// Relative links rewritten when a document changes folder — a move, the
/// Shelf — so a picture (or another document) linked relative to the old
/// place is linked relative to the new one, for every other app's sake; the
/// editor would have found the picture by name anyway.
enum RelativeLinks {
    private static let destinationRx = try! NSRegularExpression(
        pattern: "(!?\\[[^\\]\\n]*\\]\\()([^)\\s]+)((?:[ \\t]+\"[^\"]*\")?\\))")

    /// The text with its relative destinations re-pointed, or nil when
    /// nothing changes. `oldRel` and `newRel` are the document's paths in
    /// the library, before and after.
    static func rewrite(_ text: String, from oldRel: String, to newRel: String) -> String? {
        let oldDir = (oldRel as NSString).deletingLastPathComponent
        let newDir = (newRel as NSString).deletingLastPathComponent
        guard oldDir != newDir else { return nil }
        let ns = text as NSString
        var out = ""
        var at = 0
        var changed = false
        for m in destinationRx.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) {
            let dest = ns.substring(with: m.range(at: 2))
            guard let moved = repoint(dest, fromDir: oldDir, toDir: newDir) else { continue }
            out += ns.substring(with: NSRange(location: at, length: m.range(at: 2).location - at))
            out += moved
            at = m.range(at: 2).upperBoundValue
            changed = true
        }
        guard changed else { return nil }
        out += ns.substring(from: at)
        return out
    }

    /// One destination, relative to `fromDir`, as it reads from `toDir`; nil
    /// when it is not a relative path, or leaves the library.
    static func repoint(_ dest: String, fromDir: String, toDir: String) -> String? {
        let lower = dest.lowercased()
        if dest.hasPrefix("#") || dest.hasPrefix("/") || dest.hasPrefix("~") || lower.contains("://") || lower.hasPrefix("mailto:") || lower.hasPrefix("data:") { return nil }
        let decoded = dest.removingPercentEncoding ?? dest
        // Resolve against the old folder, within the library.
        var parts = fromDir.isEmpty ? [] : fromDir.split(separator: "/").map(String.init)
        for piece in decoded.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if piece == "." || piece.isEmpty { continue }
            if piece == ".." {
                guard !parts.isEmpty else { return nil }   // out of the library: left alone
                parts.removeLast()
            } else {
                parts.append(piece)
            }
        }
        // Relativize against the new folder.
        let base = toDir.isEmpty ? [] : toDir.split(separator: "/").map(String.init)
        var common = 0
        while common < base.count, common < parts.count, base[common] == parts[common] { common += 1 }
        let ups = Array(repeating: "..", count: base.count - common)
        let rel = (ups + parts[common...]).joined(separator: "/")
        let encoded = ImageEmbed.encode(rel)
        return encoded == dest ? nil : encoded
    }
}

// MARK: - The store

/// Pictures read once and kept: their size, read from the file's header on
/// the spot so a page lays out right the first time; the picture itself,
/// decoded off the main thread no larger than the page needs; and, for
/// Review and a rich-text copy, the picture inside the page as a data URL.
final class ImageStore {
    static let shared = ImageStore()
    static let loaded = Notification.Name("glassine.imageLoaded")

    private struct Entry {
        var modified: Date
        var pointSize: CGSize
        var image: NSImage?
        var dataURI: String?
        var loading = false
        /// Pasted and not yet written: kept whatever the disk says, until settled.
        var primed = false
        /// When the picture was last drawn; the least recent lets go of its
        /// pixels when there are many.
        var used: CFTimeInterval = 0
    }
    /// How many decoded pictures are kept at once; a page is rarely more.
    private let keep = 24
    private var entries: [URL: Entry] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "glassine.images", qos: .userInitiated)
    /// Decoded no larger than this on its long side: a 5K screenshot drawn
    /// in a 600-point column needs nothing like its pixels.
    private let decodeMaxPixel: CGFloat = 2048
    private let embedMaxPixel: CGFloat = 1600

    /// Nil when there is no such file.
    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    /// The entry for a file as it is now; a changed file starts over.
    private func entry(for url: URL, create: Bool) -> Entry? {
        let mod = modificationDate(url)
        if let e = entries[url], e.primed || e.modified == mod { return e }
        guard create, let mod, let size = ImageStore.pointSize(ofFileAt: url) else { return nil }
        let e = Entry(modified: mod, pointSize: size)
        entries[url] = e
        return e
    }

    /// The picture's size in points — its pixels over its density — from the
    /// file's header alone. Nil for a file that is not a picture.
    static func pointSize(ofFileAt url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return pointSize(of: source)
    }

    static func pointSize(of source: CGImageSource) -> CGSize? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat,
              w > 0, h > 0 else { return nil }
        var pw = w, ph = h
        // EXIF orientation 5–8 turns the picture on its side.
        if let o = props[kCGImagePropertyOrientation] as? UInt32, o >= 5 { swap(&pw, &ph) }
        let dpiW = (props[kCGImagePropertyDPIWidth] as? CGFloat) ?? 72
        let dpiH = (props[kCGImagePropertyDPIHeight] as? CGFloat) ?? 72
        let scaleW = dpiW > 0 ? dpiW / 72 : 1, scaleH = dpiH > 0 ? dpiH / 72 : 1
        return CGSize(width: pw / scaleW, height: ph / scaleH)
    }

    /// The size, in points, of a picture on disk; nil when it cannot be read.
    func pointSize(of url: URL) -> CGSize? {
        lock.lock(); defer { lock.unlock() }
        return entry(for: url, create: true)?.pointSize
    }

    /// The decoded picture when it is in hand; otherwise nil, and it is
    /// decoded off the main thread, `ImageStore.loaded` posted when it is.
    func image(for url: URL) -> NSImage? {
        lock.lock()
        guard var e = entry(for: url, create: true) else { lock.unlock(); return nil }
        if let image = e.image {
            e.used = CACurrentMediaTime()
            entries[url] = e
            lock.unlock()
            return image
        }
        if !e.loading {
            e.loading = true
            entries[url] = e
            lock.unlock()
            let mod = e.modified
            queue.async { [weak self] in self?.decode(url, modified: mod) }
        } else {
            lock.unlock()
        }
        return nil
    }

    /// A picture just made — pasted — kept under the name it is being written
    /// to, so the page lays out for it before the file has landed on the
    /// disk: its size now, from the data's header; the picture itself
    /// decoded off the main thread like any other.
    func prime(_ url: URL, data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let size = ImageStore.pointSize(of: source) else { return }
        lock.lock()
        var e = Entry(modified: Date(), pointSize: size)
        e.primed = true
        e.loading = true
        entries[url] = e
        let mod = e.modified
        lock.unlock()
        queue.async { [weak self] in self?.decode(source, for: url, modified: mod) }
    }

    /// The primed picture is on the disk: from here the file's date is what
    /// the store keys on, as for any other.
    func settle(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        guard var e = entries[url], e.primed else { return }
        e.primed = false
        e.modified = modificationDate(url) ?? e.modified
        entries[url] = e
    }

    private func decode(_ url: URL, modified: Date) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { finishDecode(url, modified: modified, image: nil); return }
        decode(source, for: url, modified: modified)
    }

    private func decode(_ source: CGImageSource, for url: URL, modified: Date) {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: decodeMaxPixel,
        ]
        var image: NSImage?
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            let size = ImageStore.pointSize(of: source) ?? CGSize(width: cg.width, height: cg.height)
            image = NSImage(cgImage: cg, size: size)
        }
        finishDecode(url, modified: modified, image: image)
    }

    private func finishDecode(_ url: URL, modified: Date, image: NSImage?) {
        lock.lock()
        if var e = entries[url], e.modified == modified {
            e.image = image
            e.loading = false
            e.used = CACurrentMediaTime()
            entries[url] = e
        }
        // Pictures not drawn for the longest let go of their pixels; their
        // sizes stay, so the pages they are on keep their layout.
        let held = entries.filter { $0.value.image != nil }
        if held.count > keep {
            for (key, _) in held.sorted(by: { $0.value.used < $1.value.used }).prefix(held.count - keep) {
                entries[key]?.image = nil
            }
        }
        lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: ImageStore.loaded, object: url) }
    }

    /// The picture as a `data:` URL for a page — Review, the PDF, a copy as
    /// rich text — no larger than 1600 pixels on its long side, a JPEG unless
    /// it has transparency. Made on the calling thread and kept.
    func dataURI(for url: URL) -> String? {
        lock.lock()
        guard let e = entry(for: url, create: true) else { lock.unlock(); return nil }
        if let uri = e.dataURI { lock.unlock(); return uri }
        let mod = e.modified
        lock.unlock()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: embedMaxPixel,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let hasAlpha: Bool = {
            switch cg.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: return false
            default: return true
            }
        }()
        let rep = NSBitmapImageRep(cgImage: cg)
        let data: Data?
        let mime: String
        if hasAlpha || url.pathExtension.lowercased() == "gif" {
            data = rep.representation(using: .png, properties: [:]); mime = "image/png"
        } else {
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86]); mime = "image/jpeg"
        }
        guard let data else { return nil }
        let uri = "data:\(mime);base64," + data.base64EncodedString()
        lock.lock()
        if var e = entries[url], e.modified == mod { e.dataURI = uri; entries[url] = e }
        lock.unlock()
        return uri
    }

    /// The page's pictures as `data:` URLs, for the HTML renderer: a local
    /// file is embedded, anything else is left as written.
    func resolver(documentURL: URL?, libraryRoot: URL?) -> (String) -> String {
        { [weak self] src in
            guard let self, let url = ImageEmbed.resolve(src, documentURL: documentURL, libraryRoot: libraryRoot) else { return src }
            return self.dataURI(for: url) ?? src
        }
    }
}

// MARK: - The typesetter

/// TextKit leaves out the room above the first paragraph of a text
/// container; a picture at the very top of a page needs its room all the
/// same. Every other paragraph's spacing is the typesetter's own.
final class GlassineTypesetter: NSATSTypesetter {
    override func paragraphSpacing(beforeGlyphAt glyphIndex: Int, withProposedLineFragmentRect rect: NSRect) -> CGFloat {
        let spacing = super.paragraphSpacing(beforeGlyphAt: glyphIndex, withProposedLineFragmentRect: rect)
        guard spacing == 0, let storage = attributedString, storage.length > 0,
              let lm = layoutManager else { return spacing }
        let char = lm.characterIndexForGlyph(at: glyphIndex)
        guard char == 0, storage.attribute(ImageEmbed.key, at: 0, effectiveRange: nil) != nil,
              let style = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle else { return spacing }
        return style.paragraphSpacingBefore
    }
}

import SwiftUI
#if os(macOS)
import AppKit
typealias HostViewRepresentable = NSViewRepresentable
typealias HostView = NSView
#else
import UIKit
typealias HostViewRepresentable = UIViewRepresentable
typealias HostView = UIView
#endif

/// A document row being carried through the sidebar's folder tree.
///
/// The rows are not system drag and drop — no snapshot on a translucent
/// plate, no drop indicator line. The row itself lifts under the pointer and
/// travels with it; the rows it passes step aside with a spring; a folder it
/// is held over lights up; letting go glides it into the gap, and the order
/// is written down as the library's *Your order*. Everything a row needs to
/// know about the carry is here, so a row that is not the one being carried
/// only redraws when the gap moves, not on every pointer move.
///
/// Coordinates are the sidebar's own (`SidebarView.space`), which do not move
/// with the scroll; the carried row's lift adds whatever the tree has
/// scrolled under the pointer since the pick-up, so it stays under the pointer
/// while the edges scroll the tree.
@Observable
final class SidebarDrag {
    /// One tree row, and the seam between rows.
    static let pitch: CGFloat = DocumentRow.treeHeight + SidebarView.rowSpacing
    /// Within this much of the top or bottom of the tree the pointer scrolls it.
    static let scrollZone: CGFloat = 34
    /// The fastest the edges scroll, in points a frame.
    static let scrollSpeed: CGFloat = 11

    /// The document being carried, or nil.
    private(set) var id: String?
    /// The folder whose rows it moves among, its row there, and how many rows the folder has.
    private(set) var folder = ""
    private(set) var from = 0
    private(set) var count = 0
    /// The row it would land in if let go now.
    private(set) var to = 0
    /// How far it has been carried from its own row, in points.
    var lift: CGFloat = 0
    /// A folder row under the pointer ("" for the Documents header): letting
    /// go moves the document there instead of reordering.
    private(set) var overFolder: String?
    /// True from the pick-up until the drop has been written down; rows and
    /// folders that are not part of it keep still meanwhile.
    var active: Bool { id != nil }

    /// Where each folder row is, for the drop; kept by the rows themselves.
    @ObservationIgnored var folderFrames: [String: CGRect] = [:]
    /// The visible part of the tree, for the edges that scroll it.
    @ObservationIgnored var viewport: CGRect = .zero
    #if os(macOS)
    @ObservationIgnored weak var scrollView: NSScrollView?
    #else
    @ObservationIgnored weak var scrollView: UIScrollView?
    #endif

    @ObservationIgnored private var pointer: CGPoint = .zero
    @ObservationIgnored private var start: CGPoint = .zero
    @ObservationIgnored private var scrollAtStart: CGFloat = 0
    @ObservationIgnored private var scrollSpeed: CGFloat = 0
    @ObservationIgnored private var scroller: Timer?

    enum Outcome {
        case place(Int)
        case move(String)
    }

    // MARK: - The carry

    func begin(id: String, folder: String, index: Int, count: Int, at point: CGPoint) {
        self.id = id
        self.folder = folder
        self.from = index
        self.count = count
        self.to = index
        self.lift = 0
        self.overFolder = nil
        start = point
        pointer = point
        scrollAtStart = scrollOffset
        #if os(macOS)
        NSCursor.closedHand.push()
        ScreenshotMode.note("drag begin \(id) in \"\(folder)\" at \(index) of \(count)")
        #endif
    }

    func update(to point: CGPoint) {
        pointer = point
        recompute()
        scrollIfAtEdge()
    }

    /// What letting go here means. The carry stays live until `clear()`, so
    /// the row can glide into its gap first.
    func outcome() -> Outcome {
        stopScrolling()
        #if os(macOS)
        ScreenshotMode.note("drag end lift=\(Int(lift)) to=\(to) over=\(overFolder ?? "-")")
        #endif
        if let overFolder { return .move(overFolder) }
        return .place(to)
    }

    func clear() {
        stopScrolling()
        if id != nil {
            #if os(macOS)
            NSCursor.pop()
            #endif
        }
        id = nil
        overFolder = nil
        lift = 0
        from = 0
        to = 0
        count = 0
    }

    private func recompute() {
        let scrolled = scrollOffset - scrollAtStart
        lift = (pointer.y - start.y) + scrolled
        var over: String?
        for (path, frame) in folderFrames where path != folder && frame.insetBy(dx: 0, dy: 1).contains(pointer) {
            over = path
            break
        }
        if overFolder != over { overFolder = over }
        let slot = over == nil ? max(0, min(count - 1, from + Int((lift / SidebarDrag.pitch).rounded()))) : from
        if to != slot { to = slot }
    }

    // MARK: - Scrolling at the edges

    private func scrollIfAtEdge() {
        guard viewport.height > 0 else { return }
        let zone = SidebarDrag.scrollZone
        var v: CGFloat = 0
        if pointer.y < viewport.minY + zone {
            v = -(viewport.minY + zone - pointer.y) / zone
        } else if pointer.y > viewport.maxY - zone {
            v = (pointer.y - (viewport.maxY - zone)) / zone
        }
        scrollSpeed = max(-1, min(1, v)) * SidebarDrag.scrollSpeed
        if scrollSpeed == 0 {
            stopScrolling()
        } else if scroller == nil {
            let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.scrollTick() }
            RunLoop.main.add(t, forMode: .common)
            scroller = t
        }
    }

    private func scrollTick() {
        guard active, scrollSpeed != 0 else { stopScrolling(); return }
        let before = scrollOffset
        scroll(by: scrollSpeed)
        if scrollOffset == before { stopScrolling(); return }   // the end of the tree
        recompute()
    }

    private func stopScrolling() {
        scroller?.invalidate()
        scroller = nil
        scrollSpeed = 0
    }

    /// How far the tree is scrolled from its top, in points.
    private var scrollOffset: CGFloat {
        #if os(macOS)
        guard let sv = scrollView else { return 0 }
        let clip = sv.contentView
        if sv.documentView?.isFlipped ?? true { return clip.bounds.origin.y }
        let reach = max(0, (sv.documentView?.frame.height ?? 0) - clip.bounds.height)
        return reach - clip.bounds.origin.y
        #else
        return scrollView?.contentOffset.y ?? 0
        #endif
    }

    private func scroll(by delta: CGFloat) {
        #if os(macOS)
        guard let sv = scrollView, let doc = sv.documentView else { return }
        let clip = sv.contentView
        let reach = max(0, doc.frame.height - clip.bounds.height)
        var origin = clip.bounds.origin
        if doc.isFlipped {
            origin.y = max(0, min(reach, origin.y + delta))
        } else {
            origin.y = max(0, min(reach, origin.y - delta))
        }
        clip.scroll(to: origin)
        sv.reflectScrolledClipView(clip)
        #else
        guard let sv = scrollView else { return }
        let reach = max(0, sv.contentSize.height - sv.bounds.height)
        var offset = sv.contentOffset
        offset.y = max(0, min(reach, offset.y + delta))
        sv.setContentOffset(offset, animated: false)
        #endif
    }
}

/// A row's place in its folder's list, for the rows that can be carried.
struct ReorderSlot {
    let folder: String
    let index: Int
    /// The folder's documents in the order they are shown, whatever sort made it.
    let shown: [DocumentRef]
    var count: Int { shown.count }
}

// MARK: - Finding the scroll view

/// Sits in the tree's background and hands the drag the scroll view around
/// it, which is how the edges scroll and how the lift knows how far the tree
/// has moved under the pointer.
struct ScrollHostFinder: HostViewRepresentable {
    let drag: SidebarDrag

    #if os(macOS)
    func makeNSView(context: Context) -> Probe { let v = Probe(); v.drag = drag; return v }
    func updateNSView(_ view: Probe, context: Context) { view.drag = drag; view.report() }
    #else
    func makeUIView(context: Context) -> Probe { let v = Probe(); v.drag = drag; return v }
    func updateUIView(_ view: Probe, context: Context) { view.drag = drag; view.report() }
    #endif

    final class Probe: HostView {
        weak var drag: SidebarDrag?
        #if os(macOS)
        override var isFlipped: Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); report() }
        override func layout() { super.layout(); report() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func report() { drag?.scrollView = enclosingScrollView }
        #else
        override func didMoveToWindow() { super.didMoveToWindow(); report() }
        override func layoutSubviews() { super.layoutSubviews(); report() }
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
        func report() {
            var v: UIView? = superview
            while let s = v, !(s is UIScrollView) { v = s.superview }
            drag?.scrollView = v as? UIScrollView
        }
        #endif
    }
}

// MARK: - Drop targets

/// A folder row (or the Documents header, as "") that a carried document can
/// be let go on: it tells the drag where it is, and lights up while the
/// document is held over it.
struct FolderDropTarget: ViewModifier {
    let path: String
    @Environment(SidebarDrag.self) private var drag: SidebarDrag?
    @EnvironmentObject private var state: AppState

    private var lit: Bool { drag?.overFolder == path }

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(state.theme.accent.color.opacity(lit ? 0.16 : 0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(state.theme.accent.color.opacity(lit ? 0.55 : 0), lineWidth: 1)
                    )
            )
            .animation(.easeOut(duration: 0.14), value: lit)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(SidebarView.space))
            } action: { frame in
                drag?.folderFrames[path] = frame
            }
            // A row the tree has let go of (scrolled away, the folder closed)
            // must not keep catching drops where it used to be.
            .onDisappear { drag?.folderFrames[path] = nil }
    }
}

extension View {
    func folderDropTarget(_ path: String) -> some View { modifier(FolderDropTarget(path: path)) }
}

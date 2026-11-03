import AppKit
import SwiftUI

// The glass the app's cards are made of, in one place: Settings, the command
// bar, the shortcut sheet, the tour and the prompts are all cut from it, so
// they match each other and change together. Before this each of them
// carried its own copy of the recipe, with the veil a few hundredths apart.

/// A card on the app's own glass: the window's blur under a veil of the
/// theme's tint, a hairline round the edge, and a shadow that lifts it off
/// the page. `veil` is how much of the tint lies over the blur; the tour
/// asks for more, since it stands over busy pages.
struct GlassCard: ViewModifier {
    let theme: Theme
    var radius: CGFloat = 16
    var veil: Double? = nil
    var shadowRadius: CGFloat = 30
    var shadowY: CGFloat = 12

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(
                ZStack {
                    VisualEffectBackground(material: .hudWindow, blendingMode: .withinWindow)
                    theme.tint.color.opacity(veil ?? (theme.isDark ? 0.40 : 0.52))
                }
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.text.color.opacity(theme.isDark ? 0.12 : 0.1), lineWidth: 1))
            .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.18), radius: shadowRadius, y: shadowY)
            .foregroundStyle(theme.text.color)
    }
}

extension View {
    /// The app's card glass; see `GlassCard`.
    func glassCard(_ theme: Theme, radius: CGFloat = 16, veil: Double? = nil,
                   shadowRadius: CGFloat = 30, shadowY: CGFloat = 12) -> some View {
        modifier(GlassCard(theme: theme, radius: radius, veil: veil, shadowRadius: shadowRadius, shadowY: shadowY))
    }
}

/// The veil over the page while a card is up — a wash of the theme's tint,
/// which a click on puts the card away. `light` is the thinner one the
/// command bar uses, so the page stays readable while a command is typed.
struct Scrim: View {
    let theme: Theme
    var light: Bool = false
    let dismiss: () -> Void

    var body: some View {
        theme.tint.color.opacity(light ? (theme.isDark ? 0.25 : 0.18) : (theme.isDark ? 0.35 : 0.25))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
    }
}

// MARK: - Motion that steps aside

/// Motion that steps aside when the Mac asks for stillness: `Motion.quiet`
/// hands an animation back, or nothing under Reduce Motion, so a view can
/// write `.animation(Motion.quiet(.easeOut(duration: 0.2)), value: x)` and
/// honour the setting without a second thought. (The editor's caret, the
/// backdrop's drift and the card zoom check the setting on their own.)
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static func quiet(_ animation: Animation) -> Animation? { reduced ? nil : animation }
}

// MARK: - Dragging the window by its glass

/// The empty ground of a view is a handle for the window: a press on it
/// that moves carries the window, the way the glass beside the editor's
/// column does (GlassineTextView). Only the ground — a card, a row or a
/// button over it keeps its own press. (The window's own
/// movable-by-background was turned off for what it cost on every frame;
/// this is the part of it worth having, at no cost until a press lands.)
struct DragsWindowByGround: ViewModifier {
    @State private var dragging = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in
                    guard !dragging, let event = NSApp.currentEvent, event.type == .leftMouseDragged,
                          let window = event.window else { return }
                    dragging = true
                    ScreenshotMode.note("glass drag from the ground")
                    window.performDrag(with: event)
                }
                .onEnded { _ in dragging = false }
        )
    }
}

extension View {
    /// Empty ground that drags the window; see `DragsWindowByGround`.
    func dragsWindowByGround() -> some View {
        contentShape(Rectangle()).modifier(DragsWindowByGround())
    }
}

// MARK: - Prompts

/// A question asked in the window, on the app's own glass, where a system
/// sheet used to drop in from the title bar in the Mac's grey: a line or
/// two, a field when a name is wanted, and two capsules. Return answers,
/// Esc keeps things as they were, and so does a click on the page behind.
struct PromptCard: View {
    let theme: Theme
    let title: String
    var message: String? = nil
    /// With a field: the text, and what the field says while empty.
    var text: Binding<String>? = nil
    var placeholder: String = ""
    var confirmLabel: String = "OK"
    var destructive: Bool = false
    var canConfirm: Bool = true
    var confirm: () -> Void
    var cancel: (() -> Void)? = nil

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(.system(size: 12.5))
                    .opacity(0.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let text {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($fieldFocused)
                    .onSubmit { if canConfirm { confirm() } }
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(theme.text.color.opacity(theme.isDark ? 0.08 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(fieldFocused ? theme.accent.color.opacity(0.55) : theme.text.color.opacity(0.1), lineWidth: 1)
                    )
                    .animation(.easeOut(duration: 0.15), value: fieldFocused)
                    .padding(.top, 2)
            }
            HStack(spacing: 8) {
                Spacer()
                if let cancel {
                    Button("Cancel", action: cancel)
                        .buttonStyle(GlassButtonStyle(theme: theme))
                }
                Button(confirmLabel, action: confirm)
                    .buttonStyle(GlassButtonStyle(theme: theme, prominent: true, destructive: destructive))
                    .disabled(!canConfirm)
                    .opacity(canConfirm ? 1 : 0.45)
            }
            .padding(.top, 6)
        }
        .padding(20)
        .frame(width: 360)
        .glassCard(theme, radius: 14, shadowRadius: 28, shadowY: 10)
        .onTapGesture { }
        .onAppear {
            // The keyboard goes to the field — once the card is on screen.
            if text != nil { DispatchQueue.main.async { fieldFocused = true } }
        }
        .background(
            // Return, from anywhere in the window: the page's editor has
            // given up the keyboard while a prompt is up (ContentView). Esc
            // is heard by the app's key monitor, like every other card's.
            Button("") { if canConfirm { confirm() } }
                .keyboardShortcut(.defaultAction)
                .frame(width: 0, height: 0)
                .opacity(0)
        )
    }
}

/// One of the app's prompts, up over the page: the folder's or document's
/// new name, or "Move to the Trash?".
struct PromptOverlay: View {
    @EnvironmentObject var state: AppState
    let prompt: AppState.Prompt
    @State private var text = ""
    /// Answered once: Return in the field and the card's default key can
    /// both hear the same press.
    @State private var answered = false

    private var theme: Theme { state.theme }

    /// The prompt's answer, taken once and then the card goes.
    private func answer(_ act: @escaping () -> Void) -> () -> Void {
        {
            guard !answered else { return }
            answered = true
            state.pendingPrompt = nil
            act()
        }
    }

    var body: some View {
        ZStack {
            Scrim(theme: theme) { state.pendingPrompt = nil }
            card
                .padding(.bottom, 40)
        }
        .onAppear {
            if case .rename(let path, _) = prompt {
                text = (path as NSString).lastPathComponent
                if !state.library.url(forRelativePath: path).isDirectoryURL {
                    text = (text as NSString).deletingPathExtension
                }
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        switch prompt {
        case .newFolder(let parent):
            PromptCard(theme: theme, title: "New Folder",
                       message: parent.isEmpty ? nil : "Inside \(parent.replacingOccurrences(of: "/", with: " / ")).",
                       text: $text, placeholder: "Name", confirmLabel: "Create", canConfirm: !trimmed.isEmpty,
                       confirm: answer { state.createFolder(named: trimmed, in: parent) },
                       cancel: { state.pendingPrompt = nil })
        case .rename(let path, let isFolder):
            PromptCard(theme: theme, title: isFolder ? "Rename Folder" : "Rename Document",
                       message: isFolder ? nil : "A document named by hand keeps its name; the first line stops naming it.",
                       text: $text, placeholder: "Name", confirmLabel: "Rename", canConfirm: !trimmed.isEmpty,
                       confirm: answer { state.rename(path, to: trimmed, isFolder: isFolder) },
                       cancel: { state.pendingPrompt = nil })
        case .trash(let path, let isFolder):
            PromptCard(theme: theme, title: trashQuestion(path, isFolder: isFolder),
                       message: "It can be put back with ⌘Z, or from the Trash.",
                       confirmLabel: "Move to Trash", destructive: true,
                       confirm: answer { state.trashNow(path) },
                       cancel: { state.pendingPrompt = nil })
        }
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespaces) }

    private func trashQuestion(_ path: String, isFolder: Bool) -> String {
        let last = (path as NSString).lastPathComponent
        let name: String
        if isFolder {
            name = last
        } else if let title = state.library.document(withID: path)?.title, !title.isEmpty {
            name = title
        } else {
            name = (last as NSString).deletingPathExtension
        }
        return isFolder
            ? "Move the folder “\(name)” and everything in it to the Trash?"
            : "Move “\(name)” to the Trash?"
    }
}

/// Something that went wrong, said on the glass rather than in an alert.
struct ErrorOverlay: View {
    @EnvironmentObject var state: AppState
    let message: String

    var body: some View {
        ZStack {
            Scrim(theme: state.theme) { state.errorMessage = nil }
            PromptCard(theme: state.theme, title: "Something went wrong", message: message,
                       confirmLabel: "OK", confirm: { state.errorMessage = nil })
                .padding(.bottom, 40)
        }
    }
}

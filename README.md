# Glassine

A quiet Markdown writing app for macOS. A translucent glass window, a caret that glides instead of jumps, a library that lives in iCloud Drive, autosave that never asks, and a Craft-style sidebar you can hide with one key.

Native Swift (SwiftUI + AppKit), no dependencies, no Xcode project — a Swift package and a build script. MIT licensed.

![Glassine in Review mode, Glass style, over a blurred desktop](docs/screenshot.jpg)

The caret, which is most of the point:

![Typing in Glassine — the caret glides between positions](docs/demo.gif)

There's a [45-second walkthrough](docs/demo.mp4) of the editor, Review mode and the All Documents mosaic as well.

*Glassine is the thin, translucent paper used to protect prints.*

## Install

Requirements: macOS 14 or later and Xcode (free, from the App Store). Then:

```bash
git clone https://github.com/a-libre/glassine.git
cd glassine
./build.sh --install    # compiles, copies Glassine.app to /Applications, opens it
```

Other options: `./build.sh` (build only, into `build/Glassine.app`), `./build.sh --run` (build and open without installing), `./build.sh --debug` (faster compile while hacking). To update later: `git pull && ./build.sh --install`.

The first launch asks for permission to access iCloud Drive. Say yes — that's where the library lives.

You can also open `Package.swift` in Xcode and press Run, which is handy for debugging; the assembled `.app` from `build.sh` is what you want for daily use (it has the icon and a stable identity for macOS permissions).

There is no signed download yet, so building from source is the only way to run it for now. A notarized `.dmg` is the next step; the pipeline for it is in `release.sh` and [RELEASING.md](RELEASING.md).

## What it does

- **Glass.** The window is a blur of whatever is behind it, tinted by the theme. Six built-in themes, dark by default; make your own in Settings with live preview, and export them as JSON.
- **Smooth caret.** The insertion point glides between positions instead of jumping. Speed, blink style and width are adjustable.
- **A library, not a file picker.** Documents live in `iCloud Drive/Glassine` as plain `.md` files and folders. New document is ⌘N; the file takes its name from the first line as you write.
- **Autosave** half a second after you stop typing, and at least every few seconds while you type.
- **Sidebar** with recents, starred, folders and tags, hidden and shown with ⌘S.
- **All Documents** (⌘P): a mosaic of every document with rendered previews, navigable with the arrow keys.
- **Review** (⌘↩): the document rendered as HTML in one of five styles — Glass, GitHub, Book, Editorial, Mono.
- **Typewriter scrolling, focus mode, word count and reading time.**
- **Markdown, lightly styled.** Syntax stays visible but steps back: headings, emphasis, code, quotes, lists, tasks, links, tags.
- **Copy the whole document** as Markdown (⌘⇧C) or rich text (⌥⌘C).

## Where your writing lives

`~/Library/Mobile Documents/com~apple~CloudDocs/Glassine/` — that's the "Glassine" folder at the top level of iCloud Drive in Finder. Every document is a plain `.md` file, folders are folders. Anything you drop in there from Finder or another Mac shows up in the sidebar within a few seconds; anything Glassine writes syncs the usual iCloud way.

Change the location under Settings → General if you'd rather use a different folder (a Dropbox or Obsidian vault works fine).

## Saving

Always on. Glassine writes about half a second after you stop typing, at least every four seconds while you type continuously, when you switch documents, when the app loses focus, and on quit. The small dot at the bottom-left tells you what's happening: grey means clean, accent-colored means unsaved edits are pending, and a brief "Saved" with an iCloud check appears after each write. File → Save Now forces a write if you want the reassurance.

If a file changes on disk while it's open and you have no unsaved edits, Glassine reloads it. If both sides changed, your edits win and the other version is kept next to it as "… (conflict).md". Glassine compares file *contents* to decide this, not timestamps — iCloud rewrites modification dates after upload, and trusting them produced phantom conflict copies in the very first build. Any "(conflict)" files from that build are safe to delete.

## Naming

New documents start as "Untitled" and take their file name from the first line as you write (leading `#` and Markdown marks stripped). Rename a file yourself (⌘R or the sidebar's context menu) and Glassine stops touching its name. Turn the whole behavior off in Settings → General.

## Keyboard

| | |
|---|---|
| ⌘N / ⌘⇧N | New document / new folder |
| ⌘D | The Daily timeline — today in front, earlier days receding behind it |
| ⌥⌘D | Today's note (in a Daily folder, created on first use) |
| ⌘⇧E | Export the document as a PDF in the current Review style |
| ⌘/ | The shortcut sheet |
| ⌘K | The command bar — what makes sense where you are: Review styles in Review, sorting in the mosaic, modes in the editor |
| ⌘S (or ⌘\) | Show or hide the sidebar |
| ⌘P | All Documents — the mosaic view of the whole library |
| ⌘↩ | Review — the document rendered read-only in a chosen style (Esc or ⌘↩ leaves) |
| ⌘⇧C / ⌥⌘C | Copy the whole document as Markdown / as rich text |
| Esc | Zoom out one level: Review → editor → All Documents. Inside All Documents, Esc returns to the open document |
| ↑↓←→ and ↩ | In All Documents: move between cards and open the selected one (⌘↩ opens it in Review) |
| ⌃⌘T | Typewriter scrolling |
| ⌃⌘F | Focus mode (paragraph or sentence, pick in Settings) |
| ⌘B ⌘I ⌘E ⌘⇧K | Bold, italic, inline code, link (wraps the selection in Markdown) |
| ⌘⌥1 ⌘⌥2 ⌘⌥3 ⌘⌥0 | Heading level / body text |
| ⌘⇧L | Toggle a task checkbox (or click the `[ ]`) |
| ⌘F | Search the library — titles, tags and full text |
| ⌘⇧F | Find in the open document (⌘G for next) |
| ⇥ / ⇧⇥ | Nest or un-nest a list item — bullets, numbers, and tasks; numbered items renumber to fit, and Return on an empty nested item steps back out |
| ⌘R | Rename |
| ⌘⌫ | Move to Trash (it goes to the macOS Trash, so it's recoverable) |
| ⌘Z ⇧⌘Z | Undo and redo — typing first, then file operations: a new document, a rename, a move, a duplicate, a trash |
| ⌘+ ⌘− ⌘0 | Text size |
| ⌘, | Settings |
| ⌘⌥⇧D | Copy Debug Info (also in the Help menu) — caret geometry, layout and settings in one paste, for bug reports |

Help → Check for Updates… looks at GitHub Releases; the app also checks once a day unless you turn that off in Settings → General.

Return inside a list continues the list; Return on an empty item ends it.

## Caret

Settings → Caret. Smooth movement on or off, glide time (default 110 ms), whether to also glide while typing or only for arrow keys and clicks, blink style (soft fade, classic, or never) and width. The caret takes its color from the theme. If Reduce Motion is on in System Settings, gliding is disabled automatically.

## Themes

Six built in: Graphite (default), Sepia Night, Midnight, Moss, Frost and Paper. Pick one under View → Theme.

To make your own: Settings → Themes, select the one closest to what you want, press **+** to duplicate it, then edit. Everything is live in the main window while you tweak. A theme controls the glass material, the tint color and how strongly it covers the blur, an optional paper grain, and the colors for text, headings, accent, Markdown syntax, quotes, code, links, caret and selection. Themes export as small JSON files (the ••• menu), so they're easy to share or keep in a dotfiles repo.

Glass materials, roughly: *Soft glass* is the standard window blur, *Deep glass* is darker and blurrier, *Thin glass* lets more of the desktop through, *Frosted* is a light haze, and *Opaque* turns the blur off entirely.

## All Documents

The mosaic view (⌘P, the grid row at the top of the sidebar, Esc from the editor, or automatically when nothing is open) lays every document out as a card with its title and a small rendered preview, Craft-style. Cards are arranged shortest-column-first so the grid stays balanced; the current document gets a thin accent outline. The arrow keys move a selection between cards (left/right jump to the nearest card in the next column), Return opens the selected one and ⌘↩ opens it in Review. Search, tag filters and the sort order apply here too, and the right-click menu is the same as in the sidebar.

## Review

⌘↩ swaps the editor for a read-only rendering of the document — real HTML in a web view, so tables, nested lists, task lists, code blocks and images all appear the way another Markdown app would show them. Five styles, under View → Review Style or the pill at the top-right: **Glass** (your theme's colors, transparent over the blur), **GitHub** (github.com's rendering, light or dark with the theme), **Book** (a cream page with drop caps and small-cap headings), **Editorial** (magazine typography: heavy headlines, pull-quotes) and **Mono** (a terminal). ⌘+ / ⌘− scale the text in Review independently of the editor. Links open in your browser. Esc or ⌘↩ returns to editing at roughly the same place.

## Copying a document

⌘⇧C copies the whole document as Markdown; ⌥⌘C copies it as rich text (RTF and HTML go on the clipboard, so Mail, Notes, Slack and Google Docs keep headings, bold, lists and links). The copy button at the bottom-right of the editor does Markdown on click, with rich text one click-and-hold away, and both are in the right-click menus in the sidebar and All Documents.

## Tasks

`- [ ] ` starts a task. Click the brackets to check it off: the line goes strikethrough and fades, and the file gets a `[x]` that any Markdown app understands. Click again to reopen it. ⌘⇧L does the same from the keyboard and turns an ordinary line into a task when there is no box yet. The checkboxes in Review are live too, and a click there writes the `[x]` straight into the file.

## Daily notes

⌘D (or the Today row in the sidebar) opens the Daily timeline: today's note lying readable at the front, earlier days receding up the corridor behind it — tilted back, smaller and fainter toward the vanishing point. Scroll to walk back through the days; click a card to open it. ⌥⌘D skips the corridor and opens today's note directly, titled with the date and kept in a `Daily` folder created on first use. Press it again tomorrow and you get tomorrow's.

## Appearance

Settings → Themes can follow the system: pick one light theme and one dark theme and Glassine switches with macOS. Otherwise the chosen theme stays put.

## Dates

Type `@today`, `@yesterday` or `@tomorrow` followed by a space (or punctuation, or Return) and it becomes the actual date — `@September 1, 2026` in the file, drawn as a small capsule in the editor and in Review. Typing an ISO date like `@2026-09-01` gets the capsule too. Made for daily notes; the file stays plain text that any other app can read.

## Search

⌘F glides the search box from its spot in the mosaic header to the middle of the window and gives it the keyboard, with the mosaic filtering live behind it. Every word you type has to appear somewhere in a document's title, tags or text, ignoring case and accents; documents whose titles match are listed first. In the mosaic, the top result is selected as you type, so Return opens it, and the arrow keys walk the results. Esc clears the search.

## Tags

Write `#tag` anywhere in a document and it appears under Tags in the sidebar. Click a tag to filter the list. Hex colors like `#FFF` are ignored.

## Project layout

```
Sources/Glassine/
  App/        GlassineApp (scenes, menus), AppState, Settings, Theme
  Library/    Library (iCloud folder scanning + file operations), Document (autosave, renaming)
  Editor/     GlassineTextView (smooth caret, layout, typewriter, focus), MarkdownStyler, StyleConfig, EditorView bridge
  UI/         ContentView, SidebarView, EditorContainerView, SettingsView, GlassBackground
  Support/    HexColor, small extensions
Resources/    Info.plist, icon
build.sh      assembles and signs Glassine.app
```

## Rebuilding after you change something

Edit anything under `Sources/Glassine/`, then `./build.sh --run`. Incremental builds take a few seconds. If a change misbehaves, Help → Copy Debug Info gives a snapshot of the editor's state that is easy to paste into a chat.

## Known limits (v1)

- One window. Glassine is a single-library app by design.
- Export is PDF only (File → Export as PDF…); the files are plain Markdown, so any converter works on them directly for other formats.
- Drag-and-drop between folders isn't wired up; use the context menu's "Move To".
- Tested on macOS 26/27 with Xcode 26. Minimum deployment target is macOS 14.

## Credits

Built by Alex Libre with Claude (Anthropic's Cowork) over an evening in September 2026, starting from a wish list of two things loved about [Paper](https://apps.apple.com/us/app/paper-writing-app-notes/id1143513744) — the glass and the caret — and a few things it lacked. The sidebar and mosaic take their cues from [Craft](https://www.craft.do). No code from either.

# What's new, for the landing page

The top block below is what glassine.ink shows under "What's new" — `site/update.sh`
puts it there (and the version from Info.plist), and `release.sh` runs that on
every release. Newest version first. Three to five lines a version, each
`- **Title.** One or two plain sentences.` — links as `[text](url)`, keys as
`[[⌘K]]`. Older blocks stay as a record; only the top one is shown.

## 0.2.31 — November 3, 2026

- **Pictures on the page.** Paste a screenshot, drop an image file, or type `/image`: the picture is drawn in place, scaled to the column, and the document stays a plain Markdown file — the picture is a file of its own in an `Images` folder in the library, linked with an ordinary `![](…)` line. [Images.](https://docs.glassine.ink/editor/images)
- **They travel.** Review, the PDF and Copy as Rich Text carry the picture inside the page; the cards show a small one; iCloud and GitHub sync carry the files; moving a document rewrites its links to match.

## 0.2.30 — November 2, 2026

- **Every question on the glass.** Rename, New Folder, the Trash question and any error are cards on the page now, in the look's colours — no more grey system sheets. Return answers, Esc keeps things as they were.
- **A page on its way from iCloud says so.** It reads *Coming down from iCloud…* until the file lands, and nothing typed on it is lost; a file that cannot be read stays read-only and is never written over. [Files.](https://docs.glassine.ink/library/files#saving)
- **The fanned pages keep to the page.** [[⌥⇥]] lays the open pages out over the page, not across the sidebar, which steps back with it.
- **The glass is a handle again.** The margin beside the column and the empty ground of the wall, the Timelapse and the sidebar drag the window — at no cost until a press lands. [Small delights.](https://docs.glassine.ink/reference/small-delights)
- **Lighter keystrokes.** The editor stopped copying the whole document several times per keystroke, the page beside the editor renders off the main thread once typing pauses, and the settings are no longer rewritten while you write or drag an edge.

## 0.2.29 — October 19, 2026

- **Tables are tables.** A pipe table is drawn as a grid now — a border, a line under every row and at every column, the header on a faint fill — never wider than the page, with a long cell wrapping under its own column. `/table 3x4` starts one at any size. [Tables.](https://docs.glassine.ink/editor/tables)
- **Smart dashes keep off the separator.** Type `| --- | --- |` and the hyphens stay hyphens; a separator that arrived as `| — | — |` reads as a table anyway, and a paste straightens it.
- **A paste knows a table of tabs.** A spreadsheet selection becomes a pipe table; a paste of several lines lands on lines of its own; text dragged in from another app is read like a paste. And a pasted heading keeps its room above with the syntax hidden, which it used to lose until the caret visited it.
- **Closing pages.** ⌥⌘W closes every page but this one, ⌥⇧⌘W all of them; the fanned cards have a × and the footer's pips a right-click menu. [Pages.](https://docs.glassine.ink/library/pages#closing-pages)
- **A quieter icon.** The Dock icon is the app's own glass again, now in the look it comes with: Midnight over Soft Sky, the g in paper-white on it.

## 0.2.28 — October 17, 2026

- **Arrange the wall by hand.** Pick up a card in All Documents and carry it: the wall makes room with a spring, and where you let go is where it stays. That becomes *Your order* — one order for the whole library, the sidebar's folders included. [All Documents.](https://docs.glassine.ink/library/all-documents#your-order)
- **All Documents comes up at once.** On a library of ninety documents the wall took a second and a half to appear; it takes a tenth of one now. Each card used to set every line of its preview as a view of its own, under a shadow that drew the whole card again.
- **Lighter under motion.** The window no longer works out, on every frame of every animation, where it could be dragged by. It is dragged by its top edge now, the way a window is; the glass itself is no longer a handle.

## 0.2.27 — October 16, 2026

- **One setting for how it looks.** Settings → Look is the whole of it now: eight looks as tiles, and under them the makings of the one on screen — the page's colours and glass, and the folds (or the desktop) behind it. Duplicate a built-in look and change anything; a look of yours is edited in place. [Looks.](https://docs.glassine.ink/appearance/looks)
- **No more freezes.** Glassine no longer waits on the disk from its main thread — not after a save, a sync or a switch of page — so iCloud or another app being slow with the library can't hold the window. If it ever stalls for a second anyway, it writes down why, in ~/Library/Logs/Glassine.

## 0.2.26 — October 16, 2026

- **Looks.** The theme and what lies behind the glass are one setting now — a *look* — with eight built in and Soft Sky, deep and quiet, the one the app comes with. Save whatever the page is wearing under a name, and export it as one file, theme and backdrop inside, for another Mac or another person. [Looks.](https://docs.glassine.ink/appearance/looks)
- **A tour you do.** The first launch asks for one key at a time — [[⌘1]], [[⌘2]], Esc, [[⌘↩]], [[⌥⇥]] — on the real page, and lights up when you have pressed it. About a minute, nothing to read. Help → Tour of Glassine.
- **The Timelapse, by day and by key.** [[⇥]] switches it from the daily notes alone to everything written each day; ↑ ↓ walk the days, ↩ opens one, Esc goes to All Documents and Esc there comes back. A day in the sidebar's calendar opens that day's wall.
- **The fanned pages, refined.** The pointer moves the highlight, a click or ↩ opens, 1–9 jump, and the pips in the footer show a picture of their page when the pointer rests on one.

## 0.2.25 — October 14, 2026

- **⌃Tab too.** Hold ⌃ and press Tab and the open pages fan out, the same as ⌥Tab; ⇧ steps back. Whichever you held, letting it go opens the page.
- **A long page comes up at once.** Switching to a document of a few thousand words took seconds; the editor was laying the text out over and over, from inside its own measurement. It no longer does.

## 0.2.24 — October 14, 2026

- **A tour, the first time.** Eight cards over the page: what Glassine is, and the backdrop, theme, type, caret and modes chosen on the spot. Help → Tour of Glassine brings it back.
- **Open pages.** A document stays open until you close it ([[⌘W]]). No tabs: hold ⌥ and press Tab, and the open pages fan out across the window; let go to open one. A tap flips to the page before. [How it works.](https://docs.glassine.ink/library/pages)
- **Tables.** A pipe table reads as a table in the editor — columns lined up in any font, hairlines where the pipes are, the header in bold — and Tab moves between its cells. `/table` starts one.
- **A paste keeps its shape.** Lists keep their bullets and numbers, headings their level, bold and links their marks, tables their columns — written as Markdown, from whatever app it came from. [[⌥⇧⌘V]] pastes the plain string as it is.

## 0.2.23 — October 13, 2026

- **Move to Trash asks first.** [[⌘⌫]] names the document and waits: Return moves it, Esc keeps it, and [[⌘Z]] still puts it back.

## 0.2.22 — October 12, 2026

- **The page holds still while the sidebar comes and goes.** Showing or hiding the sidebar, even quickly, no longer makes the text jump: the line you are on stays where it is while the column finds its width.
- **A new document is not a daily note.** [[⌘N]] after writing in a day's note used to file the new document under Daily. It now goes to the top of the library.
- **`---` is a rule the moment it is typed.** The third hyphen draws the rule and drops the caret to the line under it. No Return.
- **Eight more Review styles.** Reader, Gallery, Newspaper, Typewriter, Notebook, Thesis, Verse and Blueprint join the six — fourteen ways to see the page. [All of them.](https://docs.glassine.ink/review/review#styles)
- **A rule stays a rule.** Clicking on a horizontal rule no longer turns it back into three dashes.

## 0.2.21 — September 26, 2026

- **⌘3 and ⌘D are today's note.** The third row in the sidebar is now *Today* — the day's note, started for you if it has none — and ⌘D goes there too. Timelapse keeps ⌘2; New Document keeps ⌘N.
- **The search bar lands cleanly.** Esc sends the ⌘F bar back to its spot in the header without the jump to the middle of the window it made as it went; the command bar no longer refills its list as it fades.
- **Two small things put right.** A new daily note starts on the line under its heading, not two below; Editorial's first paragraph is set like the rest, not as a standfirst.

## 0.2.20 — September 25, 2026

- **The icon is the glass.** The app's icon now shows its own window — Dusk over the Aurora backdrop — with the wordmark's g on it.
- **The library watches its folder.** A file that lands in it — from a sync, another app, the Finder — is in the sidebar within a moment. There is no longer a three-second poll behind the tree.
- **Lighter under the hood.** Documents are found by an index, the sidebar's lists and the calendar's month are worked out once rather than on every redraw, and a long document is counted off the main thread when it opens.

## 0.2.19 — September 25, 2026

- **The month in the sidebar.** A calendar under the top rows, one cell a day, shaded by how much of that day's note there is — deepening under today's as you write. Click a day for its note. [How it reads.](https://docs.glassine.ink/library/sidebar#the-calendar)
- **Drag the rows into order.** Pick up a document in the tree and carry it: the rows step aside, the row glides into place, and the order holds as *Your order*. Drop it on a folder to move it there.
- **⌘→ stops at the end of the line.** With the syntax hidden, a line followed by a task, a heading or a quotation sent the caret to the start of that next line, and [[⌘⇧→]] selected into it. Both now stop where the line ends.
- **A quotation ends where its `>` lines end, and a list where its items end.** In Review the paragraph after a quote, or after a task, no longer sits inside it; the page draws what the editor draws.
- **The page beside the editor.** [[⌘⇧↩]] keeps Review to the right of the text: the same page, in the same style, redrawn in place as you write and scrolling to the paragraph you are in. Drag the hairline to share the width.

## 0.2.18 — September 21, 2026

- **⌘→ stops at the end of the line.** With the syntax hidden, a line followed by a task, a heading or a quotation sent the caret to the start of that next line, and [[⌘⇧→]] selected into it. Both now stop where the line ends.
- **A quotation ends where its `>` lines end, and a list where its items end.** In Review the paragraph after a quote, or after a task, no longer sits inside it; the page draws what the editor draws.
- **The page beside the editor.** [[⌘⇧↩]] keeps Review to the right of the text: the same page, in the same style, redrawn in place as you write and scrolling to the paragraph you are in. Drag the hairline to share the width.
- **Sync with GitHub.** The library kept in a private repository of yours, for a second Mac you'd rather not sign into iCloud on — and a history of every note, every version. No git, no daemon; connect with a token in Settings → Library. [How it works.](https://docs.glassine.ink/library/sync)
- **On the Mac App Store**, as Glassine Writer. The direct download stays, and updates itself.

## 0.2.17 — September 19, 2026

- **A quotation ends where its `>` lines end, and a list where its items end.** In Review the paragraph after a quote, or after a task, no longer sits inside it; the page draws what the editor draws.
- **The page beside the editor.** [[⌘⇧↩]] keeps Review to the right of the text: the same page, in the same style, redrawn in place as you write and scrolling to the paragraph you are in. Drag the hairline to share the width.
- **A Welcome page for the app as it is.** The document a first launch opens now tours the backdrop behind the page, the bar over a selection and the slash menu, chips, hiding the syntax, Timelapse, the command bar, Review, Settings and sync — with every key checked. And it opens from its heading, not its end.
- **Sync with GitHub.** The library kept in a private repository of yours, for a second Mac you'd rather not sign into iCloud on — and a history of every note, every version. No git, no daemon; connect with a token in Settings → Library. [How it works.](https://docs.glassine.ink/library/sync)
- **Settings, remade.** A rail of sections, a search box that finds any setting by name, [[⌘Z]] to take a change back, and the Type and Caret sections showing what they do before you look behind the card.
- **On the Mac App Store**, as Glassine Writer. The direct download stays, and updates itself.

## 0.2.16 — September 19, 2026

- **The page beside the editor.** [[⌘⇧↩]] keeps Review to the right of the text: the same page, in the same style, redrawn in place as you write and scrolling to the paragraph you are in. Drag the hairline to share the width.
- **A Welcome page for the app as it is.** The document a first launch opens now tours the backdrop behind the page, the bar over a selection and the slash menu, chips, hiding the syntax, Timelapse, the command bar, Review, Settings and sync — with every key checked. And it opens from its heading, not its end.
- **Aurora from the first launch.** A new copy opens with folds of the theme's own colours behind the glass, the way the pictures look; the desktop's blur is a tile away.
- **Sync with GitHub.** The library kept in a private repository of yours, for a second Mac you'd rather not sign into iCloud on — and a history of every note, every version. No git, no daemon; connect with a token in Settings → Library. [How it works.](https://docs.glassine.ink/library/sync)
- **Settings, remade.** A rail of sections, a search box that finds any setting by name, [[⌘Z]] to take a change back, and the Type and Caret sections showing what they do before you look behind the card.
- **On the Mac App Store**, as Glassine Writer. The direct download stays, and updates itself.

## 0.2.15 — September 18, 2026

- **The page is back in the middle.** After the sidebar came or went, the column of text could sit to one side of the window; it is centred again, whatever the sidebar does.
- **A Welcome page for the app as it is.** The document a first launch opens now tours the backdrop behind the page, the bar over a selection and the slash menu, chips, hiding the syntax, Timelapse, the command bar, Review, Settings and sync — with every key checked. And it opens from its heading, not its end.
- **Aurora from the first launch.** A new copy opens with folds of the theme's own colours behind the glass, the way the pictures look; the desktop's blur is a tile away.
- **Sync with GitHub.** The library kept in a private repository of yours, for a second Mac you'd rather not sign into iCloud on — and a history of every note, every version. No git, no daemon; connect with a token in Settings → Library. [How it works.](https://docs.glassine.ink/library/sync)
- **Settings, remade.** A rail of sections, a search box that finds any setting by name, [[⌘Z]] to take a change back, and the Type and Caret sections showing what they do before you look behind the card.
- **On the Mac App Store**, as Glassine Writer. The direct download stays, and updates itself.

## 0.2.14 — September 17, 2026

- **A Welcome page for the app as it is.** The document a first launch opens now tours the backdrop behind the page, the bar over a selection and the slash menu, chips, hiding the syntax, Timelapse, the command bar, Review, Settings and sync — with every key checked. And it opens from its heading, not its end.
- **Aurora from the first launch.** A new copy opens with folds of the theme's own colours behind the glass, the way the pictures look; the desktop's blur is a tile away.
- **Sync with GitHub.** The library kept in a private repository of yours, for a second Mac you'd rather not sign into iCloud on — and a history of every note, every version. No git, no daemon; connect with a token in Settings → Library. [How it works.](https://docs.glassine.ink/library/sync)
- **Settings, remade.** A rail of sections, a search box that finds any setting by name, [[⌘Z]] to take a change back, and the Type and Caret sections showing what they do before you look behind the card.
- **Caret tricks.** Left alone for a few seconds, the caret hops, bounces, flips, wiggles, stretches or leans — every shape performs. Off in a switch, and under Reduce Motion.
- **On the Mac App Store**, as Glassine Writer. The direct download stays, and updates itself.

## 0.2.13 — September 16, 2026

- **Aurora from the first launch.** A new copy opens with folds of the theme's own colours behind the glass, the way the pictures look; the desktop's blur is a tile away.
- **A light theme over a backdrop keeps its quiet grey.** Paper's marks, a task's box and a finished task's text lean toward the text colour over the folds, instead of fading into them.
- **Sync with GitHub.** The library kept in a private repository of yours, for a second Mac you'd rather not sign into iCloud on — and a history of every note, every version. No git, no daemon; connect with a token in Settings → Library. [How it works.](https://docs.glassine.ink/library/sync)
- **Settings, remade.** A rail of sections, a search box that finds any setting by name, [[⌘Z]] to take a change back, and the Type and Caret sections showing what they do before you look behind the card.
- **Caret tricks.** Left alone for a few seconds, the caret hops, bounces, flips, wiggles, stretches or leans — every shape performs. Off in a switch, and under Reduce Motion.
- **On the Mac App Store**, as Glassine Writer. The direct download stays, and updates itself.

## 0.2.12 — September 16, 2026

- **A light theme over a backdrop keeps its quiet grey.** Paper's marks, a task's box and a finished task's text lean toward the text colour over the folds, instead of fading into them.

## 0.2.11 — September 13, 2026

- **Sync with GitHub.** The library kept in a private repository of yours, for a second Mac you'd rather not sign into iCloud on — and a history of every note, every version. No git, no daemon; connect with a token in Settings → Library. [How it works.](https://docs.glassine.ink/library/sync)
- **Settings, remade.** A rail of sections, a search box that finds any setting by name, [[⌘Z]] to take a change back, and the Type and Caret sections showing what they do before you look behind the card.
- **Caret tricks.** Left alone for a few seconds, the caret hops, bounces, flips, wiggles, stretches or leans — every shape performs. Off in a switch, and under Reduce Motion.
- **Backdrops of your own.** Nine sets of colour behind the glass now, each running through more than one colour; duplicate any and make it yours, with a paper grain of its own.
- **On the Mac App Store**, as Glassine Writer. The direct download stays, and updates itself.

## 0.2.8 — September 12, 2026

- **Formatting as you go.** A bar over any selection; a slash menu at the start of a line; chips; hide the Markdown syntax except in the sentence being written.
- **Open With.** Finder can open `.md` and `.txt` files in Glassine; a file from outside the library is edited where it is.
- **Backdrops.** Folds of colour inside the window instead of the desktop, drifting, frosted to taste.

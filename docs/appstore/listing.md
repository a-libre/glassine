# App Store listing — Glassine Writer

Everything on the App Store Connect version page, ready to paste. Limits are
Apple's; the counts are checked by `docs/appstore/check.py`.

## Name (30)

Glassine Writer

## Subtitle (30)

The quietest way to write

## Promotional text (170)

A quiet place to write. Markdown, iCloud, nothing in the way — with a caret that glides, typewriter scrolling, and a Daily view for the notes you take every day.

## Description (4,000)

Glassine is a writing app for people who want the screen to get out of the way.

It opens to your words on a sheet of translucent glass, saves as you type, and keeps every document as a plain Markdown file in iCloud Drive — readable anywhere, on every Mac you own.

WRITING
• A caret that glides between positions instead of jumping
• Typewriter scrolling keeps the line you're writing where your eyes already are
• Focus mode dims everything but the paragraph you're in
• Light Markdown styling as you type: headings, emphasis, links, quotes, code
• Nested lists with Tab and Shift-Tab; numbered lists renumber themselves
• Tasks you can check off. Finished ones settle to the bottom of their list, and come back when you uncheck them
• Drag a bullet or a checkbox to reorder a list
• Undo reaches everything, including a document you created by accident

YOUR LIBRARY
• Documents live in a Glassine folder in iCloud Drive, visible in Finder and synced to your other Macs — or in any folder you choose
• Folders, tags (#like-this), starred documents and recents in a sidebar that hides when you want the room
• All Documents lays your writing out as a wall of cards
• Search looks inside every document, not just at titles
• A Daily view: today's note is one keystroke away, and past days recede behind it in a timeline
• @today, @yesterday and @tomorrow turn into dates as you type

REVIEW
• Command-Return shows the finished page in one of five styles: Glass, GitHub, Book, Editorial or Mono
• Check tasks off right there
• Export to PDF, or copy the whole document as Markdown or rich text with one shortcut

MADE TO BE YOURS
• Themes: Ocean by default, a light and dark pair that follows the system, and an editor for making your own
• Choose the font and size, the caret's width and speed, how much focus mode dims, whether headings center
• Every shortcut on one sheet (Command-/), and a command bar (Command-K) for everything else

Glassine is open source under the MIT license: github.com/a-libre/glassine

Requires macOS 14 or later.

## Keywords (100)

markdown,notes,daily,editor,minimal,focus,typewriter,distraction free,plain text,journal,icloud

## Support URL

https://github.com/a-libre/glassine/issues

## Marketing URL

https://github.com/a-libre/glassine

## Copyright (200)

2026 Alex Libre

## Version

Must equal the build's CFBundleShortVersionString, which `./appstore.sh X.Y.Z`
sets. Build with the version you want to see on the store page.

## Screenshots

Apple accepts 1280×800, 1440×900, 2560×1600 or 2880×1800, no alpha channel.
`docs/appstore/screenshots.sh` runs the sandboxed build and captures them.

## Elsewhere in App Store Connect

- App Information → Privacy Policy URL: https://github.com/a-libre/glassine/blob/main/PRIVACY.md
- App Information → Category: Productivity
- App Privacy: Data Not Collected (no analytics, no accounts; the App Store
  build has no network entitlement at all; iCloud sync is Apple's, on the
  user's own account — see PRIVACY.md)
- Age Rating: answer None to everything → 4+
- Pricing: your call
- App Review → Sign-in required: No
- Export compliance: Info.plist sets ITSAppUsesNonExemptEncryption to false,
  so the question is answered at upload and never asked

# App Review notes — Glassine Writer

The replies to App Review, newest first, and the text for the version page's
App Review Information → Notes field. All ready to paste.

## Reply to the September 12 rejection (Guideline 4 — no Quit in the app menu; build 10 reviewed)

Hello,

Thank you for the review. You are right: build 10 had no Quit item, and no application menu to speak of. The change that added the Window → Glassine item for the previous note (Guideline 4, reopening the window) used SwiftUI's `commandsRemoved()` on the window scene, which removes the standard menus along with the scene's own item — the application menu's Quit, Hide and Hide Others, and the Edit menu's Undo, Cut, Copy, Paste and Select All, with their shortcuts. I found the defect the day after uploading build 10 and it is fixed in build 0.2.3 (17), attached to this submission, which replaces the scene's item alone and leaves the standard menus in place.

In build 17 the Glassine menu has About, Settings…, Services, Hide Glassine, Hide Others, Show All and Quit Glassine (⌘Q); the Edit menu has Undo, Redo, Cut, Copy, Paste, Delete and Select All; the Window menu has Minimize, Zoom and Glassine (which brings the window back after it has been closed, the previous note). I verified each item by reading the running app's menu bar.

The earlier points still hold in this build: the iCloud Drive and Documents-folder permission prompts say what the app does with the folder and give an example; the window reopens from Window → Glassine, from the Dock icon and from any command that needs it. Build 17 also carries the small features and fixes released to the direct-download version since (an optional coloured backdrop inside the window, a caret that does small animations while idle, ⌘Z inside Settings, and a fix for keystrokes being delayed after the window had been covered) — none of which change permissions, entitlements or data handling. No sign-in, no external services; the outgoing-connection entitlement is for WebKit only.

Alex Libre

## Reply to the September 9 rejection (5.1.1(ii) purpose strings; Guideline 4 window) — superseded by the reply above; build 10 went in with it and was itself defective

Hello,

Thank you for the review. Both points are addressed in build 0.2.3 (13), which is attached to this submission.

Guideline 5.1.1(ii) — purpose strings. The iCloud Drive prompt now explains what the app does with the folder and gives an example. The string reads: "Glassine keeps every document you write as a Markdown file in a Glassine folder in iCloud Drive, so your writing syncs to your other Macs and stays yours as plain files. It reads that folder to list your documents in the sidebar and writes to it as you type — for example, when you open the app it lists the notes in the folder, and when you edit one, the change is saved to that note's file." The Documents-folder string, used when iCloud Drive is off, was rewritten in the same way.

Guideline 4 — reopening the window. The app keeps running when its window is closed, and there is now a Window → Glassine menu item that brings the window back. Clicking the Dock icon does the same, and so do the commands that need a window — File → New Document, View → All Documents, View → Timelapse, View → Search Library, and Settings — each of which reopens the window before acting.

Otherwise this build holds a few small features added since the last one (an optional coloured backdrop inside the window, a caret that does small animations while idle, ⌘Z inside Settings) and no changes to permissions, entitlements or data handling. The earlier answers (no sign-in, no external services, the outgoing-connection entitlement only for WebKit) still hold.

Alex Libre

(Build 10, packaged on September 10 for this reply, was the one reviewed on September 12 and was rejected for the missing Quit item: a change made for the Guideline 4 fix had removed the standard Edit and application menus. Builds 13 and 17 have them back; 17 is the one to submit.)

## Reply to the September 5 request (Guideline 2.1 – Information Needed – New App Submission)

The screen recording was attached to this reply.

## Reply to App Review

Hello,

Thank you for the review. Here are the six items, in order.

1. Screen recording

Attached is a recording made on a MacBook Pro running macOS [version from About This Mac], beginning with launching the app. It shows the typical flow: the window opening on the welcome document, writing with autosave, creating a new document, All Documents, Timelapse, Review, and Settings. The app has no account, sign-in, purchase, subscription or content-sharing flow, so none appears.

2. Purpose and audience

Glassine Writer is a Markdown writing app for the Mac. The user types in one window, and every document is saved as they type as a plain .md text file, in a folder the app keeps in the user's own iCloud Drive (the app's iCloud container) or in any local folder they choose. It is for anyone who writes on a Mac — notes, drafts, journals, a note for each day. There is no social component, no content from other users, and nothing to buy.

3. Setup and access

There is nothing to set up. Launching the app creates its library folder and opens a welcome document. No credentials, accounts or sample files are needed. The main features:

- Type in the open document; it saves itself.
- ⌘N makes a new document. Making two or three and typing a line in each gives the library views something to show.
- ⌘1, or the All Documents row in the sidebar, shows every document as cards.
- ⌘2 shows Timelapse, the view of daily notes; ⌥⌘D creates today's note.
- ⌘Return opens Review, a rendered view of the current document; ⌘⇧E exports it as a PDF.
- ⌘, opens Settings (themes, typography, behaviour).
- ⌘K opens the command bar; ⌘/ lists every shortcut.

If the review Mac is not signed in to iCloud, the app keeps its library in a local folder instead and works the same.

4. External services

None. The app uses no third-party SDKs, analytics, advertising, crash reporting, authentication, payment, AI or data providers, and makes no network requests of its own. It relies on two Apple technologies: iCloud Drive (CloudDocuments, in the app's own container, under the user's Apple Account) for the default library folder, and WebKit (WKWebView) to render the Review pane from HTML the app generates locally. The outgoing-connection entitlement is present only because WebKit's content process requires it to start inside the App Sandbox. A link the user writes into a document opens in their default browser when clicked in Review.

5. Regional differences

None. The app behaves the same in every country and region. It is in English only.

6. Regulated industries and third-party material

Not applicable. The app is a general-purpose text editor: all content is the user's own text, it contains no licensed or third-party material, and it is not in a regulated industry. The source is public under the MIT license at https://github.com/a-libre/glassine; the manual is at https://docs.glassine.ink and the privacy policy at https://glassine.ink/privacy.

Please let me know if anything else would help.

Alex Libre

## App Review Information → Notes

Glassine Writer is a Markdown writing app for the Mac: one window, documents saved as plain .md files as you type, in the app's iCloud Drive container or a local folder of the user's choosing. For anyone who writes on a Mac. No account, sign-in, purchase, subscription or content sharing.

SETUP: none. Launching creates the library and opens a welcome document. No credentials or sample files needed. If the Mac is not signed in to iCloud, a local folder is used and everything works the same.

MAIN FEATURES: type and it saves. ⌘N new document. ⌘1 All Documents (every document as cards). ⌘2 Timelapse (daily notes); ⌥⌘D today's note. ⌘Return Review (rendered view); ⌘⇧E export as PDF. ⌘, Settings. ⌘K command bar. ⌘/ every shortcut.

EXTERNAL SERVICES: none. No third-party SDKs, analytics, ads, crash reporting, authentication, payments, AI or data providers; no network requests of the app's own. Uses iCloud Drive (CloudDocuments, own container, user's Apple Account) for the default library, and WKWebView to render the Review pane from locally generated HTML — the network.client entitlement exists only because WebKit's content process requires it inside the sandbox.

REGIONAL DIFFERENCES: none; English only.

REGULATED INDUSTRY / THIRD-PARTY MATERIAL: not applicable. General-purpose text editor; all content is the user's own. Open source (MIT): https://github.com/a-libre/glassine. Manual: https://docs.glassine.ink. Privacy policy: https://glassine.ink/privacy.

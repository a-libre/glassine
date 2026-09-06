# App Review notes — Glassine Writer

The reply to Apple's *Guideline 2.1 – Information Needed – New App Submission*
message (September 2026), and the text for the version page's App Review
Information → Notes field. Both are ready to paste; the screen recording is
attached to the reply.

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

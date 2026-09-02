# Releasing Glassine

How a signed, notarized build gets from this folder to a download link. Everything here happens on the Mac that has the Developer ID certificate.

## One-time setup (after the Apple Developer Program membership is active)

1. **Certificate.** Open Xcode → Settings → Accounts. Add your Apple ID if it isn't there, select the team, click *Manage Certificates…*, then **+** → *Developer ID Application*. Xcode creates the certificate and puts it in your keychain. Check with:

   ```bash
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

2. **Notarization credentials.** Notarization is an automated Apple service that scans the build for malware and returns a ticket; without it macOS refuses to open downloaded apps. It needs an *app-specific password*, not your real one: create it at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords. Your Team ID is on [developer.apple.com/account](https://developer.apple.com/account) under Membership Details. Then store the credentials in the keychain once:

   ```bash
   xcrun notarytool store-credentials "glassine-notary" --apple-id you@example.com --team-id YOURTEAMID
   ```

   It prompts for the app-specific password and never asks again.

3. **GitHub CLI (optional, recommended).** Lets the script publish the release itself:

   ```bash
   brew install gh && gh auth login
   ```

   Without it, the script prints the link to create the release by hand and you attach the `.dmg`.

## Every release

```bash
./release.sh 0.2.0
```

That does, in order: refuses to run with uncommitted changes; writes the version into `Info.plist` and bumps the build number; builds; signs with hardened runtime and a secure timestamp; submits the app to Apple's notary service and waits (usually 2–10 minutes); staples the ticket to the app; builds `dist/Glassine-0.2.0.dmg` with an Applications shortcut; signs, notarizes and staples the disk image too; commits, tags `v0.2.0`, pushes; and creates the GitHub Release with the `.dmg` attached.

`./release.sh 0.2.0 --dry-run` does everything except push and publish, so you can open the `.dmg` and try it first.

## What users see

They download the `.dmg`, drag Glassine to Applications, and it opens with no warnings. The app checks GitHub Releases once a day (Help → Check for Updates… does it on demand) and offers the download when a newer version exists. Settings → General turns the automatic check off.

## Versioning

Use three numbers. Bump the last for fixes (0.1.1), the middle for features (0.2.0), the first when it's a different app (1.0.0). Tags are `v` + version. The GitHub Release notes are generated from commit messages, so write those for people.

## If notarization fails

`xcrun notarytool log <submission-id> --keychain-profile glassine-notary` prints the reasons. The usual ones are a missing `--timestamp`, a binary without hardened runtime, or an expired certificate. The script already handles the first two.

## The App Store

The same source, built a second way: `./build.sh --appstore` compiles with `APPSTORE` set, which turns on the App Sandbox and leaves out the GitHub update check (the store handles updates). The store listing is called **Glassine Writer** because plain "Glassine" was already reserved in App Store Connect; the app itself is still Glassine everywhere.

### What the sandbox changes

- **Where documents live.** A sandboxed app cannot read `~/Library/Mobile Documents` directly, so the store build gets its own iCloud container, `iCloud.com.alexlibre.glassine`. Its Documents folder shows up in iCloud Drive as a **Glassine** folder with the app's icon, syncs the same way, and is the default library. When iCloud Drive is off, the library falls back to the sandbox's own Documents folder.
- **Custom folders.** Settings → Library → *Change…* still works: the open panel's permission is kept as a security-scoped bookmark (`libraryBookmark` in settings), so the folder stays reachable on the next launch. Someone moving from the direct download can point the store build at their old `iCloud Drive/Glassine` folder this way and carry on.
- **Trash.** Deleting still tries the macOS Trash first; if the sandbox refuses (it can, for iCloud container files), the item goes to a hidden `.Trash` folder inside the library, which still syncs and still undoes.
- **Old Pyrus settings and folder** are not migrated in the store build (it cannot see them).

`Distribution.swift` is where all of this is decided at run time.

### One-time setup

1. **App ID with iCloud.** developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `com.alexlibre.glassine` → tick **iCloud**, click *Configure*, and create (or assign) the container **`iCloud.com.alexlibre.glassine`**. Save.
2. **Certificates.** Xcode → Settings → Accounts → Manage Certificates → **+** → *Apple Distribution*, then **+** → *Mac Installer Distribution*. (Both are separate from the Developer ID certificate the direct download uses.)
3. **Provisioning profile.** developer.apple.com → Profiles → **+** → *Mac App Store Connect* → App ID `com.alexlibre.glassine` → the Apple Distribution certificate → name it "Glassine App Store" → download. Save it as `Resources/Glassine-AppStore.provisionprofile` (git-ignored). The iCloud entitlement needs this; without it the app would be killed at launch.
4. **App Store Connect record.** appstoreconnect.apple.com → My Apps → **+** → macOS, name *Glassine Writer*, bundle ID `com.alexlibre.glassine`, SKU `glassine-mac-1`. Fill in the listing later (screenshots at 1280×800 or 2560×1600, a description, the category Productivity, a support URL — the GitHub repo works — and a privacy policy URL; the app collects nothing, so a one-line page saying so is enough).
5. **Transporter.** Install it from the App Store (Apple's, free). It is what uploads the package.

### Every store release

```bash
./appstore.sh 0.2.0
```

That bumps the version and build number, builds the sandboxed flavor, embeds the provisioning profile, signs with Apple Distribution and the real Team ID, verifies the entitlements, builds `dist/Glassine-0.2.0-AppStore.pkg` signed with the installer certificate, commits the version bump, and opens Transporter with the package. In Transporter: sign in, *Deliver*. Then in App Store Connect: TestFlight to try it on your own Mac first, or add the build to the version and *Submit for Review*.

`./appstore.sh 0.2.0 --dry-run` builds and packages without committing.

To try the sandboxed flavor without any of the signing: `./build.sh --appstore --run`. It is ad-hoc signed, so there is no iCloud container — the library lands in `~/Library/Containers/com.alexlibre.glassine/Data/Documents` — but everything else behaves as the store build will.

### Review notes worth knowing

- The direct download and the store build store documents in different places (`iCloud Drive/Glassine` vs the app's own iCloud folder). They can be pointed at the same folder through Settings → Library, but do not run both at once against it.
- Both builds bump the same `CFBundleVersion`; App Store Connect only insists it goes up.
- Reviewers get a sandboxed Mac with iCloud possibly off. The local Documents fallback covers that; the welcome document appears there.

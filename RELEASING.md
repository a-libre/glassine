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

## Later: the App Store

Same code, different container. The App Store requires the App Sandbox, which means replacing direct access to `~/Library/Mobile Documents/…` with an iCloud container entitlement (the app gets its own folder that still shows in iCloud Drive) and a security-scoped bookmark for custom library folders. About a day of work; not needed for the download route.

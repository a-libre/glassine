# Privacy Policy

Glassine collects nothing.

There are no accounts, no analytics, no crash reporting, no advertising, and no
servers of ours. What you write stays on your Mac, in plain Markdown files you
can see in Finder.

## iCloud

If you keep your library in iCloud Drive, your documents sync through your own
iCloud account under Apple's terms, exactly as any file in iCloud Drive does.
Glassine never sees them in transit and has no way to. Apple's iCloud privacy
terms: https://www.apple.com/legal/privacy/

The Mac App Store version of Glassine runs in the App Sandbox. It holds the
sandbox's permission for outgoing connections only because Review, which draws
the page with the system's web view, cannot start without it. The app never
opens a connection of its own, and there is nothing it would send.

## Checking for updates (direct download only)

The version downloaded outside the App Store updates itself with Sparkle, an
open-source framework. Once a day it fetches a small file, the update feed,
from glassine.ink. That request carries the version of Glassine you are
running and, like any web request, your IP address; Sparkle's option to send
a profile of your Mac is off, and Glassine has no server that would keep
anything about the request. When a newer version exists, the disk image is
downloaded from GitHub, whose privacy statement covers that download:
https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement

Nothing about your documents, your library, or how you use the app is ever
sent.

## Changes

If this ever changes, the change will appear here first, in the same repository
as the code that does it.

## Contact

Open an issue at https://github.com/a-libre/glassine/issues.

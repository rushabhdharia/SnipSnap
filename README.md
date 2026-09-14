# SnipSnap

A Windows-style clipboard history for macOS. Runs in the background, records
every text copy and screenshot, and drops a small floating panel next to the
cursor when you press **⌘⌃V** (Command–Control–V). Pick an item and it pastes
straight into whatever app you were using.

## Features

- **Text + images** in one history — screenshots show as thumbnails.
- **⌘⌃V** opens the panel near the pointer, over fullscreen apps too.
- **Type to search**, `↑`/`↓` to move, `Return` to paste, `Esc` to dismiss.
- `⌘1`–`⌘9` paste the Nth row; `⌘P` pins/unpins the selected row.
- **Pin** items (📌) so they stay put — pinned items are never trimmed.
- Auto-paste into the previous app (needs Accessibility; falls back to
  copy-only, so you just press `⌘V` yourself).
- History and images persist across restarts, capped at 200 unpinned items.
- Password managers that mark clips as concealed are skipped automatically.
- Menu bar icon: **Show SnipSnap**, **Clear History…**, **Quit**. No Dock icon.

## Install

### Homebrew (once published — see [Distribution](#distribution))

```sh
brew tap rushabhdharia/snipsnap
brew install --cask snipsnap
```

### From source

Needs only the Command Line Tools (`xcode-select --install`) — no Xcode.

```sh
./make.sh
```

This builds a release binary, wraps it in `SnipSnap.app`, ad-hoc signs it,
installs to `/Applications`, and launches it. Then press **⌘⌃V**.

```sh
./make.sh --no-install   # just build the bundle into ./build
./make.sh -y             # replace an existing install without asking
```

On first launch macOS asks for **Accessibility** permission (System Settings ▸
Privacy & Security ▸ Accessibility). Grant it so items paste automatically.
Until then the app still works — selecting an item puts it on the clipboard and
you press `⌘V`.

## Development

```sh
swift build                 # debug build of the app
swift run SnipSnap         # run it straight from the package
swift run SnipSnapChecks   # run the store/persistence test suite
```

`SnipSnapChecks` is a dependency-free test runner (XCTest isn't available
without Xcode). It covers dedup, retention, the pin guarantee, JSON
round-tripping, sidecar self-healing, and image storage.

### Layout

| Path | Role |
|---|---|
| `Sources/SnipSnap/` | executable shell — just `main.swift` |
| `Sources/SnipSnapCore/HotKey/` | Carbon global hot key (needs no permission to register) |
| `Sources/SnipSnapCore/Pasteboard/` | `SnipSnapMonitor` (pasteboard polling) + `Paster` (write + synthetic ⌘V) |
| `Sources/SnipSnapCore/Store/` | `HistoryStore` — dedup, retention, persistence; `ImageUtil` thumbnails |
| `Sources/SnipSnapCore/UI/` | `NSPanel` + SwiftUI history view |
| `Sources/SnipSnapChecks/` | test runner |

State lives in `~/Library/Application Support/SnipSnap/` (`index.json` plus
`images/` and `text/` sidecars).

## Distribution

The app is ad-hoc signed (`codesign --sign -`), not notarized — there's no
paid Apple Developer Program membership behind it. That's fine for building
and running locally, but a plain zip handed to someone else hits Gatekeeper's
"cannot be opened because the developer cannot be verified." Sharing via a
personal Homebrew tap works around this cleanly: Homebrew's own download
doesn't set the browser quarantine flag the way Safari does, and the cask's
`postflight` block clears it explicitly either way, so `brew install --cask`
just works.

Published at [github.com/rushabhdharia/SnipSnap](https://github.com/rushabhdharia/SnipSnap),
with the tap at [github.com/rushabhdharia/homebrew-snipsnap](https://github.com/rushabhdharia/homebrew-snipsnap).

To cut a new release:

```sh
./release.sh 1.1.0
```

This builds, bundles, ad-hoc signs, and zips the app to
`dist/SnipSnap-1.1.0.zip`, printing its sha256. Then:

1. Push this repo, tag `v1.1.0`, and attach the zip as a release asset:
   ```sh
   git tag v1.1.0 && git push origin v1.1.0
   gh release create v1.1.0 dist/SnipSnap-1.1.0.zip --title v1.1.0 --notes "..."
   ```
2. In the `homebrew-snipsnap` repo, bump `version` and `sha256` in
   `Casks/snipsnap.rb` to match, then push. Anyone running
   `brew upgrade --cask snipsnap` picks it up.

If this ever gets wide, non-technical distribution, upgrading to a real
Developer ID + notarized build removes the need for the `postflight`
quarantine workaround and makes a plain downloaded zip work with a normal
double-click, no cask required — that needs an Apple Developer Program
membership ($99/yr).

## Known limitation: Accessibility resets on every rebuild

macOS ties the Accessibility grant to the app's code signature. Ad-hoc signing
produces a new identity each time the binary changes, so after every
`./make.sh` auto-paste silently stops until you remove and re-add the app
under *System Settings ▸ Privacy & Security ▸ Accessibility*. To clear the
stale entry:

```sh
tccutil reset Accessibility com.rushabhdharia.snipsnap
```

This is inherent to unsigned local builds. The copy-only fallback keeps the app
usable in the meantime. A Developer ID signature would make the grant stick.

## Uninstall

```sh
rm -rf /Applications/SnipSnap.app
rm -rf ~/Library/Application\ Support/SnipSnap
tccutil reset Accessibility com.rushabhdharia.snipsnap
```

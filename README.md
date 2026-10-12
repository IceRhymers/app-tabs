# AppTabs

Tabs for every app on your Mac — an open-source window grouper for macOS (a free alternative to Stardock Groupy / Tack).

Group windows from **any** apps under one shared strip of tabs: your editor, terminal and browser working as a single unit.

## Status

Early development (v0.1). Core features:

- Group windows from any app via picker (`⌃⌥⌘G`) or by dragging one window onto another
- Tab strip pinned to the top of the grouped windows
- Click to switch, drag to reorder, drag out to detach
- Named groups, restored on relaunch

## Requirements

- macOS 14 (Sonoma) or later
- Xcode Command Line Tools (`xcode-select --install`) with Swift 6

## Build & Run

```bash
swift build                    # build
swift run AppTabsCoreTests     # run tests (plain harness; CLT has no XCTest)
scripts/bundle.sh              # package build/AppTabs.app
open build/AppTabs.app
```

On first launch AppTabs will ask for **Accessibility permission** (System Settings → Privacy & Security → Accessibility). It uses the Accessibility API to move and arrange other apps' windows — it never reads window contents.

### Signing (so Accessibility permission survives rebuilds)

macOS ties the Accessibility grant to the app's code signature. Ad-hoc-signed builds lose the grant every time you rebuild. To keep it:

1. Open **Keychain Access** → Certificate Assistant → **Create a Certificate…**
2. Name: `AppTabs Dev`, Certificate Type: **Code Signing**
3. Re-run `scripts/bundle.sh` — it will find and use that identity automatically.

## How it works

macOS does not let one app adopt another app's windows (unlike Windows, where Groupy can). So AppTabs draws its own borderless tab strip above your grouped windows and drives the windows themselves through the Accessibility API:

- All windows in a group share the same frame.
- Switching a tab raises that window and activates its app.
- The tab strip follows the active window's frame across displays and Spaces.

## Project layout

```
Sources/AppTabsCore/   Testable core: AX wrappers, window registry, group model, persistence
Sources/AppTabs/       AppKit/SwiftUI app: tab strip, picker, drag-to-group, settings
scripts/bundle.sh      Build + package + sign the .app
```

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

Inspired by [Tack](https://tack.website) and Stardock Groupy. Built with [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts).

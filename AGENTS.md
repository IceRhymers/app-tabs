# Agent notes

- **Build**: `swift build` — but `swift build` alone is not a runnable app; always package with `scripts/bundle.sh` and `open build/AppTabs.app`.
- **Test**: `swift run AppTabsCoreTests` — CLT ships no XCTest/Swift Testing module, so tests are a plain executable assertion harness in `Tests/AppTabsCoreTests` (exit 0 = pass). `swift test` will NOT work here.
- **No Xcode on this machine** — the `.app` is assembled by `scripts/bundle.sh`, not an Xcode project. Keep it that way.
- **Signing**: `scripts/bundle.sh` signs with a self-signed `AppTabs Dev` code-signing identity if present, else ad-hoc. Ad-hoc rebuilds lose the Accessibility grant.
- **Not sandboxed**: the app is not sandboxed and must never be — Accessibility control of other apps' windows requires it.
- **LSUIElement**: the app is a menu-bar app (no Dock icon).
- Package dep: `KeyboardShortcuts` (sindresorhus, MIT) for global hotkeys.
- The private-but-stable `_AXUIElementGetWindow` symbol is used (same as Rectangle/AltTab) to map AXUIElement → CGWindowID.

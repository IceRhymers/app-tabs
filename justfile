# AppTabs — common dev tasks. Run `just` to list available recipes.

# Default: show available recipes
default:
    @just --list

# Build debug
build:
    swift build

# Build release
build-release:
    swift build -c release

# Run the core test harness (CLT has no XCTest; exit 0 = pass)
test:
    swift run AppTabsCoreTests

# Package build/AppTabs.app (release) and sign it
bundle:
    scripts/bundle.sh release

# Package debug build
bundle-debug:
    scripts/bundle.sh debug

# Rebuild, package, and relaunch the app (kills any running instance first)
run: bundle
    #!/usr/bin/env bash
    set -euo pipefail
    pkill -f "AppTabs.app/Contents/MacOS/AppTabs" 2>/dev/null || true
    sleep 1
    open build/AppTabs.app
    sleep 1
    pgrep -f "AppTabs.app/Contents/MacOS/AppTabs" >/dev/null && echo "AppTabs running" || echo "AppTabs failed to start"

# Stop the running app
stop:
    pkill -f "AppTabs.app/Contents/MacOS/AppTabs" || echo "AppTabs not running"

# Remove build artifacts (.build and build/)
clean:
    rm -rf .build build
    @echo "cleaned"

# Full rebuild from scratch: clean, build, test, bundle
rebuild: clean build test bundle

# Open the Accessibility privacy settings (grant/revoke permission)
ax-settings:
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

# Show which signing identity bundle.sh would use
signing:
    @security find-identity -v -p codesigning | grep -m1 "AppTabs Dev" || echo "no 'AppTabs Dev' identity — bundle.sh will ad-hoc sign (Accessibility grant resets on rebuild)"

# Verify the built app's signature
verify-signature:
    codesign -dvv build/AppTabs.app 2>&1 | grep -E "Signature|Identifier|TeamIdentifier"

# Tail app logs (AX failures, save errors)
logs:
    log stream --predicate 'process == "AppTabs"' --level debug

# Format Swift sources (requires swift-format: brew install swift-format)
format:
    swift-format format --in-place --recursive Sources Tests

# Lint without changing files
lint:
    swift-format lint --recursive Sources Tests

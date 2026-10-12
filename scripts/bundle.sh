#!/bin/bash
# Build AppTabs and package it as build/AppTabs.app
# Usage: scripts/bundle.sh [debug|release]
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/build/AppTabs.app"

cd "$ROOT"
echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"

echo "==> packaging AppTabs.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT/.build/$CONFIG/AppTabs" "$APP_DIR/Contents/MacOS/AppTabs"

# Copy KeyboardShortcuts resources if the bundle exists
KS_BUNDLE=$(ls -d "$ROOT/.build/$CONFIG"/KeyboardShortcuts_KeyboardShortcuts.bundle 2>/dev/null || true)
if [ -n "$KS_BUNDLE" ]; then
  cp -R "$KS_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# App icon (optional; generated from Assets if present)
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> signing"
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "AppTabs Dev" | sed -E 's/.*"(.*)"/\1/' || true)
if [ -n "${IDENTITY:-}" ]; then
  codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
  echo "    signed with: $IDENTITY"
else
  codesign --force --deep --sign - "$APP_DIR"
  echo "    ad-hoc signed (Accessibility permission will be lost on rebuild; see README to create an 'AppTabs Dev' identity)"
fi

echo "==> done: $APP_DIR"
echo "    run with: open $APP_DIR"

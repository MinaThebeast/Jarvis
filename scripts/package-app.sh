#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/Jarvis.app"
MACOS="$APP/Contents/MacOS"
RESOURCES="$APP/Contents/Resources"

echo "Building JARVIS (release)..."
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
BINARY="$BIN_DIR/Jarvis"

if [[ ! -x "$BINARY" ]]; then
    echo "error: release binary not found at $BINARY" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BINARY" "$MACOS/Jarvis"
chmod +x "$MACOS/Jarvis"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

echo "Code-signing Jarvis.app..."
codesign --force --deep --sign - --identifier com.stark.jarvis "$APP"

echo "$APP"

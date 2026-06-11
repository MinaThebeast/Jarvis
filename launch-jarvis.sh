#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

LOG="/tmp/jarvis-launch.log"
APP="$DIR/Jarvis.app"
BINARY="$APP/Contents/MacOS/Jarvis"

needs_rebuild() {
    [[ ! -x "$BINARY" ]] && return 0
    find "$DIR/Sources" "$DIR/Info.plist" "$DIR/Package.swift" -type f \
        \( -name "*.swift" -o -name "Package.swift" -o -name "Info.plist" \) \
        -newer "$BINARY" -print -quit | grep -q .
}

if needs_rebuild; then
    echo "$(date -Iseconds) Building latest JARVIS..." >> "$LOG"
    if ! "$DIR/scripts/package-app.sh" >> "$LOG" 2>&1; then
        echo "$(date -Iseconds) Build failed — see $LOG" >> "$LOG"
        osascript -e "display alert \"JARVIS build failed\" message \"Check $LOG for details.\" as critical"
        exit 1
    fi
    echo "$(date -Iseconds) Build complete." >> "$LOG"
else
    echo "$(date -Iseconds) Launching cached Jarvis.app." >> "$LOG"
fi

open "$APP"

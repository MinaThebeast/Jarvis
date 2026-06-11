#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

LOG="/tmp/jarvis-launch.log"
BINARY="$DIR/.build/debug/Jarvis"

needs_rebuild() {
    [[ ! -x "$BINARY" ]] && return 0
    find "$DIR/Sources" "$DIR/Package.swift" -type f \
        \( -name "*.swift" -o -name "Package.swift" \) \
        -newer "$BINARY" -print -quit | grep -q .
}

if needs_rebuild; then
    echo "$(date -Iseconds) Building latest JARVIS..." >> "$LOG"
    if ! swift build >> "$LOG" 2>&1; then
        echo "$(date -Iseconds) Build failed — see $LOG" >> "$LOG"
        osascript -e "display alert \"JARVIS build failed\" message \"Check $LOG for details.\" as critical"
        exit 1
    fi
    echo "$(date -Iseconds) Build complete." >> "$LOG"
else
    echo "$(date -Iseconds) Launching cached build." >> "$LOG"
fi

exec "$BINARY"

#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

LOG="/tmp/jarvis-launch.log"
ORCH_LOG="/tmp/jarvis-orchestrator.log"
APP="$DIR/Jarvis.app"
BINARY="$APP/Contents/MacOS/Jarvis"

orchestrator_responding() {
    curl -sf http://127.0.0.1:8765/health 2>/dev/null \
        | grep -q '"status"[[:space:]]*:[[:space:]]*"online"'
}

start_orchestrator_if_needed() {
    if orchestrator_responding; then
        echo "$(date -Iseconds) Orchestrator already online." >> "$LOG"
        return 0
    fi

    echo "$(date -Iseconds) Starting orchestrator..." >> "$LOG"
    nohup "$DIR/scripts/start-orchestrator.sh" >> "$ORCH_LOG" 2>&1 &

    for _ in {1..30}; do
        if orchestrator_responding; then
            echo "$(date -Iseconds) Orchestrator online." >> "$LOG"
            return 0
        fi
        sleep 0.5
    done

    echo "$(date -Iseconds) Orchestrator failed to start — see $ORCH_LOG" >> "$LOG"
    return 1
}

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

start_orchestrator_if_needed || true

open "$APP"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORCH="$ROOT/orchestrator"
cd "$ORCH"

if [[ ! -d .venv ]]; then
    echo "Creating virtual environment..."
    python3 -m venv .venv
fi

# shellcheck disable=SC1091
source .venv/bin/activate

pip install -r requirements.txt -q

echo "Starting JARVIS orchestrator on http://127.0.0.1:8765"
exec uvicorn app.main:app --host 127.0.0.1 --port 8765

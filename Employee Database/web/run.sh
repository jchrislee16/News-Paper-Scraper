#!/usr/bin/env bash
# run.sh — start the viewer on http://127.0.0.1:5001
# Creates .venv on first run.
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -d .venv ]]; then
    echo "==> creating .venv"
    python3 -m venv .venv
    ./.venv/bin/pip install -q --upgrade pip
    ./.venv/bin/pip install -q -r requirements.txt
fi
exec ./.venv/bin/python app.py

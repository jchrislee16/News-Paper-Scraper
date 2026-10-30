#!/usr/bin/env bash
# deploy.sh — push this schema to the backend VM and rebuild the database there.
#
#   ./deploy.sh              # copy SQL up and reload the database (DESTRUCTIVE on the server)
#   ./deploy.sh --push-only  # copy the files up, do not touch the database
#   ./deploy.sh --psql       # open a psql shell on the server database
#
# Override with env vars: VM_HOST, VM_USER, VM_KEY, REMOTE_DIR, DB_NAME
set -euo pipefail

# Connection details come from the environment, never from this file: `main` is
# served by GitHub Pages, so anything committed here is public, and a live host
# plus its SSH user is free reconnaissance. Keep them in an untracked file and
# source it, e.g. ~/.employee-db-deploy:
#     export VM_HOST=... VM_USER=... VM_KEY=~/path/to/key.pem

VM_HOST="${VM_HOST:?set VM_HOST (see the note above) — refusing to guess a deploy target}"
VM_USER="${VM_USER:?set VM_USER}"
VM_KEY="${VM_KEY:?set VM_KEY to your private key path}"
REMOTE_DIR="${REMOTE_DIR:-/home/$VM_USER/employee-database}"
DB_NAME="${DB_NAME:-employee_db}"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

SSH=(ssh -i "$VM_KEY" -o StrictHostKeyChecking=accept-new "$VM_USER@$VM_HOST")

case "${1:-}" in
  --psql)
    exec "${SSH[@]}" -t "psql -d $DB_NAME"
    ;;
esac

# The VM stopped running PostgreSQL on 2026-10-29; MySQL is the live database
# there now (see README). Without this check the reload step fails somewhere
# inside load.sh with a connection error that looks like a network problem.
if ! "${SSH[@]}" 'systemctl is-active --quiet postgresql'; then
    echo "!!! PostgreSQL is not running on $VM_HOST." >&2
    echo "    The VM was switched to MySQL; use ./deploy-mysql.sh instead." >&2
    echo "    To bring PostgreSQL back:  ssh ... 'sudo systemctl enable --now postgresql'" >&2
    exit 1
fi

echo "==> pushing SQL to $VM_USER@$VM_HOST:$REMOTE_DIR"
"${SSH[@]}" "mkdir -p '$REMOTE_DIR'"
scp -q -i "$VM_KEY" -o StrictHostKeyChecking=accept-new \
    -r "$LOCAL_DIR/sql" "$LOCAL_DIR/load.sh" "$VM_USER@$VM_HOST:$REMOTE_DIR/"
"${SSH[@]}" "chmod +x '$REMOTE_DIR/load.sh'"

if [[ "${1:-}" == "--push-only" ]]; then
    echo "==> pushed (database untouched)"
    exit 0
fi

echo "==> rebuilding $DB_NAME on the server"
"${SSH[@]}" "cd '$REMOTE_DIR' && ./load.sh '$DB_NAME'"

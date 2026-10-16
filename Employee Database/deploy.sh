#!/usr/bin/env bash
# deploy.sh — push this schema to the backend VM and rebuild the database there.
#
#   ./deploy.sh              # copy SQL up and reload the database (DESTRUCTIVE on the server)
#   ./deploy.sh --push-only  # copy the files up, do not touch the database
#   ./deploy.sh --psql       # open a psql shell on the server database
#
# Override with env vars: VM_HOST, VM_USER, VM_KEY, REMOTE_DIR, DB_NAME
set -euo pipefail

VM_HOST="${VM_HOST:-20.151.118.114}"
VM_USER="${VM_USER:-azureuser}"
VM_KEY="${VM_KEY:-$HOME/Desktop/News-Paper-Scraper/free-server_key.pem}"
REMOTE_DIR="${REMOTE_DIR:-/home/$VM_USER/employee-database}"
DB_NAME="${DB_NAME:-employee_db}"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

SSH=(ssh -i "$VM_KEY" -o StrictHostKeyChecking=accept-new "$VM_USER@$VM_HOST")

case "${1:-}" in
  --psql)
    exec "${SSH[@]}" -t "psql -d $DB_NAME"
    ;;
esac

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

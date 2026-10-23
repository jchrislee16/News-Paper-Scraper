#!/usr/bin/env bash
# deploy-mysql.sh — push the MySQL schema to the backend VM and rebuild there.
#
#   ./deploy-mysql.sh              # copy SQL up and reload (DESTRUCTIVE on the server)
#   ./deploy-mysql.sh --push-only  # copy the files up, do not touch the database
#   ./deploy-mysql.sh --shell      # open a mysql shell on the server database
#
# Override with env vars: VM_HOST, VM_USER, VM_KEY, REMOTE_DIR, DB_NAME,
#                         MYSQL_USER, MYSQL_PASSWORD
#
# *** NOT YET RUN AGAINST THE VM. ***
# The VM runs PostgreSQL 14.24, not MySQL. This script assumes
# a MySQL 8.0+ server is installed and reachable there and that $MYSQL_USER can
# CREATE DATABASE. Until that is true, this will fail at the load step. Check
# first:
#     ssh -i "$VM_KEY" "$VM_USER@$VM_HOST" 'mysql --version'
#
# Note also that the server still holds the Postgres employee_db. Deploying this
# does not remove it; decide deliberately whether to keep both or drop one.
set -euo pipefail

# Connection details come from the environment, never from this file: `main` is
# served by GitHub Pages, so anything committed here is public, and a live host
# plus its SSH user is free reconnaissance. Keep them in an untracked file and
# source it, e.g. ~/.employee-db-deploy:
#     export VM_HOST=... VM_USER=... VM_KEY=~/path/to/key.pem

VM_HOST="${VM_HOST:?set VM_HOST (see the note above) — refusing to guess a deploy target}"
VM_USER="${VM_USER:?set VM_USER}"
VM_KEY="${VM_KEY:?set VM_KEY to your private key path}"
REMOTE_DIR="${REMOTE_DIR:-/home/$VM_USER/employee-database-mysql}"
DB_NAME="${DB_NAME:-employee_db}"
LOCAL_DIR="$(cd "$(dirname "$0")" && pwd)"

SSH=(ssh -i "$VM_KEY" -o StrictHostKeyChecking=accept-new "$VM_USER@$VM_HOST")

case "${1:-}" in
  --shell)
    exec "${SSH[@]}" -t "mysql --user='${MYSQL_USER:-root}' '$DB_NAME'"
    ;;
esac

echo "==> checking the server actually has MySQL"
if ! "${SSH[@]}" 'command -v mysql >/dev/null'; then
    echo "!!! no mysql client on $VM_HOST. Install MySQL server there first." >&2
    exit 1
fi
"${SSH[@]}" 'mysql --version'

echo "==> pushing SQL to $VM_USER@$VM_HOST:$REMOTE_DIR"
"${SSH[@]}" "mkdir -p '$REMOTE_DIR'"
scp -q -i "$VM_KEY" -o StrictHostKeyChecking=accept-new \
    -r "$LOCAL_DIR/sql-mysql" "$LOCAL_DIR/load-mysql.sh" "$VM_USER@$VM_HOST:$REMOTE_DIR/"
"${SSH[@]}" "chmod +x '$REMOTE_DIR/load-mysql.sh'"

if [[ "${1:-}" == "--push-only" ]]; then
    echo "==> pushed (database untouched)"
    exit 0
fi

echo "==> rebuilding $DB_NAME on the server"
"${SSH[@]}" "cd '$REMOTE_DIR' && MYSQL_USER='${MYSQL_USER:-root}' MYSQL_PASSWORD='${MYSQL_PASSWORD:-}' ./load-mysql.sh '$DB_NAME'"

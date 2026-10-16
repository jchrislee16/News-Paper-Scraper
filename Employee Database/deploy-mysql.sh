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
# The VM at 20.151.118.114 runs PostgreSQL 14.24, not MySQL. This script assumes
# a MySQL 8.0+ server is installed and reachable there and that $MYSQL_USER can
# CREATE DATABASE. Until that is true, this will fail at the load step. Check
# first:
#     ssh -i "$VM_KEY" azureuser@20.151.118.114 'mysql --version'
#
# Note also that the server still holds the Postgres employee_db. Deploying this
# does not remove it; decide deliberately whether to keep both or drop one.
set -euo pipefail

VM_HOST="${VM_HOST:-20.151.118.114}"
VM_USER="${VM_USER:-azureuser}"
VM_KEY="${VM_KEY:-$HOME/Desktop/News-Paper-Scraper/free-server_key.pem}"
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

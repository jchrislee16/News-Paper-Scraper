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
# The VM now runs MySQL 8.0.46 alongside PostgreSQL 14.24, and this script has
# been run successfully against it. MYSQL_USER must be able to CREATE DATABASE;
# MySQL 8's root uses auth_socket, so it cannot be used remotely — use the
# dedicated empdb_admin account (credentials in the untracked .env.deploy).
#
# The server holds BOTH databases: the Postgres employee_db and the MySQL one.
# This script only touches the MySQL side.
#
# MEMORY: the VM has 894 MB and no spare headroom. /etc/mysql/mysql.conf.d/
# zz-small-vm.cnf trims the buffer pool to 64M and turns performance_schema off,
# which took mysqld from 248 MB to ~145 MB idle. A 2 GB swapfile exists as a
# backstop so a MySQL spike cannot get PostgreSQL OOM-killed. Do not raise those
# limits without checking `free -h` on the box first.
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

#!/usr/bin/env bash
# refresh_snapshot.sh — re-export data/*.json from MySQL and push it.
#
# This keeps the FALLBACK fresh. The page prefers the live API, but when the
# tunnel has rotated (or the VM is down) it reads these files instead, so they
# should not be months old. Run from cron.
#
# Pushes only if something actually changed, so an idle database does not
# produce an empty commit every interval.
set -euo pipefail

B=/home/azureuser/employee-database-mysql
CLONE="$B/.site"
REPO="git@github.com:jchrislee16/News-Paper-Scraper.git"
KEY="$HOME/.ssh/id_pages_deploy"
log() { echo "[$(date -Is)] $*"; }

export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
[[ -d "$CLONE/.git" ]] || git clone --depth 1 "$REPO" "$CLONE"
cd "$CLONE"
git fetch --depth 1 origin main -q
git reset --hard origin/main -q
git config user.email "vm@jchrislee.com"
git config user.name  "empdb-vm"

# The exporter writes relative to its own location, so run the copy inside the
# clone and point it at the VM's MySQL.
cd "$CLONE/Employee Database/web"
MYSQL_DB="${MYSQL_DB:-employee_db}" \
MYSQL_USER="${MYSQL_USER:-empdb_app}" \
MYSQL_PASSWORD="${MYSQL_PASSWORD:-}" \
  "$B/venv/bin/python" export_static.py >/dev/null

cd "$CLONE"
if git diff --quiet -- data; then
    log "snapshot unchanged"
    exit 0
fi
git add data
git commit -q -m "Refresh the data snapshot from MySQL

Automated export by refresh_snapshot.sh on the VM. This is the fallback the
explorer reads when the live API tunnel is unreachable."
git push -q origin main
log "snapshot pushed"

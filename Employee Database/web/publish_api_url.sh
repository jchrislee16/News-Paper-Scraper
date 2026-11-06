#!/usr/bin/env bash
# publish_api_url.sh — tell the published page where the live API moved to.
#
# A Cloudflare quick tunnel gets a NEW random hostname every restart, and the
# frontend is a static page on GitHub Pages, so there has to be a rendezvous
# point both sides can reach. That is api-config.json in the repo: this script
# writes it, the page reads it.
#
# This is the same mechanism the v1 news feed was *documented* to have and never
# actually had -- its config.js claimed to be "auto-updated by the VM" while
# nothing ever wrote it, so the feed silently served nothing for months once the
# tunnel rotated. The difference here is (a) this script exists, and (b) the
# page falls back to a committed snapshot, so a stale URL degrades instead of
# breaking.
#
# Run by api-tunnel.service ExecStartPost. Safe to run by hand; no-ops when
# nothing changed.
set -euo pipefail

B=/home/azureuser/employee-database-mysql
LOG="$B/logs/tunnel.log"
CLONE="$B/.site"
REPO="git@github.com:jchrislee16/News-Paper-Scraper.git"
KEY="$HOME/.ssh/id_pages_deploy"

log() { echo "[$(date -Is)] $*"; }

# Last match, not first: the log is appended across restarts, so the first URL
# in it is a long-dead tunnel.
URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG" 2>/dev/null | tail -1 || true)
[[ -n "$URL" ]] || { log "no tunnel URL in $LOG yet"; exit 1; }
log "tunnel: $URL"

# Never publish a URL that does not answer: the page would switch to live mode
# against a dead host instead of quietly using the snapshot.
if ! curl -fsS --max-time 20 "$URL/api/health" >/dev/null 2>&1; then
    log "REFUSING to publish: $URL/api/health did not respond"
    exit 1
fi

export GIT_SSH_COMMAND="ssh -i $KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
[[ -d "$CLONE/.git" ]] || git clone --depth 1 "$REPO" "$CLONE"
cd "$CLONE"
git fetch --depth 1 origin main -q
git reset --hard origin/main -q
git config user.email "vm@jchrislee.com"
git config user.name  "empdb-vm"

CURRENT=$(python3 -c "import json;print(json.load(open('api-config.json')).get('api_base') or '')" 2>/dev/null || true)
if [[ "$CURRENT" == "$URL" ]]; then
    log "api-config.json already points at $URL"
    exit 0
fi

python3 - "$URL" <<'PY'
import json, sys, datetime
p = "api-config.json"
cfg = json.load(open(p))
cfg["api_base"] = sys.argv[1]
cfg["updated_at"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
json.dump(cfg, open(p, "w"), indent=2)
PY

git add api-config.json
git commit -q -m "Point the explorer at the current API tunnel

${CURRENT:-(none)} -> $URL

Published by api-tunnel.service on the VM. Quick-tunnel hostnames are ephemeral;
the page reads this file to find the live API and falls back to data/*.json when
it is unreachable."
git push -q origin main
log "pushed"

#!/usr/bin/env bash
# tunnel-mysql.sh — open an SSH tunnel to the VM's MySQL, then run the viewer
# against it.
#
#   ./tunnel-mysql.sh            # tunnel + start the viewer on :5002
#   ./tunnel-mysql.sh --tunnel   # just the tunnel, leave it in the foreground
#
# Needs VM_HOST / VM_USER / VM_KEY and MYSQL_APP_USER / MYSQL_APP_PW, which live
# in the untracked .env.deploy at the repo root:
#
#     source ../../.env.deploy && ./tunnel-mysql.sh
#
# WHY A TUNNEL. MySQL on the VM is bound to 127.0.0.1, so port 3306 is not
# reachable from the internet at all. That is deliberate: a database port open
# to the world is the single worst thing you can leave on a public IP, and the
# credentials here are only as good as the box. SSH is already the one way in,
# so the viewer borrows it. This mirrors how the README documents reaching the
# VM's PostgreSQL (a 5433 tunnel), so both engines are reached the same way.
#
# The tunnel listens on LOCAL port 3307, not 3306, so it cannot collide with a
# MySQL running on your own machine. That matters: pointing the viewer at the
# wrong one and not noticing is an easy way to "verify" the wrong database.
set -euo pipefail
cd "$(dirname "$0")"

LOCAL_PORT="${LOCAL_PORT:-3307}"
: "${VM_HOST:?set VM_HOST — source .env.deploy first}"
: "${VM_USER:?set VM_USER}"
: "${VM_KEY:?set VM_KEY}"
: "${MYSQL_APP_USER:?set MYSQL_APP_USER — see .env.deploy}"
: "${MYSQL_APP_PW:?set MYSQL_APP_PW}"

if lsof -nP -iTCP:"$LOCAL_PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "==> something already listens on $LOCAL_PORT; reusing it"
    TUNNEL_PID=""
else
    echo "==> opening tunnel  localhost:$LOCAL_PORT -> $VM_HOST:3306"
    ssh -i "$VM_KEY" -o StrictHostKeyChecking=accept-new \
        -o ExitOnForwardFailure=yes -N \
        -L "$LOCAL_PORT:localhost:3306" "$VM_USER@$VM_HOST" &
    TUNNEL_PID=$!
    trap 'if [[ -n "${TUNNEL_PID:-}" ]]; then kill "$TUNNEL_PID" 2>/dev/null || true; echo; echo "==> tunnel closed"; fi' EXIT
    for _ in $(seq 1 20); do
        lsof -nP -iTCP:"$LOCAL_PORT" -sTCP:LISTEN >/dev/null 2>&1 && break
        sleep 0.5
    done
    lsof -nP -iTCP:"$LOCAL_PORT" -sTCP:LISTEN >/dev/null 2>&1 \
        || { echo "!!! tunnel did not come up" >&2; exit 1; }
fi

if [[ "${1:-}" == "--tunnel" ]]; then
    echo "==> tunnel is up on $LOCAL_PORT. Ctrl-C to close."
    echo "    mysql -h 127.0.0.1 -P $LOCAL_PORT -u $MYSQL_APP_USER -p employee_db"
    wait
fi

if [[ ! -d .venv-mysql ]]; then
    echo "==> creating .venv-mysql"
    python3 -m venv .venv-mysql
    ./.venv-mysql/bin/pip install -q --upgrade pip
    ./.venv-mysql/bin/pip install -q -r requirements-mysql.txt
fi

export MYSQL_HOST=127.0.0.1
export MYSQL_PORT="$LOCAL_PORT"
export MYSQL_USER="$MYSQL_APP_USER"
export MYSQL_PASSWORD="$MYSQL_APP_PW"
export MYSQL_DB="${MYSQL_DB:-employee_db}"
export PORT="${PORT:-5002}"

echo "==> viewer on http://127.0.0.1:$PORT  (VM MySQL via the tunnel)"
exec ./.venv-mysql/bin/python app_mysql.py

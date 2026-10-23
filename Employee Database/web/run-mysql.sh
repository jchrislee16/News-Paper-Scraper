#!/usr/bin/env bash
# run-mysql.sh — start the MySQL-backed viewer on http://127.0.0.1:5002
#
# Deliberately a different port from run.sh (5001) so the Postgres and MySQL
# viewers can run at the same time and be compared side by side in two tabs.
#
# Creates .venv-mysql on first run. Separate from run.sh's .venv because the two
# need different drivers (psycopg2-binary vs PyMySQL).
#
#   ./run-mysql.sh
#   MYSQL_USER=root MYSQL_PASSWORD=secret ./run-mysql.sh
#   MYSQL_DB=scratch_db PORT=5099 ./run-mysql.sh
set -euo pipefail
cd "$(dirname "$0")"
if [[ ! -d .venv-mysql ]]; then
    echo "==> creating .venv-mysql"
    python3 -m venv .venv-mysql
    ./.venv-mysql/bin/pip install -q --upgrade pip
    ./.venv-mysql/bin/pip install -q -r requirements-mysql.txt
fi
export PORT="${PORT:-5002}"
export MYSQL_DB="${MYSQL_DB:-employee_db}"
exec ./.venv-mysql/bin/python app_mysql.py

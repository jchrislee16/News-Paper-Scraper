#!/usr/bin/env bash
# load-mysql.sh — (re)build the MySQL database from scratch.
#   ./load-mysql.sh                 -> local database "employee_db"
#   ./load-mysql.sh mydb            -> local database "mydb"
#   MYSQL_USER=... MYSQL_PASSWORD=... MYSQL_HOST=... ./load-mysql.sh
#
# DESTRUCTIVE: drops the target database first.
#
# MySQL counterpart of load.sh. Differences worth knowing:
#   * There is no ON_ERROR_STOP. The `mysql` client aborts on the first error
#     when reading a file UNLESS --force is passed, so never add --force here.
#   * sql_mode and NAMES are applied with --init-command so every file in the
#     loop gets them. Setting them inside a .sql file would only affect that file.
#   * ANALYZE TABLE in 08_seed.sql prints a row per table; that is success output,
#     not an error, which is why the check below looks at the exit status rather
#     than at whether anything was written to stdout.
set -euo pipefail

DB_NAME="${1:-employee_db}"
SQL_DIR="$(cd "$(dirname "$0")" && pwd)/sql-mysql"

MY=(mysql
    --user="${MYSQL_USER:-root}"
    --host="${MYSQL_HOST:-localhost}"
    --init-command="SET NAMES utf8mb4; SET SESSION sql_mode='STRICT_ALL_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'")
if [[ -n "${MYSQL_PASSWORD:-}" ]]; then
    MY+=(--password="$MYSQL_PASSWORD")
fi

echo "==> target: MySQL database $DB_NAME on ${MYSQL_HOST:-localhost} (recreated)"
"${MY[@]}" -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;
               CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;"

for f in "$SQL_DIR"/*.sql; do
    echo "--> $(basename "$f")"
    if ! "${MY[@]}" "$DB_NAME" < "$f"; then
        echo "!!! FAILED in $(basename "$f") — stopping." >&2
        exit 1
    fi
done

echo "==> done"
"${MY[@]}" "$DB_NAME" --table -e "
SELECT 'orders'      AS entity, COUNT(*) AS count FROM \`order\`
UNION ALL SELECT 'order items', COUNT(*) FROM order_item
UNION ALL SELECT 'customers',   COUNT(*) FROM customer
UNION ALL SELECT 'products',    COUNT(*) FROM product
UNION ALL SELECT 'employees',   COUNT(*) FROM employee
UNION ALL SELECT 'aliases',     COUNT(*) FROM ai_entity_alias
UNION ALL SELECT 'intents',     COUNT(*) FROM ai_intent;"

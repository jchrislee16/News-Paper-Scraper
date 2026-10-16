#!/usr/bin/env bash
# load.sh — (re)build the database from scratch.
#   ./load.sh                  -> local database "employee_db"
#   ./load.sh mydb             -> local database "mydb"
#   DB_URL=postgres://... ./load.sh   -> remote target
#
# DESTRUCTIVE: drops the target database first.
set -euo pipefail

DB_NAME="${1:-employee_db}"
SQL_DIR="$(cd "$(dirname "$0")" && pwd)/sql"

if [[ -n "${DB_URL:-}" ]]; then
    PSQL=(psql "$DB_URL")
    echo "==> target: $DB_URL"
else
    dropdb --if-exists "$DB_NAME"
    createdb "$DB_NAME"
    PSQL=(psql -d "$DB_NAME")
    echo "==> target: local database $DB_NAME (recreated)"
fi

for f in "$SQL_DIR"/*.sql; do
    echo "--> $(basename "$f")"
    "${PSQL[@]}" -v ON_ERROR_STOP=1 -q -f "$f"
done

echo "==> done"
"${PSQL[@]}" -c "SELECT 'orders' AS entity, count(*) FROM \"order\"
                 UNION ALL SELECT 'order items', count(*) FROM order_item
                 UNION ALL SELECT 'customers', count(*) FROM customer
                 UNION ALL SELECT 'products', count(*) FROM product
                 UNION ALL SELECT 'employees', count(*) FROM employee
                 UNION ALL SELECT 'aliases', count(*) FROM ai.entity_alias
                 UNION ALL SELECT 'intents', count(*) FROM ai.intent;"

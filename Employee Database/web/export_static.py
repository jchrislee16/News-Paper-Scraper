"""export_static.py — snapshot the database to JSON for the static site.

GitHub Pages serves static files only, so the Flask viewer (app_mysql.py) cannot
run there. This exports every dataset it serves into plain JSON, which a static
page then renders with the same tables, sorting and filtering.

    MYSQL_DB=employee_db python3 export_static.py          # -> ../../data/
    MYSQL_PORT=3307 MYSQL_USER=empdb_app ... python3 export_static.py   # the VM

Deliberately a snapshot, not a live API. The alternative was to expose the
viewer through a Cloudflare tunnel like the news backend, but a quick-tunnel URL
dies on every restart, which would make the published page break at random for
anyone who opened it. A committed snapshot always loads. The data is generated
test data, so there is nothing here that needs to be current to the second.

Re-run it and commit the result whenever the schema or seed changes.
"""
import json
import os
import sys
from datetime import date, datetime
from decimal import Decimal

try:
    import pymysql
except ImportError:
    sys.exit("pymysql is missing. pip install -r requirements-mysql.txt")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from app_mysql import QUERIES, DB_CONFIG  # the single source of truth for both

# The repo root: GitHub Pages serves from there, and index.html fetches
# "data/..." relative to itself.
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data")

# The P&L takes a date range. A static page cannot run an arbitrary one, so
# export the same presets the viewer's quick buttons offer and let the page
# switch between them. Anything else needs the Flask app.
PL_RANGES = [
    ("all", "All time"),
    ("ytd", "This year"),
    ("90d", "Last 90 days"),
    ("30d", "Last 30 days"),
]


def jsonable(v):
    if isinstance(v, Decimal):
        # String, not float: float() drops the trailing cents ("424.10" -> 424.1)
        # and is the wrong type for money. The page right-aligns numeric-looking
        # strings, so this still renders as a number.
        return str(v)
    if isinstance(v, datetime):
        return v.isoformat(sep=" ", timespec="minutes")
    if isinstance(v, date):
        return v.isoformat()
    if isinstance(v, bytes):
        return v.decode("utf-8", "replace")
    return v


def rows(cur, sql, params=()):
    cur.execute(sql, params)
    cols = [c[0] for c in cur.description]
    return cols, [[jsonable(v) for v in r] for r in cur.fetchall()]


def main():
    os.makedirs(OUT, exist_ok=True)
    conn = pymysql.connect(**DB_CONFIG)
    manifest = {"datasets": [], "pl": [], "generated_from": DB_CONFIG["database"]}
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT DATE(MIN(ordered_at)), DATE(MAX(ordered_at)) FROM `order`")
            first, last = cur.fetchone()
            manifest["period"] = {"start": str(first), "end": str(last)}

            for key, (label, note, sql) in QUERIES.items():
                cols, data = rows(cur, sql)
                with open(os.path.join(OUT, f"{key}.json"), "w") as f:
                    json.dump({"title": label, "note": note, "columns": cols,
                               "rows": data, "sql": " ".join(sql.split())}, f)
                manifest["datasets"].append({"key": key, "label": label,
                                             "note": note, "rows": len(data)})
                print(f"  {key:<12} {len(data):>5} rows x {len(cols)} cols")

            # P&L presets
            for rkey, rlabel in PL_RANGES:
                if rkey == "all":
                    lo, hi = "2000-01-01", "2099-12-31"
                elif rkey == "ytd":
                    lo, hi = f"{last.year}-01-01", str(last)
                elif rkey == "90d":
                    cur.execute("SELECT DATE_SUB(%s, INTERVAL 90 DAY)", (last,))
                    lo, hi = str(cur.fetchone()[0]), str(last)
                else:
                    cur.execute("SELECT DATE_SUB(%s, INTERVAL 30 DAY)", (last,))
                    lo, hi = str(cur.fetchone()[0]), str(last)

                cur.execute("CALL fn_profit_and_loss(%s, %s)", (lo, hi))
                cols = [c[0] for c in cur.description]
                data = [[jsonable(v) for v in r] for r in cur.fetchall()]
                while cur.nextset():            # drain, or the next CALL errors
                    pass
                with open(os.path.join(OUT, f"pl-{rkey}.json"), "w") as f:
                    json.dump({"title": f"Profit and Loss — {rlabel}",
                               "note": "Cancelled and refunded orders are excluded from "
                                       "revenue and cost alike. Operating expenses are not "
                                       "modelled in this schema, so the bottom line is GROSS "
                                       "profit, not net income.",
                               "range": [lo, hi], "columns": cols, "rows": data,
                               "sql": f"CALL fn_profit_and_loss('{lo}', '{hi}')"}, f)
                manifest["pl"].append({"key": rkey, "label": rlabel, "range": [lo, hi]})
                print(f"  pl-{rkey:<9} {len(data):>5} lines  {lo} .. {hi}")

            # Schema shape, so the page can show what it is a frontend to
            cur.execute("""
                SELECT TABLE_NAME, COUNT(*) AS cols
                FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE()
                  AND TABLE_NAME IN ('employee','customer','customer_address',
                      'product_category','product','order','order_item','order_status_history')
                GROUP BY TABLE_NAME ORDER BY TABLE_NAME""")
            manifest["schema"] = [{"table": t, "columns": c} for t, c in cur.fetchall()]
            for t in manifest["schema"]:
                cur.execute(f"SELECT COUNT(*) FROM `{t['table']}`")
                t["rows"] = cur.fetchone()[0]

        with open(os.path.join(OUT, "manifest.json"), "w") as f:
            json.dump(manifest, f, indent=1)
        print(f"\n==> wrote {len(manifest['datasets'])} datasets + "
              f"{len(manifest['pl'])} P&L presets to data/")
    finally:
        conn.close()


if __name__ == "__main__":
    main()

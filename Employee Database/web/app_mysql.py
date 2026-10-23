"""app_mysql.py — MySQL port of app.py. A plain text viewer for the Employee Database.

Deliberately small: no ORM, no build step, no client framework. Every dataset the
page can show is a named entry in QUERIES below, so the browser picks a key and
never supplies SQL. Free-text input only ever reaches the sp_resolve_* procedures
as a bound parameter.

    MYSQL_DB=employee_db python3 app_mysql.py          # default
    MYSQL_USER=root MYSQL_PASSWORD=secret PORT=5001 python3 app_mysql.py

PORTING NOTES vs app.py:

  psycopg2 -> pymysql. The %s placeholder style is IDENTICAL, so every bound
  parameter ported unchanged — that is the one part of this file that was free.

  The libpq DSN ("dbname=employee_db") is gone; pymysql.connect takes discrete
  keyword arguments, so connection settings are now separate env vars.

  cur.description entries are plain tuples in pymysql, so column names come from
  c[0], not c.name.

  Every connection issues `SET SESSION max_execution_time`. This is NOT
  cosmetic: in Postgres, 07_roles.sql attached statement_timeout to the
  ai_assistant ROLE, so the guard held no matter who connected. MySQL cannot
  attach an execution limit to a user or role, so the only place left to set it
  is the client. If you add another client, it must do this too.

  ::date          -> DATE(...)
  "order"         -> `order`
  ai.entity_alias -> ai_entity_alias   (MySQL has no schemas inside a database)
  array_to_string(sample_utterances, ...) -> JSON_TABLE + GROUP_CONCAT, because
      sample_utterances is a JSON array now rather than text[].

  fn_profit_and_loss and the four resolvers were FUNCTIONS you could SELECT
  FROM. They are PROCEDURES now, so they are CALLed and the ordering/trimming
  that used to live in the SQL moved here. See call_proc().
"""
import os
from datetime import date, datetime
from decimal import Decimal

import pymysql
from flask import Flask, jsonify, render_template, request

DB_CONFIG = {
    "host": os.environ.get("MYSQL_HOST", "localhost"),
    "user": os.environ.get("MYSQL_USER", "root"),
    "password": os.environ.get("MYSQL_PASSWORD", ""),
    "database": os.environ.get("MYSQL_DB", "employee_db"),
    "charset": "utf8mb4",
}
PORT = int(os.environ.get("PORT", "5001"))

# Milliseconds. Replaces `ALTER ROLE ai_assistant SET statement_timeout = '5s'`,
# which MySQL cannot express. Note it only aborts SELECTs, not writes.
MAX_EXECUTION_MS = int(os.environ.get("MAX_EXECUTION_MS", "5000"))

app = Flask(__name__)

# key -> (button label, one-line explanation, SQL)
QUERIES = {
    "orders": (
        "Orders",
        "One row per order, money already totalled (v_order_summary).",
        """SELECT order_number, customer_name, COALESCE(sales_rep_name,'—') AS sales_rep,
                  status, DATE(ordered_at) AS ordered, line_count, total_units AS units,
                  grand_total
             FROM v_order_summary ORDER BY ordered_at DESC""",
    ),
    "customers": (
        "Customers",
        "Lifetime value and recency per customer; cancelled and refunded excluded (v_customer_360).",
        """SELECT customer_name, email, tier, COALESCE(account_manager_name,'—') AS account_manager,
                  order_count, lifetime_value, average_order_value,
                  DATE(last_order_at) AS last_order, days_since_last_order AS days_since
             FROM v_customer_360 ORDER BY lifetime_value DESC""",
    ),
    "products": (
        "Products",
        "Catalogue with units sold and revenue (v_product_performance).",
        """SELECT sku, product_name, brand, COALESCE(category_name,'—') AS category,
                  current_price, stock_quantity AS stock, units_sold, revenue,
                  CASE WHEN is_active THEN '' ELSE 'discontinued' END AS note
             FROM v_product_performance ORDER BY revenue DESC, product_name""",
    ),
    "employees": (
        "Employees",
        "Sales attributed to each rep (v_employee_sales).",
        """SELECT employee_name, job_title, department, COALESCE(manager_name,'—') AS manager,
                  orders_closed, revenue, customers_served,
                  CASE WHEN is_active THEN '' ELSE 'left the company' END AS note
             FROM v_employee_sales ORDER BY revenue DESC, employee_name""",
    ),
    "restock": (
        "Needs restock",
        "Active products at or below their reorder level.",
        """SELECT product_name, sku, stock_quantity AS stock, reorder_level, units_sold
             FROM v_product_performance
            WHERE needs_restock AND is_active ORDER BY stock_quantity""",
    ),
    "sales": (
        "Daily sales",
        "Revenue per day; cancelled and refunded excluded (v_daily_sales).",
        """SELECT sales_day, order_count, units, revenue
             FROM v_daily_sales ORDER BY sales_day DESC""",
    ),
    "balance": (
        "Balance detail (A/R)",
        "Every unpaid invoice with its aging bucket (v_customer_balance). Unpaid = status 'pending'.",
        """SELECT customer_name, tier, invoice, invoice_date, days_outstanding AS days,
                  aging_bucket, items_subtotal, shipping_fee, tax_total, discount_total,
                  balance, sales_rep
             FROM v_customer_balance ORDER BY days_outstanding DESC, customer_name""",
    ),
    "aging": (
        "A/R aging summary",
        "Open balances per customer, bucketed by age (v_ar_aging).",
        """SELECT customer_name, tier, open_invoices,
                  current_0_30, past_due_31_60, past_due_61_90, past_due_90_plus,
                  total_balance, oldest_days
             FROM v_ar_aging ORDER BY total_balance DESC""",
    ),
    "margin": (
        "Profit by product",
        "Where the gross profit came from — revenue, COGS and margin per product.",
        """SELECT sku, product_name, COALESCE(category_name,'—') AS category,
                  current_price, current_cost, units_sold, revenue, cogs,
                  gross_profit, margin_pct, stock_quantity AS stock, inventory_value
             FROM v_product_performance
            WHERE units_sold > 0 ORDER BY gross_profit DESC""",
    ),
    "inventory": (
        "Inventory value",
        "Stock on hand carried at cost — the asset-side figure (v_product_performance).",
        """SELECT sku, product_name, stock_quantity AS stock, current_cost,
                  inventory_value, reorder_level,
                  CASE WHEN needs_restock THEN 'restock' ELSE '' END AS flag
             FROM v_product_performance
            WHERE is_active ORDER BY inventory_value DESC""",
    ),
    "aliases": (
        "Voice aliases",
        "What people actually say out loud, mapped to rows (ai_entity_alias).",
        """SELECT a.entity_type, a.alias, a.alias_kind,
                  CASE a.entity_type
                       WHEN 'customer' THEN (SELECT full_name FROM customer WHERE customer_id = a.entity_id)
                       WHEN 'product'  THEN (SELECT name      FROM product  WHERE product_id  = a.entity_id)
                       WHEN 'employee' THEN (SELECT full_name FROM employee WHERE employee_id = a.entity_id)
                  END AS resolves_to
             FROM ai_entity_alias a ORDER BY a.entity_type, a.alias""",
    ),
    "intents": (
        "Intents",
        "Questions the assistant is meant to answer (ai_intent).",
        # sample_utterances is a JSON array here, not a Postgres text[], so
        # array_to_string becomes JSON_TABLE + GROUP_CONCAT.
        """SELECT i.intent_name, i.description,
                  (SELECT GROUP_CONCAT(j.v SEPARATOR '  |  ')
                     FROM JSON_TABLE(i.sample_utterances, '$[*]'
                                     COLUMNS (v VARCHAR(255) PATH '$')) j) AS sample_utterances
             FROM ai_intent i WHERE i.is_enabled ORDER BY i.intent_name""",
    ),
    "utterances": (
        "Conversation log",
        "Every spoken turn: what was heard, what SQL it became, how it went (ai_utterance).",
        """SELECT u.turn_no, u.transcript, u.asr_confidence AS asr, u.intent_name,
                  u.sql_status, u.row_count, u.response_text, u.latency_ms AS ms
             FROM ai_utterance u ORDER BY u.spoken_at DESC, u.turn_no""",
    ),
}

# Procedures now, not functions. Each takes the phrase plus a NULL min_score to
# get the procedure's own default (MySQL has no default parameter values).
RESOLVERS = {
    "customer": ("ai_resolve_customer", True),
    "product": ("ai_resolve_product", True),
    "employee": ("ai_resolve_employee", True),
    "order": ("ai_resolve_order", False),
}


def jsonable(value):
    if isinstance(value, Decimal):
        # Deliberately a string, not a float: float() loses the trailing cents
        # ("12595.00" -> 12595) and is the wrong type for money anyway. The
        # front end right-aligns anything that looks numeric, so this still
        # renders as a number.
        return str(value)
    if isinstance(value, (date, datetime)):
        return value.isoformat(sep=" ", timespec="minutes") if isinstance(value, datetime) else value.isoformat()
    return value


def connect():
    conn = pymysql.connect(**DB_CONFIG)
    with conn.cursor() as cur:
        # The guard Postgres attached to the role. See the module docstring.
        cur.execute("SET SESSION max_execution_time = %s", (MAX_EXECUTION_MS,))
    return conn


def run(sql, params=None):
    """Run one query, return (columns, rows) ready for JSON."""
    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params or ())
            columns = [c[0] for c in cur.description]
            rows = [[jsonable(v) for v in row] for row in cur.fetchall()]
    finally:
        # pymysql's context manager semantics differ from psycopg2's, so the
        # close is explicit rather than implied by `with`.
        conn.close()
    return columns, rows


def call_proc(name, params):
    """CALL a procedure and return (columns, rows).

    Needed because MySQL functions cannot return a result set, so the resolvers
    and the P&L are procedures. A CALL leaves the result set on the cursor; the
    trailing empty set some drivers surface is skipped by reading the first set
    that actually has a description.
    """
    conn = connect()
    try:
        with conn.cursor() as cur:
            placeholders = ", ".join(["%s"] * len(params))
            cur.execute(f"CALL {name}({placeholders})", params)
            columns = [c[0] for c in cur.description] if cur.description else []
            rows = [[jsonable(v) for v in row] for row in cur.fetchall()]
    finally:
        conn.close()
    return columns, rows


@app.route("/")
def index():
    buttons = [(key, label, note) for key, (label, note, _) in QUERIES.items()]
    return render_template("index.html", buttons=buttons)


@app.route("/api/data/<key>")
def data(key):
    if key not in QUERIES:
        return jsonify(error=f"unknown dataset '{key}'"), 404
    label, note, sql = QUERIES[key]
    columns, rows = run(sql)
    return jsonify(title=label, note=note, columns=columns, rows=rows, sql=" ".join(sql.split()))


@app.route("/api/order/<order_number>")
def order_detail(order_number):
    sql = """SELECT product_name, category_name, quantity, unit_price, discount, line_total
               FROM v_order_line WHERE order_number = %s ORDER BY line_total DESC"""
    columns, rows = run(sql, (order_number,))
    return jsonify(title=f"Items in order {order_number}", note="v_order_line",
                   columns=columns, rows=rows, sql=" ".join(sql.split()))


@app.route("/api/pl")
def profit_and_loss():
    """Profit and loss for a period. Dates are bound parameters, never interpolated."""
    start = (request.args.get("start") or "").strip()
    end = (request.args.get("end") or "").strip()
    for label, value in (("start", start), ("end", end)):
        try:
            date.fromisoformat(value)
        except ValueError:
            return jsonify(error=f"{label} must be a date as YYYY-MM-DD"), 400
    if start > end:
        return jsonify(error="start date is after end date"), 400

    # Was: SELECT section, line_item, amount FROM fn_profit_and_loss(%s,%s) ORDER BY line_no
    # A procedure cannot be filtered or ordered by the caller in SQL, so the
    # procedure orders internally and the line_no column is dropped here.
    columns, rows = call_proc("fn_profit_and_loss", (start, end))
    if columns and columns[0] == "line_no":
        columns = columns[1:]
        rows = [r[1:] for r in rows]
    return jsonify(
        title=f"Profit and Loss — {start} to {end}",
        note="Cancelled and refunded orders are excluded from revenue and cost alike. "
             "Operating expenses are not modelled in this schema, so the bottom line is "
             "GROSS profit, not net income.",
        columns=columns, rows=rows, sql="CALL fn_profit_and_loss(%s, %s)",
    )


@app.route("/api/period")
def period():
    """Earliest and latest order date, so the UI can default the P&L range."""
    _, rows = run("SELECT DATE(MIN(ordered_at)), DATE(MAX(ordered_at)) FROM `order`")
    return jsonify(start=str(rows[0][0]), end=str(rows[0][1]))


@app.route("/api/resolve")
def resolve():
    """Simulate the voice lookup: a messy spoken phrase in, ranked candidates out."""
    kind = request.args.get("kind", "customer")
    phrase = (request.args.get("q") or "").strip()
    if kind not in RESOLVERS:
        return jsonify(error=f"unknown resolver '{kind}'"), 404
    if not phrase:
        return jsonify(error="say something first"), 400
    proc, takes_min_score = RESOLVERS[kind]
    params = (phrase, None) if takes_min_score else (phrase,)
    columns, rows = call_proc(proc, params)
    note = (f'{proc}({phrase!r}) — ranked candidates; a near-tie at the top means "did you mean…?" '
            "Scores are discrete tiers, not a continuous similarity: MySQL has no trigram "
            "matching, so a typo that misses every tier returns nothing rather than a low score.")
    return jsonify(title=f'Heard: "{phrase}"', note=note, columns=columns, rows=rows,
                   sql=f"CALL {proc}(%s, NULL)" if takes_min_score else f"CALL {proc}(%s)")


@app.route("/api/health")
def health():
    columns, rows = run("SELECT DATABASE(), COUNT(*) FROM v_order_summary")
    return jsonify(database=rows[0][0], orders=rows[0][1])


if __name__ == "__main__":
    print(f"==> http://127.0.0.1:{PORT}  (MySQL database: {DB_CONFIG['database']})")
    app.run(host="127.0.0.1", port=PORT, debug=True)

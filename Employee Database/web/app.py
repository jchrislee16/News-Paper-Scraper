"""app.py — a plain text viewer for the Employee Database.

Deliberately small: no ORM, no build step, no client framework. Every dataset the
page can show is a named entry in QUERIES below, so the browser picks a key and
never supplies SQL. Free-text input only ever reaches the ai.resolve_* functions
as a bound parameter.

    DATABASE_URL=dbname=employee_db python3 app.py      # default
    PORT=5001 python3 app.py
"""
import json
import os
from datetime import date, datetime
from decimal import Decimal

import psycopg2
from flask import Flask, jsonify, render_template, request

DATABASE_URL = os.environ.get("DATABASE_URL", "dbname=employee_db")
PORT = int(os.environ.get("PORT", "5001"))

app = Flask(__name__)

# key -> (button label, one-line explanation, SQL)
QUERIES = {
    "orders": (
        "Orders",
        "One row per order, money already totalled (v_order_summary).",
        """SELECT order_number, customer_name, coalesce(sales_rep_name,'—') AS sales_rep,
                  status, ordered_at::date AS ordered, line_count, total_units AS units,
                  grand_total
             FROM v_order_summary ORDER BY ordered_at DESC""",
    ),
    "customers": (
        "Customers",
        "Lifetime value and recency per customer; cancelled and refunded excluded (v_customer_360).",
        """SELECT customer_name, email, tier, coalesce(account_manager_name,'—') AS account_manager,
                  order_count, lifetime_value, average_order_value,
                  last_order_at::date AS last_order, days_since_last_order AS days_since
             FROM v_customer_360 ORDER BY lifetime_value DESC""",
    ),
    "products": (
        "Products",
        "Catalogue with units sold and revenue (v_product_performance).",
        """SELECT sku, product_name, brand, coalesce(category_name,'—') AS category,
                  current_price, stock_quantity AS stock, units_sold, revenue,
                  CASE WHEN is_active THEN '' ELSE 'discontinued' END AS note
             FROM v_product_performance ORDER BY revenue DESC, product_name""",
    ),
    "employees": (
        "Employees",
        "Sales attributed to each rep (v_employee_sales).",
        """SELECT employee_name, job_title, department, coalesce(manager_name,'—') AS manager,
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
        """SELECT sku, product_name, coalesce(category_name,'—') AS category,
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
        "What people actually say out loud, mapped to rows (ai.entity_alias).",
        """SELECT a.entity_type, a.alias, a.alias_kind,
                  CASE a.entity_type
                       WHEN 'customer' THEN (SELECT full_name FROM customer WHERE customer_id = a.entity_id)
                       WHEN 'product'  THEN (SELECT name      FROM product  WHERE product_id  = a.entity_id)
                       WHEN 'employee' THEN (SELECT full_name FROM employee WHERE employee_id = a.entity_id)
                  END AS resolves_to
             FROM ai.entity_alias a ORDER BY a.entity_type, a.alias""",
    ),
    "intents": (
        "Intents",
        "Questions the assistant is meant to answer (ai.intent).",
        """SELECT intent_name, description,
                  array_to_string(sample_utterances, '  |  ') AS sample_utterances
             FROM ai.intent WHERE is_enabled ORDER BY intent_name""",
    ),
    "utterances": (
        "Conversation log",
        "Every spoken turn: what was heard, what SQL it became, how it went (ai.utterance).",
        """SELECT u.turn_no, u.transcript, u.asr_confidence AS asr, u.intent_name,
                  u.sql_status, u.row_count, u.response_text, u.latency_ms AS ms
             FROM ai.utterance u ORDER BY u.spoken_at DESC, u.turn_no""",
    ),
}

RESOLVERS = {
    "customer": "SELECT * FROM ai.resolve_customer(%s)",
    "product": "SELECT * FROM ai.resolve_product(%s)",
    "employee": "SELECT * FROM ai.resolve_employee(%s)",
    "order": "SELECT * FROM ai.resolve_order(%s)",
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


def run(sql, params=None):
    """Run one query, return (columns, rows) ready for JSON."""
    with psycopg2.connect(DATABASE_URL) as conn, conn.cursor() as cur:
        cur.execute(sql, params or ())
        columns = [c.name for c in cur.description]
        rows = [[jsonable(v) for v in row] for row in cur.fetchall()]
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

    sql = """SELECT section, line_item, amount
               FROM fn_profit_and_loss(%s, %s) ORDER BY line_no"""
    columns, rows = run(sql, (start, end))
    return jsonify(
        title=f"Profit and Loss — {start} to {end}",
        note="Cancelled and refunded orders are excluded from revenue and cost alike. "
             "Operating expenses are not modelled in this schema, so the bottom line is "
             "GROSS profit, not net income.",
        columns=columns, rows=rows, sql=" ".join(sql.split()),
    )


@app.route("/api/period")
def period():
    """Earliest and latest order date, so the UI can default the P&L range."""
    _, rows = run("SELECT min(ordered_at)::date, max(ordered_at)::date FROM \"order\"")
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
    columns, rows = run(RESOLVERS[kind], (phrase,))
    note = f'ai.resolve_{kind}({phrase!r}) — ranked candidates; a near-tie at the top means "did you mean…?"'
    return jsonify(title=f'Heard: "{phrase}"', note=note, columns=columns, rows=rows,
                   sql=f"SELECT * FROM ai.resolve_{kind}(%s)")


@app.route("/api/health")
def health():
    columns, rows = run("SELECT current_database(), count(*) FROM v_order_summary")
    return jsonify(database=rows[0][0], orders=rows[0][1])


if __name__ == "__main__":
    print(f"==> http://127.0.0.1:{PORT}  (database: {DATABASE_URL})")
    app.run(host="127.0.0.1", port=PORT, debug=True)

"""generate_data.py — bulk random data for the Employee Database (MySQL).

Merged from Nam Kyu's dummy_data.py. His version defined its own tables and
inserted into those; this one targets the project's single schema in sql-mysql/
instead, and covers all seven business tables rather than two.

    ./load-mysql.sh                      # schema + the small hand-written seed
    python3 generate_data.py             # then pile volume on top
    python3 generate_data.py --customers 2000 --orders 8000
    python3 generate_data.py --truncate  # wipe generated+seed rows first

    MYSQL_USER=root MYSQL_PASSWORD=secret MYSQL_DB=employee_db python3 generate_data.py

Requires: pip install -r web/requirements-mysql.txt faker

WHAT CHANGED FROM dummy_data.py, AND WHY
----------------------------------------
Kept: the overall shape (one function per table, Faker, parameterized %s,
try/except/rollback), and the good idea of reading back real primary keys
before inserting children so referential integrity actually holds.

Fixed:
  * full_name is NOT inserted. It is a GENERATED column in this schema, so
    writing to it fails with
        (3105) The value specified for generated column 'full_name' ... not allowed
    Same for order_item.line_total / line_cost and product.search_document.
  * tier values are lowercase. The column is
    ENUM('standard','silver','gold','platinum'); 'Gold' is rejected.
  * no employee is their own manager (employee_not_own_manager trigger), and
    manager_id points at an employee that actually exists rather than a
    hardcoded randint(1, 10).
  * order dates are drawn AFTER the customer signed up. The original drew
    order_date independently, which put 48% of orders before their customer
    existed and makes every cohort/churn/retention number meaningless.
  * phone is generated to fit. Faker's en_US locale emits 21-22 characters
    about 12% of the time; the original schema's VARCHAR(20) meant one long
    number rolled back the whole 50-row batch, which is why it failed ~99.8%
    of the time. This schema's column is wide, but the value is still
    truncated defensively.
  * prices have cents and a plausible cost. The original used
    random_int(1000, 100000) with no decimals, pricing every product like a
    car, and had no cost column at all so margin was unanswerable.
  * unit_price / unit_cost are SNAPSHOT onto order_item from the product row at
    insert time, which is the whole reason those columns exist.
  * stock_quantity is decremented by what gets sold.
  * status timestamps satisfy the table's CHECK constraints:
      shipped_at >= ordered_at, delivered_at >= shipped_at,
      (status = 'cancelled') == (cancelled_at IS NOT NULL)
  * shipping/billing address always belongs to the ordering customer, because
    the composite FK (address_id, customer_id) enforces it.
  * one default address per customer per kind, because default_key does.

Not set here, deliberately: order_number and order_status_history. Triggers on
`order` write both. Supplying them would fight the schema.
"""
import argparse
import os
import random
import sys
from datetime import datetime, timedelta

try:
    import pymysql
except ImportError:
    sys.exit("pymysql is missing. pip install -r web/requirements-mysql.txt")
try:
    from faker import Faker
except ImportError:
    sys.exit("faker is missing. pip install faker")

fake = Faker("en_US")

DB = {
    "host": os.environ.get("MYSQL_HOST", "localhost"),
    "user": os.environ.get("MYSQL_USER", "root"),
    "password": os.environ.get("MYSQL_PASSWORD", ""),
    "database": os.environ.get("MYSQL_DB", "employee_db"),
    "charset": "utf8mb4",
    "cursorclass": pymysql.cursors.DictCursor,
}

# Weighted so most orders are finished business and a few are live, which is
# what makes the A/R and P&L reports show something. 'pending' is what
# v_customer_balance counts as unpaid.
STATUS_WEIGHTS = [
    ("delivered", 55), ("shipped", 10), ("packed", 5), ("paid", 8),
    ("pending", 12), ("cancelled", 6), ("refunded", 4),
]
METHODS = ["card", "paypal", "bank_transfer", "cash_on_delivery", "store_credit"]
TIERS = ["standard", "silver", "gold", "platinum"]          # lowercase: see ENUM
DEPARTMENTS = ["Engineering", "Marketing", "Sales", "Support", "Operations", "Finance"]
CATEGORIES = [
    ("Laptops", "Portable computers"),
    ("Peripherals", "Keyboards, mice, docks and other desk accessories"),
    ("Displays", "Monitors and screens"),
    ("Furniture", "Desks, chairs and office furniture"),
    ("Audio", "Headsets, speakers and microphones"),
    ("Networking", "Routers, switches and cabling"),
]


def connect():
    return pymysql.connect(**DB)


def phone():
    """Faker's en_US phone runs to 22 chars; keep it inside the column."""
    return fake.phone_number()[:40]


def pick_status():
    population = [s for s, _ in STATUS_WEIGHTS]
    weights = [w for _, w in STATUS_WEIGHTS]
    return random.choices(population, weights=weights, k=1)[0]


def generate_employees(conn, n):
    with conn.cursor() as cur:
        print(f"employees: generating {n}...")
        # Existing ids so new hires can report to someone who really exists.
        cur.execute("SELECT employee_id FROM employee")
        existing = [r["employee_id"] for r in cur.fetchall()]
        for i in range(n):
            first, last = fake.first_name(), fake.last_name()
            hired = fake.date_time_between(start_date="-6y", end_date="-30d")
            # A manager must already exist. None for the first few, so the tree
            # has roots. Never self: the employee_not_own_manager trigger
            # rejects that, and it is nonsense anyway.
            manager = random.choice(existing) if existing and random.random() < 0.75 else None
            cur.execute(
                """INSERT INTO employee
                       (first_name, last_name, email, phone, job_title, department,
                        manager_id, hired_on, is_active, created_at, updated_at)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (first, last, f"emp{i}.{fake.unique.user_name()}@example.com", phone(),
                 fake.job()[:100], random.choice(DEPARTMENTS), manager,
                 hired.date(), random.random() < 0.88, hired, datetime.now()),
            )
            existing.append(cur.lastrowid)
        conn.commit()
        print(f"employees: inserted {n}")
        return existing


def generate_customers(conn, n, employee_ids):
    with conn.cursor() as cur:
        print(f"customers: generating {n}...")
        made = []
        for i in range(n):
            first, last = fake.first_name(), fake.last_name()
            signed_up = fake.date_time_between(start_date="-4y", end_date="-1d")
            # Real employee or nobody — not a hardcoded randint range.
            mgr = random.choice(employee_ids) if employee_ids and random.random() < 0.55 else None
            cur.execute(
                """INSERT INTO customer
                       (first_name, last_name, email, phone, tier, account_manager_id,
                        signed_up_on, is_active, created_at, updated_at)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)""",
                (first, last, f"cust{i}.{fake.unique.user_name()}@example.com", phone(),
                 random.choices(TIERS, weights=[55, 25, 15, 5], k=1)[0], mgr,
                 signed_up.date(), random.random() < 0.94, signed_up, datetime.now()),
            )
            made.append({"customer_id": cur.lastrowid, "signed_up_on": signed_up})
        conn.commit()
        print(f"customers: inserted {n}")
        return made


def generate_addresses(conn, customers):
    """One default shipping each, plus a sometimes-billing and a sometimes-extra.

    default_key is a generated column with a UNIQUE index, so there can only
    ever be one default per (customer, kind). Extra addresses must be
    is_default = FALSE or the insert is rejected.
    """
    with conn.cursor() as cur:
        print(f"addresses: generating for {len(customers)} customers...")
        made = 0
        for c in customers:
            cid = c["customer_id"]
            rows = [("shipping", "home", True)]
            if random.random() < 0.45:
                rows.append(("billing", "billing", True))
            if random.random() < 0.25:
                rows.append(("shipping", "the office", False))
            for kind, label, is_default in rows:
                cur.execute(
                    """INSERT INTO customer_address
                           (customer_id, kind, label, line1, city, state_region,
                            postal_code, country_code, is_default, created_at)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, 'US', %s, %s)""",
                    (cid, kind, label, fake.street_address()[:200], fake.city()[:100],
                     fake.state_abbr(), fake.postcode()[:20], is_default,
                     c["signed_up_on"]),
                )
                made += 1
        conn.commit()
        print(f"addresses: inserted {made}")


def generate_catalogue(conn, n_products):
    with conn.cursor() as cur:
        print(f"catalogue: generating up to {n_products} products...")
        for name, descr in CATEGORIES:
            cur.execute(
                "INSERT INTO product_category (name, description) VALUES (%s, %s) "
                "ON DUPLICATE KEY UPDATE description = VALUES(description)",
                (name, descr),
            )
        conn.commit()
        cur.execute("SELECT category_id, name FROM product_category")
        cats = cur.fetchall()

        # Price bands per category, so a mouse does not cost as much as a laptop.
        # The original generator priced everything 1000-100000 with no decimals.
        bands = {
            "Laptops": (650, 3200, 0.16), "Peripherals": (12, 260, 0.45),
            "Displays": (140, 1400, 0.24), "Furniture": (90, 1800, 0.38),
            "Audio": (25, 480, 0.40), "Networking": (30, 900, 0.30),
        }
        cur.execute("SELECT COALESCE(MAX(CAST(SUBSTRING(sku, 5) AS UNSIGNED)), 0) AS m "
                    "FROM product WHERE sku REGEXP '^[A-Z]{3}-[0-9]+$'")
        # int() matters: MySQL returns MAX(CAST(...)) as a Decimal, and a
        # Decimal cannot be formatted with :05d.
        start = int(cur.fetchone()["m"] or 0) + 1

        made = 0
        for i in range(n_products):
            cat = random.choice(cats)
            low, high, margin = bands.get(cat["name"], (20, 500, 0.30))
            price = round(random.uniform(low, high), 2)          # real cents
            cost = round(price * (1 - margin) * random.uniform(0.92, 1.06), 2)
            cost = max(0.01, min(cost, price))                   # never above price
            stock = random.randint(0, 400)
            cur.execute(
                """INSERT INTO product
                       (sku, name, brand, description, category_id, unit_price,
                        unit_cost, currency, stock_quantity, reorder_level,
                        is_active, created_at, updated_at)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, 'USD', %s, %s, %s, %s, %s)""",
                (f"{cat['name'][:3].upper()}-{start + i:05d}",
                 f"{fake.word().capitalize()} {fake.word().capitalize()}"[:200],
                 fake.company()[:100], fake.sentence(nb_words=10)[:1000],
                 cat["category_id"], price, cost, stock,
                 random.choice([0, 5, 10, 25]), random.random() < 0.93,
                 fake.date_time_between(start_date="-3y", end_date="-1d"),
                 datetime.now()),
            )
            made += 1
        conn.commit()
        print(f"catalogue: inserted {made} products across {len(cats)} categories")


def generate_orders(conn, n_orders, max_lines):
    with conn.cursor() as cur:
        print(f"orders: generating {n_orders}...")
        cur.execute("SELECT customer_id, signed_up_on FROM customer WHERE is_active = TRUE")
        customers = cur.fetchall()
        if not customers:
            print("orders: no customers — run the customer step first")
            return
        cur.execute("SELECT employee_id FROM employee WHERE is_active = TRUE")
        reps = [r["employee_id"] for r in cur.fetchall()]
        cur.execute("SELECT product_id, unit_price, unit_cost, stock_quantity "
                    "FROM product WHERE is_active = TRUE")
        products = cur.fetchall()
        if not products:
            print("orders: no products — run the catalogue step first")
            return
        # Addresses, grouped by customer, so the composite FK can be satisfied.
        cur.execute("SELECT address_id, customer_id, kind FROM customer_address")
        addr_by_cust = {}
        for a in cur.fetchall():
            addr_by_cust.setdefault(a["customer_id"], []).append(a)

        made = lines_made = 0
        for _ in range(n_orders):
            cust = random.choice(customers)
            signed = cust["signed_up_on"]
            if isinstance(signed, datetime):
                earliest = signed
            else:
                earliest = datetime.combine(signed, datetime.min.time())
            # *** An order cannot predate its customer. ***
            if earliest >= datetime.now() - timedelta(days=1):
                continue
            ordered = fake.date_time_between(start_date=earliest, end_date="now")

            status = pick_status()
            shipped = delivered = cancelled = None
            if status in ("shipped", "delivered"):
                shipped = ordered + timedelta(days=random.randint(1, 5),
                                              hours=random.randint(0, 23))
                if shipped > datetime.now():
                    shipped = datetime.now()
            if status == "delivered":
                base = shipped or ordered
                delivered = base + timedelta(days=random.randint(1, 7))
                if delivered > datetime.now():
                    delivered = datetime.now()
                if delivered < base:
                    delivered = base
            if status == "cancelled":
                cancelled = ordered + timedelta(days=random.randint(0, 3))
                if cancelled > datetime.now():
                    cancelled = datetime.now()

            chosen = random.sample(products, k=min(len(products),
                                                   random.randint(1, max_lines)))
            items_subtotal = sum(round(p["unit_price"] * 1, 2) for p in chosen)

            cur.execute(
                """INSERT INTO `order`
                       (customer_id, sales_rep_id, status, ordered_at, shipped_at,
                        delivered_at, cancelled_at, method, shipping_address_id,
                        billing_address_id, shipping_fee, tax_total, discount_total,
                        currency, notes, created_at, updated_at)
                   VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                           'USD', %s, %s, %s)""",
                (cust["customer_id"],
                 random.choice(reps) if reps and random.random() < 0.7 else None,
                 status, ordered, shipped, delivered, cancelled,
                 random.choice(METHODS),
                 # Must be an address OWNED BY THIS CUSTOMER — composite FK.
                 (lambda a: a["address_id"] if a else None)(
                     next((x for x in addr_by_cust.get(cust["customer_id"], [])
                           if x["kind"] == "shipping"), None)),
                 (lambda a: a["address_id"] if a else None)(
                     next((x for x in addr_by_cust.get(cust["customer_id"], [])
                           if x["kind"] == "billing"), None)),
                 round(random.choice([0, 0, 0, 7.5, 9.5, 12.0, 15.0]), 2),
                 round(float(items_subtotal) * random.uniform(0.0, 0.09), 2),
                 round(random.choice([0, 0, 0, 0, 10, 25, 50]), 2),
                 random.choice([None, None, None, fake.sentence(nb_words=6)[:1000]]),
                 ordered, datetime.now()),
            )
            order_id = cur.lastrowid
            made += 1

            for p in chosen:          # UNIQUE(order_id, product_id): sample, no repeats
                qty = random.randint(1, 5)
                disc = round(float(p["unit_price"]) * qty * random.choice([0, 0, 0, 0.05, 0.1]), 2)
                cur.execute(
                    """INSERT INTO order_item
                           (order_id, product_id, quantity, unit_price, unit_cost, discount)
                       VALUES (%s, %s, %s, %s, %s, %s)""",
                    # SNAPSHOT both price and cost. Never read these back from
                    # product later: the catalogue moves, history must not.
                    (order_id, p["product_id"], qty, p["unit_price"], p["unit_cost"], disc),
                )
                lines_made += 1
                if status not in ("cancelled", "refunded"):
                    cur.execute(
                        "UPDATE product SET stock_quantity = GREATEST(0, stock_quantity - %s) "
                        "WHERE product_id = %s",
                        (qty, p["product_id"]),
                    )
            if made % 500 == 0:
                conn.commit()
                print(f"orders: {made}/{n_orders}...")
        conn.commit()
        print(f"orders: inserted {made} with {lines_made} line items "
              f"({lines_made / made:.1f} per order)" if made else "orders: none")


def truncate(conn):
    """Children first, and FK checks off because `order` and customer_address
    reference each other through the composite key."""
    with conn.cursor() as cur:
        cur.execute("SET FOREIGN_KEY_CHECKS = 0")
        for t in ("order_status_history", "order_item", "`order`", "customer_address",
                  "customer", "product", "product_category", "employee"):
            cur.execute(f"DELETE FROM {t}")
        cur.execute("UPDATE order_number_seq SET last_number = 1000 WHERE only_row = 1")
        cur.execute("SET FOREIGN_KEY_CHECKS = 1")
    conn.commit()
    print("truncated all business tables and reset the order number counter")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--employees", type=int, default=25)
    ap.add_argument("--customers", type=int, default=200)
    ap.add_argument("--products", type=int, default=60)
    ap.add_argument("--orders", type=int, default=600)
    ap.add_argument("--max-lines", type=int, default=4, help="max line items per order")
    ap.add_argument("--truncate", action="store_true",
                    help="delete all business rows first (including the hand seed)")
    ap.add_argument("--seed", type=int, help="fix the RNG for a repeatable run")
    args = ap.parse_args()

    if args.seed is not None:
        random.seed(args.seed)
        Faker.seed(args.seed)

    conn = connect()
    try:
        print(f"==> {DB['user']}@{DB['host']}/{DB['database']}")
        if args.truncate:
            truncate(conn)
        emp_ids = generate_employees(conn, args.employees)
        customers = generate_customers(conn, args.customers, emp_ids)
        generate_addresses(conn, customers)
        generate_catalogue(conn, args.products)
        generate_orders(conn, args.orders, args.max_lines)

        with conn.cursor() as cur:
            cur.execute("""
                SELECT (SELECT COUNT(*) FROM employee)   AS employees,
                       (SELECT COUNT(*) FROM customer)   AS customers,
                       (SELECT COUNT(*) FROM customer_address) AS addresses,
                       (SELECT COUNT(*) FROM product)    AS products,
                       (SELECT COUNT(*) FROM `order`)    AS orders,
                       (SELECT COUNT(*) FROM order_item) AS order_items,
                       (SELECT COUNT(*) FROM order_status_history) AS history""")
            print("\n==> totals now in the database")
            for k, v in cur.fetchone().items():
                print(f"      {k:<12} {v}")
    except Exception as exc:
        conn.rollback()
        print(f"\n!!! rolled back: {exc}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()

# Employee Database

A MySQL / PostgreSQL schema for **Employee : Customer : Order : Product**, built to
sit underneath an Alexa-style voice assistant.

**There is one schema.** It lives in [`Employee Database/`](Employee%20Database/).

```bash
cd "Employee Database"
./load-mysql.sh                 # build the MySQL database (drops and recreates)
python3 generate_data.py        # pile volume on top of the hand-written seed
cd web && ./run-mysql.sh        # browse it at http://127.0.0.1:5002
```

## Layout

| Path | What it is |
|---|---|
| `Employee Database/sql-mysql/` | **the schema**, MySQL 8/9, numbered `01`..`08` |
| `Employee Database/sql/` | the same schema for PostgreSQL 14 — same 92 columns, verified to the cent |
| `Employee Database/generate_data.py` | bulk random data generator (Faker + PyMySQL) |
| `Employee Database/web/` | a small Flask viewer: orders, customers, margin, A/R, P&L |
| `Employee Database/PORTING.md` | what differs between the two engines, and why |
| `Employee Database/README.md` | the design rationale — read this first |

Both engine trees describe the **same 8 tables and the same 92 columns**; `sql/` is
not a second design. See `PORTING.md` for the handful of places an engine forced
a different mechanism.

## The two decisions the schema is built around

**1. An order has many line items.** `order` is the header; `order_item` holds the
lines. One order can contain a laptop and a mouse. Flattening `product_id` and
`quantity` onto the order row would make that two orders and break every
per-order figure.

**2. Money is snapshotted at the moment of sale.** `order_item.unit_price` and
`order_item.unit_cost` are frozen when the order is placed. Historical revenue
and gross profit read those, never `product.unit_price` / `product.unit_cost`,
which move with the catalogue and with supplier pricing.

Those two are what make revenue, margin, COGS, and A/R answerable at all.

## History

The previous project — a personalized news feed (GitHub Pages frontend +
Flask/TF-IDF backend on an Azure VM) — is preserved in full at tag
**`archive/v1`**:

    git show archive/v1:CLAUDE.md
    git checkout archive/v1

The earlier standalone `sql db` and `dummy_data.py` at this level were an
independent 2-table draft. They were folded into the single schema above; the
generator became `Employee Database/generate_data.py`. Recover them from git if
needed:

    git show 1c5f63f:'sql db'
    git show 1c5f63f:dummy_data.py

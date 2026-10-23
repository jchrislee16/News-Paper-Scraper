-- 04_views.sql — MySQL port. The answer surface.
--
-- These views exist mainly FOR the assistant. A voice question ("what did Maria
-- spend last month?") should become a one-table SELECT against a view, not a
-- five-way join the model has to invent. Every view is flat, fully labelled, and
-- pre-joined; the LLM picks a view, a filter, and an aggregate.
--
-- PORTING NOTES:
--
--   FILTER (WHERE p)  ->  SUM/COUNT/MAX(CASE WHEN p THEN x END)
--     21 sites. MySQL has no FILTER clause. The rewrite is mechanical BUT note
--     one trap that cost real money in the Postgres version: for a DISTINCT
--     count the CASE must sit INSIDE the DISTINCT --
--         COUNT(DISTINCT CASE WHEN p THEN o.order_id END)
--     not COUNT(DISTINCT o.order_id) wrapped in a CASE. Getting that backwards
--     reintroduces the average_order_value fan-out bug.
--
--   ::numeric(12,2)      ->  CAST(... AS DECIMAL(12,2))
--   date_trunc('day',x)::date -> DATE(x)
--   current_date - d     ->  DATEDIFF(CURRENT_DATE, d)
--   IS DISTINCT FROM     ->  NOT (a <=> b)      (MySQL NULL-safe equality)
--   fn_profit_and_loss() ->  sp_profit_and_loss()  *** NOW A PROCEDURE ***
--
-- Both helper functions are declared DETERMINISTIC so they can be created
-- without log_bin_trust_function_creators. They are pure, so this is honest.

-- ---------------------------------------------------------------------------
-- What counts as revenue.
--
-- Cancelled AND refunded orders are excluded from every revenue, unit and
-- customer-value figure below. This lives in one function rather than being
-- spelled out at each aggregate: the predicate was previously repeated eleven
-- times, which is how `refunded` came to be missing from all eleven. Adding a
-- new non-revenue status is now a one-line change here.
--
-- MySQL caveat: a function call in a view predicate is a black box to the
-- optimizer and will not be inlined the way Postgres inlines an IMMUTABLE SQL
-- function. That is a deliberate trade — the duplication it prevents is
-- exactly what caused the refunded-revenue bug.
DELIMITER $$

CREATE FUNCTION counts_as_revenue(s VARCHAR(20)) RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    -- `NOT (s <=> 'x')` is Postgres' `s IS DISTINCT FROM 'x'`: a NULL status
    -- counts as revenue, matching the original.
    RETURN NOT (s <=> 'cancelled') AND NOT (s <=> 'refunded');
END$$

-- Does this order still owe us money? Companion to counts_as_revenue(), and the
-- single place the pending-means-unpaid assumption is written down.
CREATE FUNCTION is_outstanding(s VARCHAR(20)) RETURNS BOOLEAN
DETERMINISTIC
BEGIN
    RETURN s <=> 'pending';
END$$

DELIMITER ;

-- One row per order, with money already totalled.
CREATE VIEW v_order_summary AS
SELECT
    o.order_id,
    o.order_number,
    o.status,
    o.ordered_at,
    o.shipped_at,
    o.delivered_at,
    o.method                          AS payment_method,
    c.customer_id,
    c.full_name                       AS customer_name,
    c.email                           AS customer_email,
    c.tier                            AS customer_tier,
    e.employee_id                     AS sales_rep_id,
    e.full_name                       AS sales_rep_name,
    COUNT(oi.order_item_id)           AS line_count,
    -- CAST AS SIGNED: MySQL returns SUM() over an INT column as DECIMAL, so
    -- without this a quantity of 2 reaches the front end as "2.00". Postgres
    -- returns bigint here. These are counts, not money.
    CAST(COALESCE(SUM(oi.quantity), 0) AS SIGNED) AS total_units,
    COALESCE(SUM(oi.line_total), 0)   AS items_subtotal,
    o.shipping_fee,
    o.tax_total,
    o.discount_total,
    COALESCE(SUM(oi.line_total), 0) + o.shipping_fee + o.tax_total - o.discount_total
                                      AS grand_total,
    o.currency
FROM `order` o
JOIN customer c         ON c.customer_id = o.customer_id
LEFT JOIN employee e    ON e.employee_id = o.sales_rep_id
LEFT JOIN order_item oi ON oi.order_id = o.order_id
GROUP BY o.order_id, c.customer_id, e.employee_id;

-- One row per line item, fully denormalised. "What was in order A-1003?"
CREATE VIEW v_order_line AS
SELECT
    oi.order_item_id,
    o.order_id,
    o.order_number,
    o.status,
    o.ordered_at,
    c.customer_id,
    c.full_name   AS customer_name,
    p.product_id,
    p.sku,
    p.name        AS product_name,
    p.brand,
    pc.name       AS category_name,
    oi.quantity,
    oi.unit_price,
    oi.discount,
    oi.line_total
FROM order_item oi
JOIN `order` o                ON o.order_id = oi.order_id
JOIN customer c               ON c.customer_id = o.customer_id
JOIN product p                ON p.product_id = oi.product_id
LEFT JOIN product_category pc ON pc.category_id = p.category_id;

-- Everything you'd want to say about a customer in one sentence.
CREATE VIEW v_customer_360 AS
SELECT
    c.customer_id,
    c.full_name       AS customer_name,
    c.email,
    c.phone,
    c.tier,
    c.signed_up_on,
    c.is_active,
    am.full_name      AS account_manager_name,
    COUNT(DISTINCT CASE WHEN counts_as_revenue(o.status) THEN o.order_id END) AS order_count,
    COALESCE(SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.line_total END), 0) AS lifetime_value,
    -- Mean value PER ORDER. Must not be AVG() over this query's rows: the
    -- order_item join multiplies each order by its line count, which weighted
    -- the old average toward many-line orders. sum/count is the per-order mean.
    CAST(COALESCE(
        SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.line_total END)
        / NULLIF(COUNT(DISTINCT CASE WHEN counts_as_revenue(o.status) THEN o.order_id END), 0),
        0) AS DECIMAL(12,2))                                       AS average_order_value,
    MIN(o.ordered_at) AS first_order_at,
    MAX(o.ordered_at) AS last_order_at,
    DATEDIFF(CURRENT_DATE, DATE(MAX(o.ordered_at)))                AS days_since_last_order
FROM customer c
LEFT JOIN `order` o     ON o.customer_id = c.customer_id
LEFT JOIN order_item oi ON oi.order_id = o.order_id
LEFT JOIN employee am   ON am.employee_id = c.account_manager_id
GROUP BY c.customer_id, am.employee_id;

-- Product side: what sells, what is about to run out.
CREATE VIEW v_product_performance AS
SELECT
    p.product_id,
    p.sku,
    p.name AS product_name,
    p.brand,
    pc.name AS category_name,
    p.unit_price AS current_price,
    p.unit_cost  AS current_cost,
    p.stock_quantity,
    -- Inventory carried at cost — the asset-side figure a balance sheet wants.
    CAST(p.stock_quantity * p.unit_cost AS DECIMAL(12,2)) AS inventory_value,
    p.reorder_level,
    (p.stock_quantity <= p.reorder_level) AS needs_restock,
    p.is_active,
    CAST(COALESCE(SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.quantity END), 0) AS SIGNED) AS units_sold,
    COALESCE(SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.line_total END), 0) AS revenue,
    -- Cost and margin use the order_item SNAPSHOT, never product.unit_cost, so
    -- historical profit does not move when supplier pricing changes.
    COALESCE(SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.line_cost END), 0)  AS cogs,
    COALESCE(SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.line_total - oi.line_cost END), 0)
                                                                                  AS gross_profit,
    ROUND(100 * COALESCE(SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.line_total - oi.line_cost END), 0)
              / NULLIF(SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.line_total END), 0), 1)
                                                                                  AS margin_pct,
    COUNT(DISTINCT CASE WHEN counts_as_revenue(o.status) THEN o.order_id END)      AS order_count,
    MAX(CASE WHEN counts_as_revenue(o.status) THEN o.ordered_at END)               AS last_sold_at
FROM product p
LEFT JOIN product_category pc ON pc.category_id = p.category_id
LEFT JOIN order_item oi       ON oi.product_id = p.product_id
LEFT JOIN `order` o           ON o.order_id = oi.order_id
GROUP BY p.product_id, pc.category_id;

-- Employee side: "how did Priya do this quarter?"
CREATE VIEW v_employee_sales AS
SELECT
    e.employee_id,
    e.full_name AS employee_name,
    e.job_title,
    e.department,
    m.full_name AS manager_name,
    e.is_active,
    COUNT(DISTINCT CASE WHEN counts_as_revenue(o.status) THEN o.order_id END)      AS orders_closed,
    COALESCE(SUM(CASE WHEN counts_as_revenue(o.status) THEN oi.line_total END), 0) AS revenue,
    COUNT(DISTINCT CASE WHEN counts_as_revenue(o.status) THEN o.customer_id END)   AS customers_served,
    MAX(o.ordered_at)                                                              AS last_order_at
FROM employee e
LEFT JOIN employee m    ON m.employee_id = e.manager_id
LEFT JOIN `order` o     ON o.sales_rep_id = e.employee_id
LEFT JOIN order_item oi ON oi.order_id = o.order_id
GROUP BY e.employee_id, m.employee_id;

-- Time series for "how are we doing this month vs last?"
CREATE VIEW v_daily_sales AS
SELECT
    DATE(o.ordered_at)                    AS sales_day,
    COUNT(DISTINCT o.order_id)            AS order_count,
    COALESCE(SUM(oi.line_total), 0)       AS revenue,
    CAST(COALESCE(SUM(oi.quantity), 0) AS SIGNED) AS units
FROM `order` o
LEFT JOIN order_item oi ON oi.order_id = o.order_id
WHERE counts_as_revenue(o.status)
GROUP BY DATE(o.ordered_at);

-- ---------------------------------------------------------------------------
-- ACCOUNTING REPORTS
--
-- Two QuickBooks-shaped reports: a receivables ledger ("who owes us what") and
-- a period profit-and-loss. Both are read-only derivations of the order tables;
-- there is no general ledger here and no double-entry.
--
-- Two honest limits, stated here because the reports look authoritative:
--   1. OPERATING EXPENSES ARE NOT MODELLED. Nothing in this schema records
--      payroll, rent, software or marketing spend, so the P&L stops at GROSS
--      profit. It is not net income and must not be presented as such.
--   2. PAYMENT IS INFERRED FROM FULFILMENT. There is no payment or invoice
--      table, so "unpaid" can only mean status = 'pending'. A real business
--      ships on terms, where payment and fulfilment move independently; that
--      needs a payment table before the aging buckets can be trusted.
-- ---------------------------------------------------------------------------

-- Customer Balance Detail: one row per open invoice, oldest first, with the
-- aging bucket a collections team would sort on.
CREATE VIEW v_customer_balance AS
SELECT
    v.customer_id,
    v.customer_name,
    v.customer_tier                                 AS tier,
    v.order_number                                  AS invoice,
    DATE(v.ordered_at)                              AS invoice_date,
    DATEDIFF(CURRENT_DATE, DATE(v.ordered_at))      AS days_outstanding,
    CASE
        WHEN DATEDIFF(CURRENT_DATE, DATE(v.ordered_at)) <= 30 THEN 'Current (0-30)'
        WHEN DATEDIFF(CURRENT_DATE, DATE(v.ordered_at)) <= 60 THEN 'Past due 31-60'
        WHEN DATEDIFF(CURRENT_DATE, DATE(v.ordered_at)) <= 90 THEN 'Past due 61-90'
        ELSE                                                       'Past due 90+'
    END                                             AS aging_bucket,
    v.items_subtotal,
    v.shipping_fee,
    v.tax_total,
    v.discount_total,
    v.grand_total                                   AS balance,
    COALESCE(v.sales_rep_name, '—')                 AS sales_rep
FROM v_order_summary v
WHERE is_outstanding(v.status);

-- A/R Aging Summary: the classic matrix, one row per customer who owes money.
CREATE VIEW v_ar_aging AS
SELECT
    b.customer_name,
    b.tier,
    COUNT(*)                                                                      AS open_invoices,
    COALESCE(SUM(CASE WHEN b.days_outstanding <= 30 THEN b.balance END), 0)       AS current_0_30,
    COALESCE(SUM(CASE WHEN b.days_outstanding BETWEEN 31 AND 60 THEN b.balance END), 0) AS past_due_31_60,
    COALESCE(SUM(CASE WHEN b.days_outstanding BETWEEN 61 AND 90 THEN b.balance END), 0) AS past_due_61_90,
    COALESCE(SUM(CASE WHEN b.days_outstanding >  90 THEN b.balance END), 0)       AS past_due_90_plus,
    SUM(b.balance)                                                                AS total_balance,
    MAX(b.days_outstanding)                                                       AS oldest_days
FROM v_customer_balance b
GROUP BY b.customer_name, b.tier;

-- ---------------------------------------------------------------------------
-- Profit and Loss for a period, laid out as report lines rather than columns so
-- it renders as a statement. Cancelled and refunded orders are excluded from
-- both revenue AND cost (a refund returns the goods), then shown as memo lines
-- so the money is visible rather than silently dropped.
--
-- *** PORTING LOSS — READ THIS ***
-- In Postgres this was fn_profit_and_loss(from, to) RETURNS TABLE, which meant
-- you could treat it as a relation:
--     SELECT * FROM fn_profit_and_loss('2026-01-01','2026-12-31')
--       WHERE section = 'TOTAL';
--     ... or join it, or wrap it in another view.
--
-- MySQL functions cannot return a result set (RETURNS TABLE is a syntax error),
-- so it is now a PROCEDURE. You CALL it and read the result:
--     CALL sp_profit_and_loss('2026-01-01','2026-12-31');
-- You CANNOT filter it, join it, or build a view on top of it. Any such
-- post-processing has to move into the caller (web/app.py does this).
-- ---------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_profit_and_loss(IN from_date DATE, IN to_date DATE)
READS SQL DATA
BEGIN
    WITH scope AS (
        SELECT o.order_id, o.shipping_fee, o.tax_total, o.discount_total
        FROM `order` o
        WHERE DATE(o.ordered_at) BETWEEN from_date AND to_date
          AND counts_as_revenue(o.status)
    ),
    item AS (
        SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS gross_sales,
               COALESCE(SUM(oi.discount), 0)                 AS line_discount,
               COALESCE(SUM(oi.line_cost), 0)                AS cogs
        FROM order_item oi JOIN scope s USING (order_id)
    ),
    -- renamed from `ord` in the Postgres original: ORD() is a MySQL function.
    ordsum AS (
        SELECT COUNT(*)                         AS order_count,
               COALESCE(SUM(shipping_fee), 0)   AS shipping,
               COALESCE(SUM(tax_total), 0)      AS tax,
               COALESCE(SUM(discount_total), 0) AS order_discount
        FROM scope
    ),
    dropped AS (
        SELECT COALESCE(SUM(CASE WHEN status = 'cancelled' THEN grand_total END), 0) AS cancelled_value,
               COALESCE(SUM(CASE WHEN status = 'refunded'  THEN grand_total END), 0) AS refunded_value
        FROM v_order_summary
        WHERE DATE(ordered_at) BETWEEN from_date AND to_date
    ),
    calc AS (
        SELECT i.*, o.*, d.*,
               i.gross_sales - i.line_discount - o.order_discount              AS net_sales,
               i.gross_sales - i.line_discount - o.order_discount + o.shipping AS total_income
        FROM item i CROSS JOIN ordsum o CROSS JOIN dropped d
    )
    -- MySQL has no `t(col, col, ...)` derived-table column aliasing, so the
    -- names are declared on the first branch of the UNION instead.
    SELECT * FROM (
        SELECT  1 AS line_no, 'Income' AS section, 'Product sales (gross)' AS line_item,
                gross_sales AS amount                                            FROM calc
        UNION ALL SELECT  2, 'Income', 'Less: line discounts',  -line_discount    FROM calc
        UNION ALL SELECT  3, 'Income', 'Less: order discounts', -order_discount   FROM calc
        UNION ALL SELECT  4, 'Income', 'Net product sales',      net_sales        FROM calc
        UNION ALL SELECT  5, 'Income', 'Shipping income',        shipping         FROM calc
        UNION ALL SELECT  6, 'TOTAL',  'Total income',           total_income     FROM calc
        UNION ALL SELECT  7, 'COGS',   'Cost of goods sold',     -cogs            FROM calc
        UNION ALL SELECT  8, 'TOTAL',  'GROSS PROFIT',           total_income - cogs FROM calc
        UNION ALL SELECT  9, 'TOTAL',  'Gross margin %',
                          ROUND(100 * (total_income - cogs) / NULLIF(total_income, 0), 1) FROM calc
        UNION ALL SELECT 10, 'Memo',   'Orders counted',         CAST(order_count AS DECIMAL(12,2)) FROM calc
        UNION ALL SELECT 11, 'Memo',   'Sales tax collected (a liability, not income)', tax FROM calc
        UNION ALL SELECT 12, 'Memo',   'Cancelled in period (excluded above)', cancelled_value FROM calc
        UNION ALL SELECT 13, 'Memo',   'Refunded in period (excluded above)',  refunded_value  FROM calc
        UNION ALL SELECT 14, 'Memo',
                          'Operating expenses are not modelled in this schema — bottom line is GROSS profit, not net income',
                          CAST(NULL AS DECIMAL(12,2))                            FROM calc
    ) t
    ORDER BY line_no;
END$$

DELIMITER ;

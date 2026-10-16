-- 04_views.sql — the answer surface.
--
-- These views exist mainly FOR the assistant. A voice question ("what did Maria
-- spend last month?") should become a one-table SELECT against a view, not a
-- five-way join the model has to invent. Every view is flat, fully labelled, and
-- pre-joined; the LLM picks a view, a filter, and an aggregate.

-- ---------------------------------------------------------------------------
-- What counts as revenue.
--
-- Cancelled AND refunded orders are excluded from every revenue, unit and
-- customer-value figure below. This lives in one function rather than being
-- spelled out at each aggregate: the predicate was previously repeated eleven
-- times, which is how `refunded` came to be missing from all eleven. Adding a
-- new non-revenue status is now a one-line change here.
CREATE OR REPLACE FUNCTION counts_as_revenue(s order_status) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT s IS DISTINCT FROM 'cancelled' AND s IS DISTINCT FROM 'refunded';
$$;

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
    count(oi.order_item_id)           AS line_count,
    coalesce(sum(oi.quantity), 0)     AS total_units,
    coalesce(sum(oi.line_total), 0)   AS items_subtotal,
    o.shipping_fee,
    o.tax_total,
    o.discount_total,
    coalesce(sum(oi.line_total), 0) + o.shipping_fee + o.tax_total - o.discount_total
                                      AS grand_total,
    o.currency
FROM "order" o
JOIN customer c        ON c.customer_id = o.customer_id
LEFT JOIN employee e   ON e.employee_id = o.sales_rep_id
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
JOIN "order" o             ON o.order_id = oi.order_id
JOIN customer c            ON c.customer_id = o.customer_id
JOIN product p             ON p.product_id = oi.product_id
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
    count(DISTINCT o.order_id) FILTER (WHERE counts_as_revenue(o.status))  AS order_count,
    coalesce(sum(oi.line_total) FILTER (WHERE counts_as_revenue(o.status)), 0) AS lifetime_value,
    -- Mean value PER ORDER. Must not be avg() over this query's rows: the
    -- order_item join multiplies each order by its line count, which weighted
    -- the old average toward many-line orders. sum/count is the per-order mean.
    coalesce(sum(oi.line_total) FILTER (WHERE counts_as_revenue(o.status))
             / nullif(count(DISTINCT o.order_id) FILTER (WHERE counts_as_revenue(o.status)), 0),
             0)::numeric(12,2)                                         AS average_order_value,
    min(o.ordered_at) AS first_order_at,
    max(o.ordered_at) AS last_order_at,
    (current_date - max(o.ordered_at)::date)                           AS days_since_last_order
FROM customer c
LEFT JOIN "order" o   ON o.customer_id = c.customer_id
LEFT JOIN order_item oi ON oi.order_id = o.order_id
LEFT JOIN employee am ON am.employee_id = c.account_manager_id
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
    (p.stock_quantity * p.unit_cost)::numeric(12,2) AS inventory_value,
    p.reorder_level,
    (p.stock_quantity <= p.reorder_level) AS needs_restock,
    p.is_active,
    coalesce(sum(oi.quantity) FILTER (WHERE counts_as_revenue(o.status)), 0)   AS units_sold,
    coalesce(sum(oi.line_total) FILTER (WHERE counts_as_revenue(o.status)), 0) AS revenue,
    -- Cost and margin use the order_item SNAPSHOT, never product.unit_cost, so
    -- historical profit does not move when supplier pricing changes.
    coalesce(sum(oi.line_cost) FILTER (WHERE counts_as_revenue(o.status)), 0)  AS cogs,
    coalesce(sum(oi.line_total - oi.line_cost) FILTER (WHERE counts_as_revenue(o.status)), 0)
                                                                              AS gross_profit,
    round(100 * coalesce(sum(oi.line_total - oi.line_cost) FILTER (WHERE counts_as_revenue(o.status)), 0)
              / nullif(sum(oi.line_total) FILTER (WHERE counts_as_revenue(o.status)), 0), 1)
                                                                              AS margin_pct,
    count(DISTINCT o.order_id) FILTER (WHERE counts_as_revenue(o.status))      AS order_count,
    max(o.ordered_at) FILTER (WHERE counts_as_revenue(o.status))               AS last_sold_at
FROM product p
LEFT JOIN product_category pc ON pc.category_id = p.category_id
LEFT JOIN order_item oi       ON oi.product_id = p.product_id
LEFT JOIN "order" o           ON o.order_id = oi.order_id
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
    count(DISTINCT o.order_id) FILTER (WHERE counts_as_revenue(o.status))      AS orders_closed,
    coalesce(sum(oi.line_total) FILTER (WHERE counts_as_revenue(o.status)), 0) AS revenue,
    count(DISTINCT o.customer_id) FILTER (WHERE counts_as_revenue(o.status))   AS customers_served,
    max(o.ordered_at)                                                      AS last_order_at
FROM employee e
LEFT JOIN employee m    ON m.employee_id = e.manager_id
LEFT JOIN "order" o     ON o.sales_rep_id = e.employee_id
LEFT JOIN order_item oi ON oi.order_id = o.order_id
GROUP BY e.employee_id, m.employee_id;

-- Time series for "how are we doing this month vs last?"
CREATE VIEW v_daily_sales AS
SELECT
    date_trunc('day', o.ordered_at)::date AS sales_day,
    count(DISTINCT o.order_id)            AS order_count,
    coalesce(sum(oi.line_total), 0)       AS revenue,
    coalesce(sum(oi.quantity), 0)         AS units
FROM "order" o
LEFT JOIN order_item oi ON oi.order_id = o.order_id
WHERE counts_as_revenue(o.status)
GROUP BY 1;

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

-- Does this order still owe us money? Companion to counts_as_revenue(), and the
-- single place the pending-means-unpaid assumption above is written down.
CREATE OR REPLACE FUNCTION is_outstanding(s order_status) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT s = 'pending';
$$;

-- Customer Balance Detail: one row per open invoice, oldest first, with the
-- aging bucket a collections team would sort on.
CREATE VIEW v_customer_balance AS
SELECT
    v.customer_id,
    v.customer_name,
    v.customer_tier                      AS tier,
    v.order_number                       AS invoice,
    v.ordered_at::date                   AS invoice_date,
    (current_date - v.ordered_at::date)  AS days_outstanding,
    CASE
        WHEN current_date - v.ordered_at::date <=  30 THEN 'Current (0-30)'
        WHEN current_date - v.ordered_at::date <=  60 THEN 'Past due 31-60'
        WHEN current_date - v.ordered_at::date <=  90 THEN 'Past due 61-90'
        ELSE                                              'Past due 90+'
    END                                  AS aging_bucket,
    v.items_subtotal,
    v.shipping_fee,
    v.tax_total,
    v.discount_total,
    v.grand_total                        AS balance,
    coalesce(v.sales_rep_name, '—')      AS sales_rep
FROM v_order_summary v
WHERE is_outstanding(v.status);

-- A/R Aging Summary: the classic matrix, one row per customer who owes money.
CREATE VIEW v_ar_aging AS
SELECT
    b.customer_name,
    b.tier,
    count(*)                                                                  AS open_invoices,
    coalesce(sum(b.balance) FILTER (WHERE b.days_outstanding <=  30), 0)      AS current_0_30,
    coalesce(sum(b.balance) FILTER (WHERE b.days_outstanding BETWEEN 31 AND 60), 0) AS past_due_31_60,
    coalesce(sum(b.balance) FILTER (WHERE b.days_outstanding BETWEEN 61 AND 90), 0) AS past_due_61_90,
    coalesce(sum(b.balance) FILTER (WHERE b.days_outstanding >  90), 0)       AS past_due_90_plus,
    sum(b.balance)                                                           AS total_balance,
    max(b.days_outstanding)                                                  AS oldest_days
FROM v_customer_balance b
GROUP BY b.customer_name, b.tier;

-- Profit and Loss for a period, laid out as report lines rather than columns so
-- it renders as a statement. Cancelled and refunded orders are excluded from
-- both revenue AND cost (a refund returns the goods), then shown as memo lines
-- so the money is visible rather than silently dropped.
CREATE OR REPLACE FUNCTION fn_profit_and_loss(from_date date, to_date date)
RETURNS TABLE (line_no integer, section text, line_item text, amount numeric)
LANGUAGE sql STABLE AS $$
    WITH scope AS (
        SELECT o.order_id, o.shipping_fee, o.tax_total, o.discount_total
        FROM "order" o
        WHERE o.ordered_at::date BETWEEN from_date AND to_date
          AND counts_as_revenue(o.status)
    ),
    item AS (
        SELECT coalesce(sum(oi.quantity * oi.unit_price), 0) AS gross_sales,
               coalesce(sum(oi.discount), 0)                 AS line_discount,
               coalesce(sum(oi.line_cost), 0)                AS cogs
        FROM order_item oi JOIN scope s USING (order_id)
    ),
    ord AS (
        SELECT count(*)                         AS order_count,
               coalesce(sum(shipping_fee), 0)   AS shipping,
               coalesce(sum(tax_total), 0)      AS tax,
               coalesce(sum(discount_total), 0) AS order_discount
        FROM scope
    ),
    dropped AS (
        SELECT coalesce(sum(grand_total) FILTER (WHERE status = 'cancelled'), 0) AS cancelled_value,
               coalesce(sum(grand_total) FILTER (WHERE status = 'refunded'), 0)  AS refunded_value
        FROM v_order_summary
        WHERE ordered_at::date BETWEEN from_date AND to_date
    ),
    calc AS (
        SELECT i.*, o.*, d.*,
               i.gross_sales - i.line_discount - o.order_discount               AS net_sales,
               i.gross_sales - i.line_discount - o.order_discount + o.shipping  AS total_income
        FROM item i CROSS JOIN ord o CROSS JOIN dropped d
    )
    SELECT * FROM (
        SELECT  1, 'Income', 'Product sales (gross)',   gross_sales                    FROM calc
        UNION ALL SELECT  2, 'Income', 'Less: line discounts',  -line_discount          FROM calc
        UNION ALL SELECT  3, 'Income', 'Less: order discounts', -order_discount         FROM calc
        UNION ALL SELECT  4, 'Income', 'Net product sales',      net_sales              FROM calc
        UNION ALL SELECT  5, 'Income', 'Shipping income',        shipping               FROM calc
        UNION ALL SELECT  6, 'TOTAL',  'Total income',           total_income           FROM calc
        UNION ALL SELECT  7, 'COGS',   'Cost of goods sold',     -cogs                  FROM calc
        UNION ALL SELECT  8, 'TOTAL',  'GROSS PROFIT',           total_income - cogs    FROM calc
        UNION ALL SELECT  9, 'TOTAL',  'Gross margin %',
                          round(100 * (total_income - cogs) / nullif(total_income, 0), 1) FROM calc
        UNION ALL SELECT 10, 'Memo',   'Orders counted',         order_count::numeric   FROM calc
        UNION ALL SELECT 11, 'Memo',   'Sales tax collected (a liability, not income)', tax FROM calc
        UNION ALL SELECT 12, 'Memo',   'Cancelled in period (excluded above)', cancelled_value FROM calc
        UNION ALL SELECT 13, 'Memo',   'Refunded in period (excluded above)',  refunded_value  FROM calc
        UNION ALL SELECT 14, 'Memo',
                          'Operating expenses are not modelled in this schema — bottom line is GROSS profit, not net income',
                          NULL::numeric                                                FROM calc
    ) t(line_no, section, line_item, amount)
    ORDER BY line_no;
$$;

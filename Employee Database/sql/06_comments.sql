-- 06_comments.sql — schema documentation AS assistant training data.
--
-- These COMMENTs are not decoration: ai.schema_context reads them straight out of
-- the catalogue and they become part of the model's system prompt. Write them for
-- a reader who has never seen the data and must not guess. Prefer stating the trap
-- ("this is a snapshot, do not join to the catalogue price") over restating the name.

COMMENT ON TABLE employee IS
  'Staff. Sales reps are linked from "order".sales_rep_id; account managers from customer.account_manager_id. manager_id is a self-reference forming the reporting tree.';
COMMENT ON COLUMN employee.full_name IS 'Generated "First Last". Use this for name matching, not first_name/last_name separately.';
COMMENT ON COLUMN employee.is_active IS 'false = has left the company. Historical orders keep pointing at them; exclude inactive staff from "who works here" questions but NOT from historical sales totals.';

COMMENT ON TABLE customer IS
  'People who place orders. One row per person; addresses live in customer_address, purchases in "order".';
COMMENT ON COLUMN customer.tier IS 'Loyalty tier: standard < silver < gold < platinum. Set by the business, not derived from spend.';
COMMENT ON COLUMN customer.account_manager_id IS 'Employee who owns the relationship. Different from the sales rep on any individual order.';
COMMENT ON COLUMN customer.email IS 'citext: comparisons are case-insensitive, no need for lower().';

COMMENT ON TABLE customer_address IS 'Addresses belonging to a customer. kind separates billing from shipping; is_default marks the one to assume when the caller does not say which.';
COMMENT ON COLUMN customer_address.label IS 'The name a person uses out loud for this address: "home", "the office", "mum''s place".';

COMMENT ON TABLE product_category IS 'Product taxonomy. parent_category_id allows nesting; top-level categories have it NULL.';
COMMENT ON TABLE product IS 'Sellable catalogue. unit_price here is the CURRENT price and changes over time.';
COMMENT ON COLUMN product.unit_price IS 'Current catalogue price. For what a customer actually paid, use order_item.unit_price instead — never this column.';
COMMENT ON COLUMN product.unit_cost IS 'What WE pay per unit. CURRENT cost; moves with supplier pricing. For historical gross profit use order_item.unit_cost instead — never this column.';
COMMENT ON COLUMN product.stock_quantity IS 'Units on hand right now. Compare against reorder_level for restock questions.';
COMMENT ON COLUMN product.search_document IS 'Full-text index of name + brand + description. Query with @@ plainto_tsquery(''english'', ...) for vague descriptions.';

COMMENT ON TABLE "order" IS
  'A purchase. Quoted identifier: ORDER is a reserved word, so it must be written "order" in every query. Money totals are NOT stored here — use v_order_summary.grand_total.';
COMMENT ON COLUMN "order".order_number IS 'Human-facing reference like A-1042. This is what people say out loud; order_id is internal.';
COMMENT ON COLUMN "order".status IS 'Lifecycle state. Cancelled and refunded orders should normally be EXCLUDED from revenue questions.';
COMMENT ON COLUMN "order".sales_rep_id IS 'Employee credited with this order. NULL for self-serve web orders.';
COMMENT ON COLUMN "order".shipping_fee IS 'Added to the item subtotal. Not part of order_item line totals.';
COMMENT ON COLUMN "order".discount_total IS 'Order-level discount, subtracted from the total. Line-level discounts live in order_item.discount and are already inside line_total.';

COMMENT ON TABLE order_item IS 'Line items. One row per product per order.';
COMMENT ON COLUMN order_item.unit_price IS 'PRICE SNAPSHOT at the moment of ordering. Historical revenue must use this, never product.unit_price.';
COMMENT ON COLUMN order_item.unit_cost IS 'COST SNAPSHOT at the moment of ordering, the cost-side twin of unit_price. Historical gross profit must use this, never product.unit_cost.';
COMMENT ON COLUMN order_item.line_cost IS 'Generated: quantity * unit_cost. Note no discount term — a customer discount reduces our revenue, not our cost. Sum this for cost of goods sold.';
COMMENT ON COLUMN order_item.line_total IS 'Generated: quantity * unit_price - discount. Sum this for revenue.';

COMMENT ON TABLE order_status_history IS 'Append-only audit of status transitions, written automatically by a trigger. Answers "when did it ship" and "was this ever cancelled".';

COMMENT ON VIEW v_order_summary IS 'ONE ROW PER ORDER with customer, rep and money already totalled. Default starting point for any order question. grand_total = items + shipping + tax - order discount.';
COMMENT ON VIEW v_order_line IS 'One row per line item, fully denormalised with product and customer names. Use for "what was in that order" and per-product breakdowns.';
COMMENT ON VIEW v_customer_360 IS 'One row per customer with order_count, lifetime_value, average_order_value and recency. Cancelled AND refunded orders are already excluded from the money and count columns. average_order_value is per order, not per line item. Caveat: first_order_at/last_order_at/days_since_last_order count every order including cancelled and refunded ones.';
COMMENT ON VIEW v_product_performance IS 'One row per product with units_sold, revenue, cogs, gross_profit, margin_pct, inventory_value and needs_restock. Cancelled AND refunded orders already excluded. Use this to break down where the P&L gross profit came from, by product or category.';
COMMENT ON VIEW v_employee_sales IS 'One row per employee with orders_closed and revenue attributed as sales rep. Cancelled AND refunded orders already excluded.';
COMMENT ON VIEW v_daily_sales IS 'Revenue and order count per calendar day, cancelled and refunded orders excluded. Use for trends and period comparisons.';

COMMENT ON VIEW v_customer_balance IS 'ACCOUNTS RECEIVABLE DETAIL: one row per unpaid invoice with an aging bucket. "Unpaid" means status = ''pending'' — there is no payment table, so this is inferred from fulfilment state, not observed. Use for "who owes us money" and "what is overdue".';
COMMENT ON VIEW v_ar_aging IS 'A/R aging summary: one row per customer owing money, with balances bucketed Current/31-60/61-90/90+. Derived from v_customer_balance; same pending-means-unpaid caveat.';
COMMENT ON FUNCTION is_outstanding(order_status) IS 'True when an order still owes money (status = ''pending''). Companion to counts_as_revenue(); the one place the pending-means-unpaid assumption is written down.';
COMMENT ON FUNCTION fn_profit_and_loss(date, date) IS 'PROFIT AND LOSS for a date range, returned as report lines (line_no, section, line_item, amount) rather than columns. Call as SELECT * FROM fn_profit_and_loss(''2026-01-01'',''2026-12-31''). Cancelled and refunded orders are excluded from revenue AND cost, then shown as memo lines. IMPORTANT: operating expenses are not modelled anywhere in this schema, so the bottom line is GROSS PROFIT, not net income — never report it as net income or profit after expenses. Sales tax is a liability, not income.';
COMMENT ON SCHEMA ai IS 'Voice-assistant support: entity resolution, conversation logs, and the self-describing schema prompt. Business data never lives here.';
COMMENT ON TABLE ai.entity_alias IS 'Spoken alternatives for a row (nicknames, abbreviations, recurring speech-recognition errors). entity_id is polymorphic — interpret it with entity_type.';
COMMENT ON TABLE ai.intent IS 'Catalogue of supported questions with sample utterances and a vetted sql_template. Prefer parameterising a template over authoring new SQL.';
COMMENT ON TABLE ai.voice_session IS 'One conversation. context holds the last-mentioned entities so follow-ups like "and his last order?" can be resolved.';
COMMENT ON TABLE ai.utterance IS 'One spoken turn: transcript, detected intent, resolved entities, generated SQL and outcome. The record used to debug and improve the assistant.';
COMMENT ON VIEW ai.schema_context IS 'The live schema prompt. SELECT this to build the model system prompt instead of maintaining a hand-written schema string.';
COMMENT ON VIEW ai.enum_values IS 'Every legal ENUM value. Map spoken words onto these instead of inventing string literals.';

COMMENT ON FUNCTION counts_as_revenue(order_status) IS 'True when an order should be counted in revenue: everything except cancelled and refunded. Single source of truth for the v_* money columns -- filter with this rather than writing a status list.';

COMMENT ON FUNCTION ai.resolve_customer(text, numeric) IS 'Spoken phrase -> candidate customers, ranked. Handles aliases, exact names, trigram typos and phonetic near-misses. Re-prompt the caller when the top two scores are close.';
COMMENT ON FUNCTION ai.resolve_product(text, numeric) IS 'Spoken phrase -> candidate products, ranked. Also matches vague descriptions via full-text search.';
COMMENT ON FUNCTION ai.resolve_employee(text, numeric) IS 'Spoken phrase -> candidate employees, ranked.';
COMMENT ON FUNCTION ai.resolve_order(text) IS 'Spoken order reference in any shape ("A-1003", "a1003", "1003") -> matching orders.';

-- ---------------------------------------------------------------------------
-- ai.object_doc — the same rows the MySQL port keeps, carried here too.
--
-- Redundant on Postgres: the COMMENT ON VIEW statements above already reach
-- ai.schema_context. It is populated anyway so both engines return the same
-- table_purpose text for every view, and so adding a view means adding its
-- description in one place that works on either engine.
-- ---------------------------------------------------------------------------
INSERT INTO ai.object_doc (object_name, object_type, purpose) VALUES
('v_order_summary','view',
 'ONE ROW PER ORDER with customer, rep and money already totalled. Default starting point for any order question. grand_total = items + shipping + tax - order discount.'),
('v_order_line','view',
 'One row per line item, fully denormalised with product and customer names. Use for "what was in that order" and per-product breakdowns.'),
('v_customer_360','view',
 'One row per customer with order_count, lifetime_value, average_order_value and recency. Cancelled AND refunded orders are already excluded from the money and count columns. average_order_value is per order, not per line item. Caveat: first_order_at/last_order_at/days_since_last_order count every order including cancelled and refunded ones.'),
('v_product_performance','view',
 'One row per product with units_sold, revenue, cogs, gross_profit, margin_pct, inventory_value and needs_restock. Cancelled AND refunded orders already excluded. Use this to break down where the P&L gross profit came from, by product or category.'),
('v_employee_sales','view',
 'One row per employee with orders_closed and revenue attributed as sales rep. Cancelled AND refunded orders already excluded.'),
('v_daily_sales','view',
 'Revenue and order count per calendar day, cancelled and refunded orders excluded. Use for trends and period comparisons.'),
('v_customer_balance','view',
 'ACCOUNTS RECEIVABLE DETAIL: one row per unpaid invoice with an aging bucket. "Unpaid" means status = ''pending'' — there is no payment table, so this is inferred from fulfilment state, not observed. Use for "who owes us money" and "what is overdue".'),
('v_ar_aging','view',
 'A/R aging summary: one row per customer owing money, with balances bucketed Current/31-60/61-90/90+. Derived from v_customer_balance; same pending-means-unpaid caveat.'),
-- These three are named without the ai_ prefix because on Postgres the schema
-- carries it: information_schema reports table_name = 'schema_context' in
-- schema 'ai'. The MySQL port stores them as 'ai_schema_context' etc., which is
-- the same uniform ai.X <-> ai_X mapping used for every object in this schema.
('schema_context','view',
 'The live schema prompt. SELECT this to build the model system prompt instead of maintaining a hand-written schema string. Reads table/column COMMENTs from the catalogue, and view descriptions from ai.object_doc.'),
('enum_values','view',
 'Every legal ENUM value. Map spoken words onto these instead of inventing string literals.'),
('v_failure_review','view',
 'What is going wrong, most-common first. Feed this back into aliases and intents.'),
('ai','schema',
 'Voice-assistant support: entity resolution, conversation logs, and the self-describing schema prompt. Business data never lives here.');

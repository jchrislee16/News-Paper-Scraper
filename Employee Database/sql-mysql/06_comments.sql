-- 06_comments.sql — MySQL port. Schema documentation AS assistant training data.
--
-- These COMMENTs are not decoration: ai_schema_context reads them straight out
-- of information_schema and they become part of the model's system prompt. Write
-- them for a reader who has never seen the data and must not guess. Prefer
-- stating the trap ("this is a snapshot, do not join to the catalogue price")
-- over restating the name.
--
-- PORTING NOTES:
--
--   COMMENT ON TABLE t IS '...'      -> ALTER TABLE t COMMENT = '...'
--   COMMENT ON COLUMN t.c IS '...'   -> ALTER TABLE t MODIFY COLUMN c <FULL
--                                       DEFINITION> COMMENT '...'
--     *** MAINTENANCE HAZARD: MySQL makes you restate the ENTIRE column
--     definition to change its comment. If you alter a column's type, default
--     or nullability in 02_core_tables.sql you MUST mirror it here, or loading
--     this file will silently revert the change. The definitions below were
--     generated from the live schema, not typed by hand. ***
--
--   COMMENT ON VIEW v IS '...'       -> NOT POSSIBLE. MySQL has no way to
--                                       comment a view. Stored in the
--                                       ai_object_doc table instead, which
--                                       ai_schema_context joins back in.
--   COMMENT ON FUNCTION f IS '...'   -> ALTER FUNCTION/PROCEDURE f COMMENT '...'
--   COMMENT ON SCHEMA ai IS '...'    -> no schemas; recorded in ai_object_doc.
--
-- Several comment TEXTS also changed, because the Postgres wording is now
-- factually wrong for this database. Those are called out inline. Leaving them
-- as-written would teach the model things that are no longer true, which is
-- worse than having no comment at all.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
ALTER TABLE employee COMMENT =
  'Staff. Sales reps are linked from `order`.sales_rep_id; account managers from customer.account_manager_id. manager_id is a self-reference forming the reporting tree.';

ALTER TABLE customer COMMENT =
  'People who place orders. One row per person; addresses live in customer_address, purchases in `order`.';

ALTER TABLE customer_address COMMENT =
  'Addresses belonging to a customer. kind separates billing from shipping; is_default marks the one to assume when the caller does not say which. At most one default per customer per kind, enforced by a UNIQUE index on the generated default_key column.';

ALTER TABLE product_category COMMENT =
  'Product taxonomy. parent_category_id allows nesting; top-level categories have it NULL.';

-- CHANGED: the Postgres version documented a search_document tsvector column
-- here. That column does not exist in MySQL; full-text search moved to an index.
ALTER TABLE product COMMENT =
  'Sellable catalogue. unit_price here is the CURRENT price and changes over time. For vague descriptive searches ("anything like a standing desk?") use MATCH(name, brand, description) AGAINST (''...'' IN NATURAL LANGUAGE MODE) — there is no tsvector column, the FULLTEXT index product_search_idx serves this.';

ALTER TABLE `order` COMMENT =
  'A purchase. ORDER is a reserved word, so this table must be written with backticks as `order` in every query. Money totals are NOT stored here — use v_order_summary.grand_total.';

ALTER TABLE order_item COMMENT =
  'Line items. One row per product per order.';

ALTER TABLE order_status_history COMMENT =
  'Append-only audit of status transitions, written automatically by triggers on `order`. Answers "when did it ship" and "was this ever cancelled". Note changed_by is always NULL until the application supplies it.';

ALTER TABLE order_number_seq COMMENT =
  'Internal counter standing in for a Postgres SEQUENCE. One row. Read and incremented by the order_number_assign trigger to mint order numbers like A-1042. Not business data; ignore it when answering questions.';

ALTER TABLE ai_entity_alias COMMENT =
  'Spoken alternatives for a row (nicknames, abbreviations, recurring speech-recognition errors). entity_id is polymorphic — interpret it with entity_type.';

ALTER TABLE ai_intent COMMENT =
  'Catalogue of supported questions with sample utterances and a vetted sql_template. Prefer parameterising a template over authoring new SQL. sample_utterances and required_slots are JSON arrays (they were text[] in Postgres).';

ALTER TABLE ai_voice_session COMMENT =
  'One conversation. context is a JSON object holding the last-mentioned entities so follow-ups like "and his last order?" can be resolved.';

ALTER TABLE ai_utterance COMMENT =
  'One spoken turn: transcript, detected intent, resolved entities, generated SQL and outcome. The record used to debug and improve the assistant.';

ALTER TABLE ai_object_doc COMMENT =
  'Documentation for views and routines. Exists only because MySQL cannot attach a COMMENT to a view. ai_schema_context joins this in so view descriptions still reach the model prompt.';

-- ---------------------------------------------------------------------------
-- Columns. Definitions below are generated from the live schema — see the
-- MAINTENANCE HAZARD note at the top before editing any of them.
-- ---------------------------------------------------------------------------
ALTER TABLE employee
  MODIFY COLUMN full_name VARCHAR(201) GENERATED ALWAYS AS
      (TRIM(CONCAT(COALESCE(first_name,''), ' ', COALESCE(last_name,'')))) STORED
      COMMENT 'Generated "First Last". Use this for name matching, not first_name/last_name separately.',
  MODIFY COLUMN is_active TINYINT(1) NOT NULL DEFAULT '1'
      COMMENT 'false = has left the company. Historical orders keep pointing at them; exclude inactive staff from "who works here" questions but NOT from historical sales totals.';

ALTER TABLE customer
  MODIFY COLUMN tier ENUM('standard','silver','gold','platinum') NOT NULL DEFAULT 'standard'
      COMMENT 'Loyalty tier: standard < silver < gold < platinum. Set by the business, not derived from spend.',
  MODIFY COLUMN account_manager_id BIGINT DEFAULT NULL
      COMMENT 'Employee who owns the relationship. Different from the sales rep on any individual order.',
  -- CHANGED: was 'citext: comparisons are case-insensitive'. There is no citext
  -- in MySQL; the same behaviour comes from the collation instead.
  MODIFY COLUMN email VARCHAR(255) NOT NULL
      COMMENT 'Case-insensitive because the column collation is utf8mb4_0900_ai_ci, so no need for LOWER() when comparing. UNIQUE, so Bob@x.com and bob@x.com cannot both exist.';

ALTER TABLE customer_address
  MODIFY COLUMN label VARCHAR(100) DEFAULT NULL
      COMMENT 'The name a person uses out loud for this address: "home", "the office", "mum''s place".';

ALTER TABLE product
  MODIFY COLUMN unit_price DECIMAL(12,2) NOT NULL
      COMMENT 'Current catalogue price. For what a customer actually paid, use order_item.unit_price instead — never this column.',
  MODIFY COLUMN unit_cost DECIMAL(12,2) NOT NULL DEFAULT '0.00'
      COMMENT 'What WE pay per unit. CURRENT cost; moves with supplier pricing. For historical gross profit use order_item.unit_cost instead — never this column.',
  MODIFY COLUMN stock_quantity INT NOT NULL DEFAULT '0'
      COMMENT 'Units on hand right now. Compare against reorder_level for restock questions. Note nothing decrements this when an order is placed.';

ALTER TABLE `order`
  MODIFY COLUMN order_number VARCHAR(20) NOT NULL
      COMMENT 'Human-facing reference like A-1042. This is what people say out loud; order_id is internal. Assigned by the order_number_assign trigger, not a DEFAULT.',
  MODIFY COLUMN status ENUM('pending','paid','packed','shipped','delivered','cancelled','refunded') NOT NULL DEFAULT 'pending'
      COMMENT 'Lifecycle state. Cancelled and refunded orders should normally be EXCLUDED from revenue questions — filter with counts_as_revenue(status).',
  MODIFY COLUMN sales_rep_id BIGINT DEFAULT NULL
      COMMENT 'Employee credited with this order. NULL for self-serve web orders.',
  MODIFY COLUMN shipping_fee DECIMAL(12,2) NOT NULL DEFAULT '0.00'
      COMMENT 'Added to the item subtotal. Not part of order_item line totals.',
  MODIFY COLUMN discount_total DECIMAL(12,2) NOT NULL DEFAULT '0.00'
      COMMENT 'Order-level discount, subtracted from the total. Line-level discounts live in order_item.discount and are already inside line_total.';

ALTER TABLE order_item
  MODIFY COLUMN unit_price DECIMAL(12,2) NOT NULL
      COMMENT 'PRICE SNAPSHOT at the moment of ordering. Historical revenue must use this, never product.unit_price.',
  MODIFY COLUMN unit_cost DECIMAL(12,2) NOT NULL DEFAULT '0.00'
      COMMENT 'COST SNAPSHOT at the moment of ordering, the cost-side twin of unit_price. Historical gross profit must use this, never product.unit_cost.',
  MODIFY COLUMN line_total DECIMAL(12,2) GENERATED ALWAYS AS ((quantity * unit_price) - discount) STORED
      COMMENT 'Generated: quantity * unit_price - discount. Sum this for revenue.',
  MODIFY COLUMN line_cost DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_cost) STORED
      COMMENT 'Generated: quantity * unit_cost. Note no discount term — a customer discount reduces our revenue, not our cost. Sum this for cost of goods sold.';

-- ---------------------------------------------------------------------------
-- Routines. MySQL supports these natively via ALTER ... COMMENT.
-- ---------------------------------------------------------------------------
ALTER FUNCTION counts_as_revenue COMMENT
  'True when an order should be counted in revenue: everything except cancelled and refunded. Single source of truth for the v_* money columns -- filter with this rather than writing a status list.';

ALTER FUNCTION is_outstanding COMMENT
  'True when an order still owes money (status = ''pending''). Companion to counts_as_revenue(); the one place the pending-means-unpaid assumption is written down.';

-- CHANGED: was a FUNCTION you could SELECT FROM. It is a PROCEDURE now, so the
-- call syntax in this comment had to change or the model would generate SQL
-- that errors.
ALTER PROCEDURE fn_profit_and_loss COMMENT
  'PROFIT AND LOSS for a date range, returned as report lines (line_no, section, line_item, amount) rather than columns. Call as CALL fn_profit_and_loss(''2026-01-01'',''2026-12-31''). It is a PROCEDURE, not a function: you cannot SELECT FROM it, filter it, or join it — read the full result and post-process in the application. Cancelled and refunded orders are excluded from revenue AND cost, then shown as memo lines. IMPORTANT: operating expenses are not modelled anywhere in this schema, so the bottom line is GROSS PROFIT, not net income — never report it as net income or profit after expenses. Sales tax is a liability, not income.';

-- CHANGED, and this one matters most. The Postgres comment promised "trigram
-- typos", which this database can no longer do. Advertising a capability the
-- resolver does not have would make the model over-trust a weak match.
ALTER PROCEDURE ai_resolve_customer COMMENT
  'Spoken phrase -> candidate customers, ranked (score, reason). Call as CALL ai_resolve_customer(''jon smyth'', NULL) — pass NULL for the default min_score of 0.35. Matches curated aliases, exact name, exact email, name prefix, name substring, SOUNDEX of the whole name, and SOUNDEX of the first/last word. IT DOES NOT DO TRIGRAM OR EDIT-DISTANCE MATCHING: MySQL has no similarity(), so scores are discrete tiers, not a continuous confidence. A misspelling that is not caught by prefix, substring or SOUNDEX returns NOTHING rather than a low score. Re-prompt the caller when the top two scores are close, and do not assume a miss means the customer does not exist.';

ALTER PROCEDURE ai_resolve_product COMMENT
  'Spoken phrase -> candidate products, ranked (score, reason). Call as CALL ai_resolve_product(''wireless mouse'', NULL) — NULL means the default min_score of 0.30. Matches aliases, exact SKU, exact name, prefix, substring, FULLTEXT over name+brand+description for vague descriptions, SOUNDEX, and word match. Same limitation as ai_resolve_customer: no trigram/edit-distance tier, so misspellings can miss entirely.';

ALTER PROCEDURE ai_resolve_employee COMMENT
  'Spoken phrase -> candidate employees, ranked (score, reason). Call as CALL ai_resolve_employee(''priya'', NULL) for the default min_score of 0.35. Same tiers and same no-trigram limitation as ai_resolve_customer.';

ALTER PROCEDURE ai_resolve_order COMMENT
  'Spoken order reference in any shape ("A-1003", "a1003", "1003") -> matching orders. Call as CALL ai_resolve_order(''a1003''). This one ported from Postgres without loss; it is exact matching on a punctuation-stripped order number.';

-- ---------------------------------------------------------------------------
-- Views and the former `ai` schema. MySQL cannot comment a view, so these go
-- into ai_object_doc, which ai_schema_context joins back in.
-- ---------------------------------------------------------------------------
INSERT INTO ai_object_doc (object_name, object_type, purpose) VALUES
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
('ai_schema_context','view',
 'The live schema prompt. SELECT this to build the model system prompt instead of maintaining a hand-written schema string. Reads table/column COMMENTs from information_schema, and view descriptions from ai_object_doc.'),
('ai_enum_values','view',
 'Every legal ENUM value. Map spoken words onto these instead of inventing string literals. Because MySQL enums are inline rather than named types, enum_name is table.column and the same vocabulary appears more than once (e.g. order.status and ai_utterance.new_status).'),
('ai_v_failure_review','view',
 'What is going wrong, most-common first. Feed this back into aliases and intents. recent_transcripts is the 5 most recent, separated by " ~ ", and is capped by group_concat_max_len.'),
('ai','schema',
 'The ai_* prefixed tables and views are voice-assistant support: entity resolution, conversation logs, and the self-describing schema prompt. Business data never lives in them. In Postgres these were a separate `ai` schema; MySQL has no schemas inside a database, hence the prefix.');

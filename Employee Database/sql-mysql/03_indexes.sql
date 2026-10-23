-- 03_indexes.sql — MySQL port. Access paths, split into "normal app" and
-- "voice lookup".
--
-- WHAT CHANGED FROM POSTGRES:
--
-- a) InnoDB auto-creates an index for every foreign key column. That already
--    covers 7 of the 11 app indexes in the Postgres original, so they are not
--    repeated here (a duplicate index costs writes and buys nothing):
--      order(sales_rep_id)            -> order_sales_rep_fk
--      order_item(order_id)           -> leftmost prefix of order_item_order_product
--      order_item(product_id)         -> order_item_product_fk
--      customer_address(customer_id)  -> customer_address_customer_fk
--      customer(account_manager_id)   -> customer_account_manager_fk
--      employee(manager_id)           -> employee_manager_fk
--      product(category_id)           -> product_category_fk
--
-- b) MySQL HAS NO PARTIAL INDEXES. Two Postgres indexes carried a WHERE and
--    have lost it. They still work, they are just bigger than they need to be:
--      ... ON "order" (sales_rep_id) WHERE sales_rep_id IS NOT NULL
--      ... ON product (category_id)  WHERE is_active
--
-- c) DESC in a multi-column index is honoured (MySQL 8.0+), so the
--    (customer_id, ordered_at DESC) shape ports as-is.

-- ---------------------------------------------------------------------------
-- Normal app paths. Only the ones InnoDB did not already make.
-- ---------------------------------------------------------------------------
CREATE INDEX order_customer_idx    ON `order` (customer_id, ordered_at DESC);
CREATE INDEX order_status_idx      ON `order` (status, ordered_at DESC);
CREATE INDEX order_ordered_at_idx  ON `order` (ordered_at DESC);
CREATE INDEX order_status_hist_idx ON order_status_history (order_id, changed_at DESC);

-- ---------------------------------------------------------------------------
-- Voice lookup paths. *** THIS IS WHERE THE PORT LOSES THE MOST. ***
--
-- Speech recognition hands us misspelled, un-punctuated names: "jon smyth",
-- "wireless mowse". Exact equality is useless there. The Postgres original gave
-- every user-facing name TWO indexes: a trigram index (edit-distance-ish) and a
-- phonetic index (sounds-like).
--
-- DELETED — no MySQL equivalent exists:
--     CREATE INDEX customer_name_trgm  ON customer  USING gin (full_name gin_trgm_ops);
--     CREATE INDEX employee_name_trgm  ON employee  USING gin (full_name gin_trgm_ops);
--     CREATE INDEX product_name_trgm   ON product   USING gin (name gin_trgm_ops);
--     CREATE INDEX category_name_trgm  ON product_category USING gin (name gin_trgm_ops);
-- MySQL has no trigram operator class and no similarity(). There is nothing to
-- index, because there is no fuzzy predicate to serve. See 05_ai_layer.sql.
--
-- DEGRADED — dmetaphone() does not exist, so these are SOUNDEX() instead.
-- SOUNDEX keeps only the first letter plus three consonant codes, so it is much
-- coarser than double metaphone: it collides aggressively on short names and
-- misses vowel-shifted pairs that dmetaphone catches.
-- ---------------------------------------------------------------------------
CREATE INDEX customer_name_phonetic ON customer  ((SOUNDEX(full_name)));
CREATE INDEX employee_name_phonetic ON employee  ((SOUNDEX(full_name)));
CREATE INDEX product_name_phonetic  ON product   ((SOUNDEX(name)));

-- "anything like a standing desk?"
-- Indexes the generated search_document column, mirroring Postgres, which puts
-- its GIN index on a generated tsvector of the same name. Different internals
-- (plain text vs tsvector), identical column name and identical inputs.
CREATE FULLTEXT INDEX product_search_idx ON product (search_document);

-- Order numbers get spoken as "A dash ten forty two" / "a1042"; index a
-- punctuation-stripped form so the resolver can match either shape.
-- MySQL 8 functional index: the expression needs its own parentheses.
CREATE INDEX order_number_squashed_idx ON `order` ((UPPER(REPLACE(order_number, '-', ''))));

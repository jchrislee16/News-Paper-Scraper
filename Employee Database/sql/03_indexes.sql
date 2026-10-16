-- 03_indexes.sql — access paths, split into "normal app" and "voice lookup".

-- Foreign keys / common filters
CREATE INDEX order_customer_idx        ON "order" (customer_id, ordered_at DESC);
CREATE INDEX order_sales_rep_idx       ON "order" (sales_rep_id) WHERE sales_rep_id IS NOT NULL;
CREATE INDEX order_status_idx          ON "order" (status, ordered_at DESC);
CREATE INDEX order_ordered_at_idx      ON "order" (ordered_at DESC);
CREATE INDEX order_item_order_idx      ON order_item (order_id);
CREATE INDEX order_item_product_idx    ON order_item (product_id);
CREATE INDEX customer_address_cust_idx ON customer_address (customer_id);
CREATE INDEX customer_manager_idx      ON customer (account_manager_id);
CREATE INDEX employee_manager_idx      ON employee (manager_id);
CREATE INDEX product_category_idx      ON product (category_id) WHERE is_active;
CREATE INDEX order_status_hist_idx     ON order_status_history (order_id, changed_at DESC);

-- ---------------------------------------------------------------------------
-- Voice lookup paths.
--
-- Speech recognition hands us misspelled, un-punctuated names: "jon smyth",
-- "wireless mowse". Exact equality is useless there, so every user-facing name
-- gets both a trigram index (edit-distance-ish) and a phonetic index (sounds-like).
-- ---------------------------------------------------------------------------
CREATE INDEX customer_name_trgm  ON customer  USING gin (full_name gin_trgm_ops);
CREATE INDEX employee_name_trgm  ON employee  USING gin (full_name gin_trgm_ops);
CREATE INDEX product_name_trgm   ON product   USING gin (name gin_trgm_ops);
CREATE INDEX category_name_trgm  ON product_category USING gin (name gin_trgm_ops);

CREATE INDEX customer_name_phonetic ON customer (dmetaphone(full_name));
CREATE INDEX employee_name_phonetic ON employee (dmetaphone(full_name));
CREATE INDEX product_name_phonetic  ON product  (dmetaphone(name));

-- "anything like a standing desk?"
CREATE INDEX product_search_idx ON product USING gin (search_document);

-- Order numbers get spoken as "A dash ten forty two" / "a1042"; index a
-- punctuation-stripped form so the resolver can match either shape.
CREATE INDEX order_number_squashed_idx
    ON "order" (upper(replace(order_number, '-', '')));

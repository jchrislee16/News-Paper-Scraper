-- 08_seed.sql — MySQL port. Small, realistic dataset for exercising voice queries.
-- Dates are relative to NOW(), so "last month" questions keep working.
--
-- PORTING NOTES:
--
--   current_date - 1800            -> DATE_SUB(CURRENT_DATE, INTERVAL 1800 DAY)
--   now() - (n || ' days')::interval -> DATE_SUB(NOW(), INTERVAL n DAY)
--   'x'::order_status              -> 'x'   (MySQL coerces the string to ENUM)
--   ARRAY['a','b']                 -> JSON_ARRAY('a','b')
--   '{...}'::jsonb                 -> '{...}'  (MySQL casts a valid JSON string)
--   setval('order_number_seq',1017)-> UPDATE order_number_seq SET last_number
--   ANALYZE                        -> ANALYZE TABLE <explicit list>
--
--   JOIN (VALUES (..),(..)) AS a(col, col)
--       MySQL has a VALUES ROW() constructor (8.0.19+) but NO derived column
--       list — you cannot name its columns, they arrive as column_0, column_1.
--       So every one of these becomes a UNION ALL of SELECTs with the names
--       declared on the first branch. More verbose, same result.
--
--   UPDATE t SET c = v.c FROM (...) v WHERE t.k = v.k
--       MySQL has no UPDATE ... FROM. Rewritten as
--       UPDATE t JOIN (...) v ON v.k = t.k SET t.c = v.c
--
--   WITH s AS (INSERT ... RETURNING id) INSERT ... SELECT FROM s
--       MySQL has neither data-modifying CTEs nor RETURNING. Split into a plain
--       INSERT followed by a lookup on the natural key (device_id).

-- --- Employees --------------------------------------------------------------
INSERT INTO employee (first_name, last_name, email, phone, job_title, department, hired_on) VALUES
 ('Dana',   'Whitfield', 'dana.whitfield@example.com',  '+1-206-555-0101', 'Sales Director',           'Sales',      DATE_SUB(CURRENT_DATE, INTERVAL 1800 DAY)),
 ('Priya',  'Raman',     'priya.raman@example.com',     '+1-206-555-0102', 'Senior Account Executive', 'Sales',      DATE_SUB(CURRENT_DATE, INTERVAL 1200 DAY)),
 ('Marcus', 'Boyd',      'marcus.boyd@example.com',     '+1-206-555-0103', 'Account Executive',        'Sales',      DATE_SUB(CURRENT_DATE, INTERVAL  700 DAY)),
 ('Sofia',  'Nguyen',    'sofia.nguyen@example.com',    '+1-206-555-0104', 'Account Executive',        'Sales',      DATE_SUB(CURRENT_DATE, INTERVAL  420 DAY)),
 ('Tom',    'Ellis',     'tom.ellis@example.com',       '+1-206-555-0105', 'Support Lead',             'Support',    DATE_SUB(CURRENT_DATE, INTERVAL  950 DAY)),
 ('Rachel', 'Okonkwo',   'rachel.okonkwo@example.com',  '+1-206-555-0106', 'Warehouse Manager',        'Operations', DATE_SUB(CURRENT_DATE, INTERVAL 1500 DAY));

-- MySQL will not let an UPDATE's subquery read the table being updated, so the
-- manager id is captured into a variable first. (Postgres allowed the subquery.)
SET @dana := (SELECT employee_id FROM employee WHERE email = 'dana.whitfield@example.com');
UPDATE employee SET manager_id = @dana
 WHERE email IN ('priya.raman@example.com','marcus.boyd@example.com','sofia.nguyen@example.com');
UPDATE employee SET is_active = FALSE WHERE email = 'marcus.boyd@example.com';  -- left the company

-- --- Customers --------------------------------------------------------------
SET @priya := (SELECT employee_id FROM employee WHERE email = 'priya.raman@example.com');
SET @sofia := (SELECT employee_id FROM employee WHERE email = 'sofia.nguyen@example.com');

INSERT INTO customer (first_name, last_name, email, phone, tier, signed_up_on, account_manager_id) VALUES
 ('John',   'Smith',    'john.smith@example.com',     '+1-312-555-0201', 'gold',     DATE_SUB(CURRENT_DATE, INTERVAL  900 DAY), @priya),
 ('Maria',  'Gonzalez', 'maria.gonzalez@example.com', '+1-312-555-0202', 'platinum', DATE_SUB(CURRENT_DATE, INTERVAL 1100 DAY), @priya),
 ('Robert', 'Chen',     'robert.chen@example.com',    '+1-312-555-0203', 'silver',   DATE_SUB(CURRENT_DATE, INTERVAL  400 DAY), @sofia),
 ('Aisha',  'Patel',    'aisha.patel@example.com',    '+1-312-555-0204', 'gold',     DATE_SUB(CURRENT_DATE, INTERVAL  610 DAY), @sofia),
 ('Daniel', 'O''Brien', 'daniel.obrien@example.com',  '+1-312-555-0205', 'standard', DATE_SUB(CURRENT_DATE, INTERVAL  120 DAY), NULL),
 ('Yuki',   'Tanaka',   'yuki.tanaka@example.com',    '+1-312-555-0206', 'silver',   DATE_SUB(CURRENT_DATE, INTERVAL  300 DAY), NULL),
 ('Grace',  'Miller',   'grace.miller@example.com',   '+1-312-555-0207', 'standard', DATE_SUB(CURRENT_DATE, INTERVAL   55 DAY), NULL),
 ('Omar',   'Haddad',   'omar.haddad@example.com',    '+1-312-555-0208', 'gold',     DATE_SUB(CURRENT_DATE, INTERVAL  780 DAY), @priya);

INSERT INTO customer_address (customer_id, kind, label, line1, city, state_region, postal_code, is_default)
SELECT c.customer_id, 'shipping', 'home', a.line1, a.city, a.region, a.zip, TRUE
FROM customer c
JOIN (
            SELECT 'john.smith@example.com'     AS email, '418 Maple Street'   AS line1, 'Chicago'  AS city, 'IL' AS region, '60614' AS zip
  UNION ALL SELECT 'maria.gonzalez@example.com',          '77 Harbor View Rd',           'Seattle',           'WA',          '98101'
  UNION ALL SELECT 'robert.chen@example.com',             '1200 Lakeshore Ave',          'Chicago',           'IL',          '60611'
  UNION ALL SELECT 'aisha.patel@example.com',             '9 Birchwood Lane',            'Austin',            'TX',          '78701'
  UNION ALL SELECT 'daniel.obrien@example.com',           '55 Cedar Court',              'Boston',            'MA',          '02108'
  UNION ALL SELECT 'yuki.tanaka@example.com',             '310 Pine Street',             'Portland',          'OR',          '97205'
  UNION ALL SELECT 'grace.miller@example.com',            '82 Willow Drive',             'Denver',            'CO',          '80202'
  UNION ALL SELECT 'omar.haddad@example.com',             '640 Sunset Blvd',             'Phoenix',           'AZ',          '85004'
) a ON a.email = c.email;

-- A second, non-default address so "send it to the office" has something to resolve.
INSERT INTO customer_address (customer_id, kind, label, line1, city, state_region, postal_code, is_default)
SELECT customer_id, 'shipping', 'the office', '200 West Adams St, Suite 1400', 'Chicago', 'IL', '60606', FALSE
FROM customer WHERE email = 'john.smith@example.com';

-- --- Catalogue --------------------------------------------------------------
INSERT INTO product_category (name, description) VALUES
 ('Laptops',     'Portable computers'),
 ('Peripherals', 'Keyboards, mice, docks and other desk accessories'),
 ('Displays',    'Monitors and screens'),
 ('Furniture',   'Desks, chairs and office furniture'),
 ('Audio',       'Headsets, speakers and microphones');

INSERT INTO product (sku, name, brand, description, category_id, unit_price, stock_quantity, reorder_level)
SELECT v.sku, v.name, v.brand, v.descr, pc.category_id, v.price, v.stock, v.reorder
FROM (
            SELECT 'LAP-0001' AS sku, 'MacBook Pro 14'           AS name, 'Apple'          AS brand, '14-inch laptop for development and design work'  AS descr, 'Laptops'     AS cat, 1999.00 AS price,  24 AS stock,  5 AS reorder
  UNION ALL SELECT 'LAP-0002',        'ThinkPad X1 Carbon',              'Lenovo',                  'Lightweight business ultrabook',                          'Laptops',           1549.00,        11,         4
  UNION ALL SELECT 'LAP-0003',        'Chromebook Flip',                 'ASUS',                    'Budget convertible laptop for students',                  'Laptops',            429.00,         3,         6
  UNION ALL SELECT 'PER-0001',        'Wireless Mouse',                  'Logitech',                'Bluetooth ergonomic mouse, silent click',                 'Peripherals',         39.99,       140,        25
  UNION ALL SELECT 'PER-0002',        'Mechanical Keyboard',             'Keychron',                'Compact hot-swappable mechanical keyboard',               'Peripherals',        109.00,        62,        15
  UNION ALL SELECT 'PER-0003',        'USB-C Docking Station',           'Anker',                   'Eleven-port dock with dual display output',               'Peripherals',        189.50,        18,        10
  UNION ALL SELECT 'PER-0004',        'Webcam 1080p',                    'Logitech',                'Full HD webcam with privacy shutter',                     'Peripherals',         74.00,        40,        12
  UNION ALL SELECT 'DIS-0001',        '27-inch 4K Monitor',              'Dell',                    'Colour-accurate 27 inch 4K display',                      'Displays',           549.00,        16,         5
  UNION ALL SELECT 'DIS-0002',        '34-inch Ultrawide',               'LG',                      'Curved ultrawide monitor for multitasking',               'Displays',           899.00,         7,         3
  UNION ALL SELECT 'FUR-0001',        'Standing Desk',                   'Uplift',                  'Electric height-adjustable sit-stand desk',               'Furniture',          649.00,        12,         4
  UNION ALL SELECT 'FUR-0002',        'Ergonomic Office Chair',          'Herman Miller',           'Mesh task chair with lumbar support',                      'Furniture',         1195.00,         9,         3
  UNION ALL SELECT 'FUR-0003',        'Monitor Arm',                     'Ergotron',                'Single monitor desk-mounted arm',                         'Furniture',          159.00,        30,        10
  UNION ALL SELECT 'AUD-0001',        'Noise Cancelling Headset',        'Sony',                    'Over-ear wireless headset for calls and focus',           'Audio',              349.00,        22,         8
  UNION ALL SELECT 'AUD-0002',        'USB Microphone',                  'Blue',                    'Cardioid USB condenser microphone for meetings',          'Audio',              129.00,        14,         6
) v
JOIN product_category pc ON pc.name = v.cat;

UPDATE product SET is_active = FALSE WHERE sku = 'LAP-0003';  -- discontinued

-- Two live products sitting at or below their reorder level, so restock questions
-- have something to return.
UPDATE product SET stock_quantity = 2 WHERE sku = 'DIS-0002';
UPDATE product SET stock_quantity = 8 WHERE sku = 'PER-0003';

-- --- Orders -----------------------------------------------------------------
-- order_number is supplied explicitly here, which the order_number_assign
-- trigger deliberately leaves alone (it only mints one when the column is
-- NULL or empty). The counter is resynced below so the next real order is A-1018.
INSERT INTO `order` (order_number, customer_id, sales_rep_id, status, ordered_at, shipped_at,
                     delivered_at, cancelled_at, method, shipping_fee, tax_total, discount_total, notes)
SELECT o.num,
       c.customer_id,
       e.employee_id,
       o.st,
       DATE_SUB(NOW(), INTERVAL o.days_ago DAY),
       CASE WHEN o.st IN ('shipped','delivered') THEN DATE_SUB(NOW(), INTERVAL (o.days_ago - 2) DAY) END,
       CASE WHEN o.st = 'delivered'              THEN DATE_SUB(NOW(), INTERVAL (o.days_ago - 5) DAY) END,
       CASE WHEN o.st = 'cancelled'              THEN DATE_SUB(NOW(), INTERVAL (o.days_ago - 1) DAY) END,
       o.pay, o.ship, o.tax, o.disc, o.note
FROM (
            SELECT 'A-1001' AS num, 'john.smith@example.com'     AS cust, 'priya.raman@example.com'  AS rep, 'delivered' AS st, 95 AS days_ago, 'card'          AS pay, 12.00 AS ship, 178.40 AS tax,  0.00 AS disc, CAST(NULL AS CHAR) AS note
  UNION ALL SELECT 'A-1002',        'maria.gonzalez@example.com',        'priya.raman@example.com',         'delivered',        88,             'bank_transfer',         0.00,        241.10,       50.00,       'Volume discount applied'
  UNION ALL SELECT 'A-1003',        'robert.chen@example.com',           'sofia.nguyen@example.com',        'delivered',        74,             'card',                  9.50,         42.30,        0.00,       NULL
  UNION ALL SELECT 'A-1004',        'john.smith@example.com',            'priya.raman@example.com',         'cancelled',        66,             'card',                  0.00,          0.00,        0.00,       'Customer changed their mind'
  UNION ALL SELECT 'A-1005',        'aisha.patel@example.com',           'sofia.nguyen@example.com',        'delivered',        61,             'paypal',               15.00,        119.80,        0.00,       NULL
  UNION ALL SELECT 'A-1006',        'omar.haddad@example.com',           'priya.raman@example.com',         'delivered',        52,             'card',                  0.00,        208.60,       25.00,       NULL
  UNION ALL SELECT 'A-1007',        'yuki.tanaka@example.com',           NULL,                              'delivered',        44,             'card',                 11.00,         31.90,        0.00,       NULL
  UNION ALL SELECT 'A-1008',        'maria.gonzalez@example.com',        'priya.raman@example.com',         'delivered',        38,             'bank_transfer',         0.00,        154.20,        0.00,       NULL
  UNION ALL SELECT 'A-1009',        'daniel.obrien@example.com',         NULL,                              'refunded',         33,             'card',                 12.00,         10.40,        0.00,       'Arrived damaged'
  UNION ALL SELECT 'A-1010',        'john.smith@example.com',            'priya.raman@example.com',         'delivered',        27,             'card',                  0.00,         97.30,        0.00,       NULL
  UNION ALL SELECT 'A-1011',        'grace.miller@example.com',          'sofia.nguyen@example.com',        'delivered',        21,             'paypal',                9.50,         26.80,        0.00,       NULL
  UNION ALL SELECT 'A-1012',        'robert.chen@example.com',           'sofia.nguyen@example.com',        'shipped',          12,             'card',                  0.00,        111.90,        0.00,       NULL
  UNION ALL SELECT 'A-1013',        'aisha.patel@example.com',           'sofia.nguyen@example.com',        'shipped',           9,             'card',                 15.00,         63.40,        0.00,       NULL
  UNION ALL SELECT 'A-1014',        'omar.haddad@example.com',           'priya.raman@example.com',         'packed',            5,             'bank_transfer',         0.00,        175.20,        0.00,       NULL
  UNION ALL SELECT 'A-1015',        'maria.gonzalez@example.com',        'priya.raman@example.com',         'paid',              3,             'card',                  0.00,         88.00,        0.00,       NULL
  UNION ALL SELECT 'A-1016',        'yuki.tanaka@example.com',           NULL,                              'pending',           1,             'card',                 11.00,         12.90,        0.00,       NULL
  UNION ALL SELECT 'A-1017',        'grace.miller@example.com',          'sofia.nguyen@example.com',        'pending',           0,             'paypal',                9.50,         35.60,        0.00,       NULL
) o
JOIN customer c      ON c.email = o.cust
LEFT JOIN employee e ON e.email = o.rep;

-- Replaces: SELECT setval('order_number_seq', 1017);
UPDATE order_number_seq SET last_number = 1017 WHERE only_row = 1;

-- --- Unit costs (drives cost of goods sold in the P&L) ----------------------
-- Margins vary by category: laptops are thin, peripherals and furniture are fat.
UPDATE product p
JOIN (
            SELECT 'LAP-0001' AS sku, 1680.00 AS cost
  UNION ALL SELECT 'LAP-0002', 1290.00
  UNION ALL SELECT 'LAP-0003',  352.00
  UNION ALL SELECT 'PER-0001',   21.50
  UNION ALL SELECT 'PER-0002',   62.00
  UNION ALL SELECT 'PER-0003',  112.00
  UNION ALL SELECT 'PER-0004',   41.00
  UNION ALL SELECT 'DIS-0001',  398.00
  UNION ALL SELECT 'DIS-0002',  672.00
  UNION ALL SELECT 'FUR-0001',  389.00
  UNION ALL SELECT 'FUR-0002',  702.00
  UNION ALL SELECT 'FUR-0003',   86.00
  UNION ALL SELECT 'AUD-0001',  128.00
  UNION ALL SELECT 'AUD-0002',   54.00
) v ON v.sku = p.sku
SET p.unit_cost = v.cost;

INSERT INTO order_item (order_id, product_id, quantity, unit_price, discount)
SELECT o.order_id, p.product_id, i.qty, p.unit_price, i.disc
FROM (
            SELECT 'A-1001' AS num, 'LAP-0001' AS sku, 1 AS qty,   0.00 AS disc
  UNION ALL SELECT 'A-1001','PER-0001',2,  0.00  UNION ALL SELECT 'A-1001','AUD-0001',1, 0.00
  UNION ALL SELECT 'A-1002','LAP-0001',2,100.00  UNION ALL SELECT 'A-1002','DIS-0001',2, 0.00
  UNION ALL SELECT 'A-1002','FUR-0003',2,  0.00
  UNION ALL SELECT 'A-1003','PER-0002',1,  0.00  UNION ALL SELECT 'A-1003','PER-0001',1, 0.00
  UNION ALL SELECT 'A-1003','PER-0004',2,  0.00
  UNION ALL SELECT 'A-1004','FUR-0002',1,  0.00
  UNION ALL SELECT 'A-1005','FUR-0001',1,  0.00  UNION ALL SELECT 'A-1005','FUR-0003',1, 0.00
  UNION ALL SELECT 'A-1005','PER-0003',1,  0.00
  UNION ALL SELECT 'A-1006','LAP-0002',1,  0.00  UNION ALL SELECT 'A-1006','DIS-0002',1, 0.00
  UNION ALL SELECT 'A-1007','PER-0001',3,  0.00  UNION ALL SELECT 'A-1007','AUD-0002',1, 0.00
  UNION ALL SELECT 'A-1008','FUR-0002',1,  0.00  UNION ALL SELECT 'A-1008','AUD-0001',1, 0.00
  UNION ALL SELECT 'A-1009','PER-0004',1,  0.00  UNION ALL SELECT 'A-1009','PER-0001',1, 0.00
  UNION ALL SELECT 'A-1010','DIS-0001',1,  0.00  UNION ALL SELECT 'A-1010','PER-0003',1, 0.00
  UNION ALL SELECT 'A-1010','PER-0002',1,  0.00
  UNION ALL SELECT 'A-1011','PER-0002',1,  0.00  UNION ALL SELECT 'A-1011','PER-0001',2, 0.00
  UNION ALL SELECT 'A-1012','LAP-0002',1,  0.00  UNION ALL SELECT 'A-1012','AUD-0001',1, 0.00
  UNION ALL SELECT 'A-1013','FUR-0001',1,  0.00  UNION ALL SELECT 'A-1013','PER-0001',1, 0.00
  UNION ALL SELECT 'A-1014','LAP-0001',1,  0.00  UNION ALL SELECT 'A-1014','FUR-0003',1, 0.00
  UNION ALL SELECT 'A-1015','DIS-0002',1,  0.00
  UNION ALL SELECT 'A-1016','AUD-0002',1,  0.00  UNION ALL SELECT 'A-1016','PER-0001',1, 0.00
  UNION ALL SELECT 'A-1017','PER-0003',2,  0.00
) i
JOIN `order` o  ON o.order_number = i.num
JOIN product p  ON p.sku = i.sku;

-- Default shipping/billing address per order.
UPDATE `order` o
JOIN customer_address a ON a.customer_id = o.customer_id AND a.is_default
SET o.shipping_address_id = a.address_id,
    o.billing_address_id  = a.address_id;

-- Snapshot each line's cost from the catalogue, mirroring how unit_price was
-- captured. Done as a backfill here only because the seed writes order_item
-- rows without a cost; a real application sets both at insert time.
UPDATE order_item oi
JOIN product p ON p.product_id = oi.product_id
SET oi.unit_cost = p.unit_cost;

-- --- Voice aliases ----------------------------------------------------------
INSERT INTO ai_entity_alias (entity_type, entity_id, alias, alias_kind)
SELECT 'customer', c.customer_id, v.alias, v.kind
FROM (
            SELECT 'robert.chen@example.com'     AS email, 'bobby'         AS alias, 'nickname'  AS kind
  UNION ALL SELECT 'robert.chen@example.com',             'bob chen',              'nickname'
  UNION ALL SELECT 'maria.gonzalez@example.com',          'maria g',               'nickname'
  UNION ALL SELECT 'daniel.obrien@example.com',           'danny obrien',          'nickname'
  UNION ALL SELECT 'john.smith@example.com',              'jon smyth',             'asr_error'
) v JOIN customer c ON c.email = v.email;

INSERT INTO ai_entity_alias (entity_type, entity_id, alias, alias_kind)
SELECT 'employee', e.employee_id, 'pria', 'asr_error'
FROM employee e WHERE e.email = 'priya.raman@example.com';

INSERT INTO ai_entity_alias (entity_type, entity_id, alias, alias_kind)
SELECT 'product', p.product_id, v.alias, v.kind
FROM (
            SELECT 'LAP-0001' AS sku, 'mbp'                          AS alias, 'abbreviation' AS kind
  UNION ALL SELECT 'LAP-0001',        'macbook',                             'abbreviation'
  UNION ALL SELECT 'PER-0001',        'wireless mowse',                      'asr_error'
  UNION ALL SELECT 'FUR-0001',        'sit stand desk',                      'trade_name'
  UNION ALL SELECT 'AUD-0001',        'noise cancelling headphones',         'trade_name'
  UNION ALL SELECT 'DIS-0002',        'ultrawide',                           'abbreviation'
) v JOIN product p ON p.sku = v.sku;

-- --- Intent catalogue -------------------------------------------------------
-- sql_template uses named :slots. The assistant fills them from resolved_entities
-- and binds them as parameters — it never string-concatenates a value into SQL.
-- NOTE: templates referencing fn_profit_and_loss would need CALL now; none do.
INSERT INTO ai_intent (intent_name, description, sample_utterances, required_slots, sql_template) VALUES
 ('order_status',
  'Where is a specific order right now',
  JSON_ARRAY('where is order A-1003','what is the status of my last order','has order a1012 shipped yet'),
  JSON_ARRAY('order_number'),
  'SELECT order_number, status, ordered_at, shipped_at, delivered_at, grand_total
     FROM v_order_summary WHERE order_id = :order_id'),

 ('customer_last_order',
  'The most recent order placed by a named customer',
  JSON_ARRAY('what did John Smith order last','show me Maria''s latest purchase','when did bobby last buy something'),
  JSON_ARRAY('customer_id'),
  'SELECT order_number, ordered_at, status, grand_total
     FROM v_order_summary WHERE customer_id = :customer_id
     ORDER BY ordered_at DESC LIMIT 1'),

 ('customer_spend',
  'How much a customer has spent, optionally within a period',
  JSON_ARRAY('how much has Maria spent','what is John Smith''s lifetime value','how much did Aisha spend last month'),
  JSON_ARRAY('customer_id'),
  'SELECT customer_name, order_count, lifetime_value, average_order_value, last_order_at
     FROM v_customer_360 WHERE customer_id = :customer_id'),

 ('product_stock',
  'How many units of a product are on hand',
  JSON_ARRAY('how many wireless mice do we have','are we out of standing desks','stock level for the MBP'),
  JSON_ARRAY('product_id'),
  'SELECT product_name, stock_quantity, reorder_level, needs_restock
     FROM v_product_performance WHERE product_id = :product_id'),

 ('restock_list',
  'Everything at or below its reorder level',
  JSON_ARRAY('what needs reordering','which products are running low','anything out of stock'),
  JSON_ARRAY(),
  'SELECT product_name, stock_quantity, reorder_level
     FROM v_product_performance WHERE needs_restock AND is_active
     ORDER BY stock_quantity'),

 ('top_products',
  'Best selling products over a period',
  JSON_ARRAY('what sold best this month','top five products','what is our bestseller'),
  JSON_ARRAY(),
  'SELECT product_name, units_sold, revenue
     FROM v_product_performance ORDER BY revenue DESC LIMIT :limit'),

 ('sales_by_rep',
  'How a named sales rep is performing',
  JSON_ARRAY('how did Priya do this quarter','who is my top sales rep','how many orders has Sofia closed'),
  JSON_ARRAY(),
  'SELECT employee_name, orders_closed, revenue, customers_served
     FROM v_employee_sales ORDER BY revenue DESC'),

 ('revenue_for_period',
  'Total revenue over a date range',
  JSON_ARRAY('how much did we make last week','revenue this month','what were sales yesterday'),
  JSON_ARRAY('start_date','end_date'),
  'SELECT sum(revenue) AS revenue, sum(order_count) AS orders
     FROM v_daily_sales WHERE sales_day BETWEEN :start_date AND :end_date'),

 ('order_contents',
  'What was in a given order',
  JSON_ARRAY('what was in order A-1001','what did she actually buy','list the items on a1005'),
  JSON_ARRAY('order_id'),
  'SELECT product_name, quantity, unit_price, line_total
     FROM v_order_line WHERE order_id = :order_id ORDER BY line_total DESC');

-- --- A sample conversation (shows the logging shape) -------------------------
-- Postgres did this in one statement with a data-modifying CTE and RETURNING.
-- MySQL has neither, so: insert the session, then look it up by device_id.
INSERT INTO ai_voice_session (channel, device_id, employee_id, locale)
SELECT 'alexa', 'amzn1.echo-api.device.SAMPLE', e.employee_id, 'en-US'
FROM employee e WHERE e.email = 'priya.raman@example.com';

SET @sess := (SELECT session_id FROM ai_voice_session
              WHERE device_id = 'amzn1.echo-api.device.SAMPLE');

INSERT INTO ai_utterance (session_id, turn_no, transcript, asr_confidence, intent_name,
                          intent_confidence, slots, resolved_entities, generated_sql,
                          sql_status, row_count, response_text, latency_ms, was_helpful)
VALUES
 (@sess, 1, 'how much has jon smyth spent with us', 0.82, 'customer_spend', 0.91,
  '{"customer":"jon smyth"}', '{"customer_id":1,"match_score":0.71,"match_reason":"alias"}',
  'SELECT customer_name, order_count, lifetime_value FROM v_customer_360 WHERE customer_id = 1',
  'ok', 1, 'John Smith has placed 3 orders totalling 4,216 dollars.', 640, TRUE),
 (@sess, 2, 'and what did he order last time', 0.94, 'customer_last_order', 0.88,
  '{"customer":"he"}', '{"customer_id":1,"source":"session_context"}',
  'SELECT order_number, ordered_at, status, grand_total FROM v_order_summary WHERE customer_id = 1 ORDER BY ordered_at DESC LIMIT 1',
  'ok', 1, 'Order A-1010 on the 14th, delivered, 875 dollars.', 410, TRUE),
 (@sess, 3, 'do we have any more of those mowse things', 0.61, 'product_stock', 0.54,
  '{"product":"mowse"}', '{"candidates":[{"product_id":4,"score":0.44}]}',
  NULL, 'rejected', NULL, 'Did you mean the Wireless Mouse?', 300, NULL);

-- Keep the last-mentioned entity on the session, which is what made turn 2 work.
UPDATE ai_voice_session
SET context = '{"last_customer_id": 1, "last_order_number": "A-1010"}'
WHERE device_id = 'amzn1.echo-api.device.SAMPLE';

ANALYZE TABLE employee, customer, customer_address, product_category, product,
              `order`, order_item, order_status_history,
              ai_entity_alias, ai_intent, ai_voice_session, ai_utterance;

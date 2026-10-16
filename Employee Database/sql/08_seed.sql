-- 08_seed.sql — small, realistic dataset for exercising voice queries.
-- Dates are relative to now(), so "last month" questions keep working.

-- --- Employees --------------------------------------------------------------
INSERT INTO employee (first_name, last_name, email, phone, job_title, department, hired_on) VALUES
 ('Dana',   'Whitfield', 'dana.whitfield@example.com',  '+1-206-555-0101', 'Sales Director',       'Sales',      current_date - 1800),
 ('Priya',  'Raman',     'priya.raman@example.com',     '+1-206-555-0102', 'Senior Account Executive','Sales',   current_date - 1200),
 ('Marcus', 'Boyd',      'marcus.boyd@example.com',     '+1-206-555-0103', 'Account Executive',    'Sales',      current_date - 700),
 ('Sofia',  'Nguyen',    'sofia.nguyen@example.com',    '+1-206-555-0104', 'Account Executive',    'Sales',      current_date - 420),
 ('Tom',    'Ellis',     'tom.ellis@example.com',       '+1-206-555-0105', 'Support Lead',         'Support',    current_date - 950),
 ('Rachel', 'Okonkwo',   'rachel.okonkwo@example.com',  '+1-206-555-0106', 'Warehouse Manager',    'Operations', current_date - 1500);

UPDATE employee SET manager_id = (SELECT employee_id FROM employee WHERE email = 'dana.whitfield@example.com')
WHERE email IN ('priya.raman@example.com','marcus.boyd@example.com','sofia.nguyen@example.com');
UPDATE employee SET is_active = false WHERE email = 'marcus.boyd@example.com';  -- left the company

-- --- Customers --------------------------------------------------------------
INSERT INTO customer (first_name, last_name, email, phone, tier, signed_up_on, account_manager_id) VALUES
 ('John',    'Smith',    'john.smith@example.com',    '+1-312-555-0201', 'gold',     current_date - 900,
   (SELECT employee_id FROM employee WHERE email='priya.raman@example.com')),
 ('Maria',   'Gonzalez', 'maria.gonzalez@example.com','+1-312-555-0202', 'platinum', current_date - 1100,
   (SELECT employee_id FROM employee WHERE email='priya.raman@example.com')),
 ('Robert',  'Chen',     'robert.chen@example.com',   '+1-312-555-0203', 'silver',   current_date - 400,
   (SELECT employee_id FROM employee WHERE email='sofia.nguyen@example.com')),
 ('Aisha',   'Patel',    'aisha.patel@example.com',   '+1-312-555-0204', 'gold',     current_date - 610,
   (SELECT employee_id FROM employee WHERE email='sofia.nguyen@example.com')),
 ('Daniel',  'O''Brien', 'daniel.obrien@example.com', '+1-312-555-0205', 'standard', current_date - 120, NULL),
 ('Yuki',    'Tanaka',   'yuki.tanaka@example.com',   '+1-312-555-0206', 'silver',   current_date - 300, NULL),
 ('Grace',   'Miller',   'grace.miller@example.com',  '+1-312-555-0207', 'standard', current_date - 55,  NULL),
 ('Omar',    'Haddad',   'omar.haddad@example.com',   '+1-312-555-0208', 'gold',     current_date - 780,
   (SELECT employee_id FROM employee WHERE email='priya.raman@example.com'));

INSERT INTO customer_address (customer_id, kind, label, line1, city, state_region, postal_code, is_default)
SELECT c.customer_id, 'shipping', 'home', a.line1, a.city, a.region, a.zip, true
FROM customer c
JOIN (VALUES
  ('john.smith@example.com',    '418 Maple Street',   'Chicago', 'IL', '60614'),
  ('maria.gonzalez@example.com','77 Harbor View Rd',  'Seattle', 'WA', '98101'),
  ('robert.chen@example.com',   '1200 Lakeshore Ave', 'Chicago', 'IL', '60611'),
  ('aisha.patel@example.com',   '9 Birchwood Lane',   'Austin',  'TX', '78701'),
  ('daniel.obrien@example.com', '55 Cedar Court',     'Boston',  'MA', '02108'),
  ('yuki.tanaka@example.com',   '310 Pine Street',    'Portland','OR', '97205'),
  ('grace.miller@example.com',  '82 Willow Drive',    'Denver',  'CO', '80202'),
  ('omar.haddad@example.com',   '640 Sunset Blvd',    'Phoenix', 'AZ', '85004')
) AS a(email, line1, city, region, zip) ON a.email = c.email::text;

-- A second, non-default address so "send it to the office" has something to resolve.
INSERT INTO customer_address (customer_id, kind, label, line1, city, state_region, postal_code, is_default)
SELECT customer_id, 'shipping', 'the office', '200 West Adams St, Suite 1400', 'Chicago', 'IL', '60606', false
FROM customer WHERE email = 'john.smith@example.com';

-- --- Catalogue --------------------------------------------------------------
INSERT INTO product_category (name, description) VALUES
 ('Laptops',     'Portable computers'),
 ('Peripherals', 'Keyboards, mice, docks and other desk accessories'),
 ('Displays',    'Monitors and screens'),
 ('Furniture',   'Desks, chairs and office furniture'),
 ('Audio',       'Headsets, speakers and microphones');

INSERT INTO product (sku, name, brand, description, category_id, unit_price, stock_quantity, reorder_level) VALUES
 ('LAP-0001','MacBook Pro 14',       'Apple',    '14-inch laptop for development and design work',
   (SELECT category_id FROM product_category WHERE name='Laptops'), 1999.00, 24, 5),
 ('LAP-0002','ThinkPad X1 Carbon',   'Lenovo',   'Lightweight business ultrabook',
   (SELECT category_id FROM product_category WHERE name='Laptops'), 1549.00, 11, 4),
 ('LAP-0003','Chromebook Flip',      'ASUS',     'Budget convertible laptop for students',
   (SELECT category_id FROM product_category WHERE name='Laptops'),  429.00,  3, 6),
 ('PER-0001','Wireless Mouse',       'Logitech', 'Bluetooth ergonomic mouse, silent click',
   (SELECT category_id FROM product_category WHERE name='Peripherals'), 39.99, 140, 25),
 ('PER-0002','Mechanical Keyboard',  'Keychron', 'Compact hot-swappable mechanical keyboard',
   (SELECT category_id FROM product_category WHERE name='Peripherals'), 109.00, 62, 15),
 ('PER-0003','USB-C Docking Station','Anker',    'Eleven-port dock with dual display output',
   (SELECT category_id FROM product_category WHERE name='Peripherals'), 189.50, 18, 10),
 ('PER-0004','Webcam 1080p',         'Logitech', 'Full HD webcam with privacy shutter',
   (SELECT category_id FROM product_category WHERE name='Peripherals'), 74.00, 40, 12),
 ('DIS-0001','27-inch 4K Monitor',   'Dell',     'Colour-accurate 27 inch 4K display',
   (SELECT category_id FROM product_category WHERE name='Displays'), 549.00, 16, 5),
 ('DIS-0002','34-inch Ultrawide',    'LG',       'Curved ultrawide monitor for multitasking',
   (SELECT category_id FROM product_category WHERE name='Displays'), 899.00,  7, 3),
 ('FUR-0001','Standing Desk',        'Uplift',   'Electric height-adjustable sit-stand desk',
   (SELECT category_id FROM product_category WHERE name='Furniture'), 649.00, 12, 4),
 ('FUR-0002','Ergonomic Office Chair','Herman Miller','Mesh task chair with lumbar support',
   (SELECT category_id FROM product_category WHERE name='Furniture'), 1195.00, 9, 3),
 ('FUR-0003','Monitor Arm',          'Ergotron', 'Single monitor desk-mounted arm',
   (SELECT category_id FROM product_category WHERE name='Furniture'), 159.00, 30, 10),
 ('AUD-0001','Noise Cancelling Headset','Sony',  'Over-ear wireless headset for calls and focus',
   (SELECT category_id FROM product_category WHERE name='Audio'), 349.00, 22, 8),
 ('AUD-0002','USB Microphone',       'Blue',     'Cardioid USB condenser microphone for meetings',
   (SELECT category_id FROM product_category WHERE name='Audio'), 129.00, 14, 6);

UPDATE product SET is_active = false WHERE sku = 'LAP-0003';  -- discontinued

-- Two live products sitting at or below their reorder level, so restock questions
-- have something to return.
UPDATE product SET stock_quantity = 2 WHERE sku = 'DIS-0002';
UPDATE product SET stock_quantity = 8 WHERE sku = 'PER-0003';

-- --- Orders -----------------------------------------------------------------
INSERT INTO "order" (order_number, customer_id, sales_rep_id, status, ordered_at, shipped_at, delivered_at,
                     cancelled_at, method, shipping_fee, tax_total, discount_total, notes)
SELECT o.num,
       (SELECT customer_id FROM customer WHERE email = o.cust),
       (SELECT employee_id FROM employee WHERE email = o.rep),
       o.st::order_status,
       now() - (o.days_ago || ' days')::interval,
       CASE WHEN o.st IN ('shipped','delivered') THEN now() - ((o.days_ago - 2) || ' days')::interval END,
       CASE WHEN o.st = 'delivered' THEN now() - ((o.days_ago - 5) || ' days')::interval END,
       CASE WHEN o.st = 'cancelled' THEN now() - ((o.days_ago - 1) || ' days')::interval END,
       o.pay::payment_method, o.ship, o.tax, o.disc, o.note
FROM (VALUES
 ('A-1001','john.smith@example.com',    'priya.raman@example.com',  'delivered', 95, 'card',        12.00, 178.40, 0.00,   NULL),
 ('A-1002','maria.gonzalez@example.com','priya.raman@example.com',  'delivered', 88, 'bank_transfer',0.00, 241.10, 50.00, 'Volume discount applied'),
 ('A-1003','robert.chen@example.com',   'sofia.nguyen@example.com', 'delivered', 74, 'card',         9.50,  42.30, 0.00,   NULL),
 ('A-1004','john.smith@example.com',    'priya.raman@example.com',  'cancelled', 66, 'card',         0.00,   0.00, 0.00,  'Customer changed their mind'),
 ('A-1005','aisha.patel@example.com',   'sofia.nguyen@example.com', 'delivered', 61, 'paypal',      15.00, 119.80, 0.00,   NULL),
 ('A-1006','omar.haddad@example.com',   'priya.raman@example.com',  'delivered', 52, 'card',         0.00, 208.60, 25.00,  NULL),
 ('A-1007','yuki.tanaka@example.com',   NULL,                       'delivered', 44, 'card',        11.00,  31.90, 0.00,   NULL),
 ('A-1008','maria.gonzalez@example.com','priya.raman@example.com',  'delivered', 38, 'bank_transfer',0.00, 154.20, 0.00,   NULL),
 ('A-1009','daniel.obrien@example.com', NULL,                       'refunded',  33, 'card',        12.00,  10.40, 0.00,  'Arrived damaged'),
 ('A-1010','john.smith@example.com',    'priya.raman@example.com',  'delivered', 27, 'card',         0.00,  97.30, 0.00,   NULL),
 ('A-1011','grace.miller@example.com',  'sofia.nguyen@example.com', 'delivered', 21, 'paypal',       9.50,  26.80, 0.00,   NULL),
 ('A-1012','robert.chen@example.com',   'sofia.nguyen@example.com', 'shipped',   12, 'card',         0.00, 111.90, 0.00,   NULL),
 ('A-1013','aisha.patel@example.com',   'sofia.nguyen@example.com', 'shipped',    9, 'card',        15.00,  63.40, 0.00,   NULL),
 ('A-1014','omar.haddad@example.com',   'priya.raman@example.com',  'packed',     5, 'bank_transfer',0.00, 175.20, 0.00,   NULL),
 ('A-1015','maria.gonzalez@example.com','priya.raman@example.com',  'paid',       3, 'card',         0.00,  88.00, 0.00,   NULL),
 ('A-1016','yuki.tanaka@example.com',   NULL,                       'pending',    1, 'card',        11.00,  12.90, 0.00,   NULL),
 ('A-1017','grace.miller@example.com',  'sofia.nguyen@example.com', 'pending',    0, 'paypal',       9.50,  35.60, 0.00,   NULL)
) AS o(num, cust, rep, st, days_ago, pay, ship, tax, disc, note);

SELECT setval('order_number_seq', 1017);

-- --- Unit costs (drives cost of goods sold in the P&L) ----------------------
-- Margins vary by category: laptops are thin, peripherals and furniture are fat.
UPDATE product SET unit_cost = v.cost
FROM (VALUES
  ('LAP-0001', 1680.00::numeric),
  ('LAP-0002', 1290.00::numeric),
  ('LAP-0003', 352.00::numeric),
  ('PER-0001', 21.50::numeric),
  ('PER-0002', 62.00::numeric),
  ('PER-0003', 112.00::numeric),
  ('PER-0004', 41.00::numeric),
  ('DIS-0001', 398.00::numeric),
  ('DIS-0002', 672.00::numeric),
  ('FUR-0001', 389.00::numeric),
  ('FUR-0002', 702.00::numeric),
  ('FUR-0003', 86.00::numeric),
  ('AUD-0001', 128.00::numeric),
  ('AUD-0002', 54.00::numeric)
) AS v(sku, cost)
WHERE product.sku = v.sku;

INSERT INTO order_item (order_id, product_id, quantity, unit_price, discount)
SELECT (SELECT order_id FROM "order" WHERE order_number = i.num),
       p.product_id, i.qty, p.unit_price, i.disc
FROM (VALUES
 ('A-1001','LAP-0001',1, 0.00), ('A-1001','PER-0001',2, 0.00), ('A-1001','AUD-0001',1, 0.00),
 ('A-1002','LAP-0001',2, 100.00), ('A-1002','DIS-0001',2, 0.00), ('A-1002','FUR-0003',2, 0.00),
 ('A-1003','PER-0002',1, 0.00), ('A-1003','PER-0001',1, 0.00), ('A-1003','PER-0004',2, 0.00),
 ('A-1004','FUR-0002',1, 0.00),
 ('A-1005','FUR-0001',1, 0.00), ('A-1005','FUR-0003',1, 0.00), ('A-1005','PER-0003',1, 0.00),
 ('A-1006','LAP-0002',1, 0.00), ('A-1006','DIS-0002',1, 0.00),
 ('A-1007','PER-0001',3, 0.00), ('A-1007','AUD-0002',1, 0.00),
 ('A-1008','FUR-0002',1, 0.00), ('A-1008','AUD-0001',1, 0.00),
 ('A-1009','PER-0004',1, 0.00), ('A-1009','PER-0001',1, 0.00),
 ('A-1010','DIS-0001',1, 0.00), ('A-1010','PER-0003',1, 0.00), ('A-1010','PER-0002',1, 0.00),
 ('A-1011','PER-0002',1, 0.00), ('A-1011','PER-0001',2, 0.00),
 ('A-1012','LAP-0002',1, 0.00), ('A-1012','AUD-0001',1, 0.00),
 ('A-1013','FUR-0001',1, 0.00), ('A-1013','PER-0001',1, 0.00),
 ('A-1014','LAP-0001',1, 0.00), ('A-1014','FUR-0003',1, 0.00),
 ('A-1015','DIS-0002',1, 0.00),
 ('A-1016','AUD-0002',1, 0.00), ('A-1016','PER-0001',1, 0.00),
 ('A-1017','PER-0003',2, 0.00)
) AS i(num, sku, qty, disc)
JOIN product p ON p.sku = i.sku;

-- Default shipping/billing address per order.
UPDATE "order" o
SET shipping_address_id = a.address_id, billing_address_id = a.address_id
FROM customer_address a
WHERE a.customer_id = o.customer_id AND a.is_default;

-- --- Voice aliases ----------------------------------------------------------
-- Snapshot each line's cost from the catalogue, mirroring how unit_price was
-- captured. Done as a backfill here only because the seed writes order_item
-- rows without a cost; a real application sets both at insert time.
UPDATE order_item oi SET unit_cost = p.unit_cost
FROM product p WHERE p.product_id = oi.product_id;

INSERT INTO ai.entity_alias (entity_type, entity_id, alias, alias_kind) VALUES
 ('customer', (SELECT customer_id FROM customer WHERE email='robert.chen@example.com'),   'bobby',      'nickname'),
 ('customer', (SELECT customer_id FROM customer WHERE email='robert.chen@example.com'),   'bob chen',   'nickname'),
 ('customer', (SELECT customer_id FROM customer WHERE email='maria.gonzalez@example.com'),'maria g',    'nickname'),
 ('customer', (SELECT customer_id FROM customer WHERE email='daniel.obrien@example.com'), 'danny obrien','nickname'),
 ('customer', (SELECT customer_id FROM customer WHERE email='john.smith@example.com'),    'jon smyth',  'asr_error'),
 ('employee', (SELECT employee_id FROM employee WHERE email='priya.raman@example.com'),   'pria',       'asr_error'),
 ('product',  (SELECT product_id  FROM product  WHERE sku='LAP-0001'),                    'mbp',        'abbreviation'),
 ('product',  (SELECT product_id  FROM product  WHERE sku='LAP-0001'),                    'macbook',    'abbreviation'),
 ('product',  (SELECT product_id  FROM product  WHERE sku='PER-0001'),                    'wireless mowse','asr_error'),
 ('product',  (SELECT product_id  FROM product  WHERE sku='FUR-0001'),                    'sit stand desk','trade_name'),
 ('product',  (SELECT product_id  FROM product  WHERE sku='AUD-0001'),                    'noise cancelling headphones','trade_name'),
 ('product',  (SELECT product_id  FROM product  WHERE sku='DIS-0002'),                    'ultrawide',  'abbreviation');

-- --- Intent catalogue -------------------------------------------------------
-- sql_template uses named :slots. The assistant fills them from resolved_entities
-- and binds them as parameters — it never string-concatenates a value into SQL.
INSERT INTO ai.intent (intent_name, description, sample_utterances, required_slots, sql_template) VALUES
 ('order_status',
  'Where is a specific order right now',
  ARRAY['where is order A-1003','what is the status of my last order','has order a1012 shipped yet'],
  ARRAY['order_number'],
  'SELECT order_number, status, ordered_at, shipped_at, delivered_at, grand_total
     FROM v_order_summary WHERE order_id = :order_id'),

 ('customer_last_order',
  'The most recent order placed by a named customer',
  ARRAY['what did John Smith order last','show me Maria''s latest purchase','when did bobby last buy something'],
  ARRAY['customer_id'],
  'SELECT order_number, ordered_at, status, grand_total
     FROM v_order_summary WHERE customer_id = :customer_id
     ORDER BY ordered_at DESC LIMIT 1'),

 ('customer_spend',
  'How much a customer has spent, optionally within a period',
  ARRAY['how much has Maria spent','what is John Smith''s lifetime value','how much did Aisha spend last month'],
  ARRAY['customer_id'],
  'SELECT customer_name, order_count, lifetime_value, average_order_value, last_order_at
     FROM v_customer_360 WHERE customer_id = :customer_id'),

 ('product_stock',
  'How many units of a product are on hand',
  ARRAY['how many wireless mice do we have','are we out of standing desks','stock level for the MBP'],
  ARRAY['product_id'],
  'SELECT product_name, stock_quantity, reorder_level, needs_restock
     FROM v_product_performance WHERE product_id = :product_id'),

 ('restock_list',
  'Everything at or below its reorder level',
  ARRAY['what needs reordering','which products are running low','anything out of stock'],
  ARRAY[]::text[],
  'SELECT product_name, stock_quantity, reorder_level
     FROM v_product_performance WHERE needs_restock AND is_active
     ORDER BY stock_quantity'),

 ('top_products',
  'Best selling products over a period',
  ARRAY['what sold best this month','top five products','what is our bestseller'],
  ARRAY[]::text[],
  'SELECT product_name, units_sold, revenue
     FROM v_product_performance ORDER BY revenue DESC LIMIT :limit'),

 ('sales_by_rep',
  'How a named sales rep is performing',
  ARRAY['how did Priya do this quarter','who is my top sales rep','how many orders has Sofia closed'],
  ARRAY[]::text[],
  'SELECT employee_name, orders_closed, revenue, customers_served
     FROM v_employee_sales ORDER BY revenue DESC'),

 ('revenue_for_period',
  'Total revenue over a date range',
  ARRAY['how much did we make last week','revenue this month','what were sales yesterday'],
  ARRAY['start_date','end_date'],
  'SELECT sum(revenue) AS revenue, sum(order_count) AS orders
     FROM v_daily_sales WHERE sales_day BETWEEN :start_date AND :end_date'),

 ('order_contents',
  'What was in a given order',
  ARRAY['what was in order A-1001','what did she actually buy','list the items on a1005'],
  ARRAY['order_id'],
  'SELECT product_name, quantity, unit_price, line_total
     FROM v_order_line WHERE order_id = :order_id ORDER BY line_total DESC');

-- --- A sample conversation (shows the logging shape) -------------------------
WITH s AS (
    INSERT INTO ai.voice_session (channel, device_id, employee_id, locale)
    VALUES ('alexa', 'amzn1.echo-api.device.SAMPLE',
            (SELECT employee_id FROM employee WHERE email='priya.raman@example.com'), 'en-US')
    RETURNING session_id
)
INSERT INTO ai.utterance (session_id, turn_no, transcript, asr_confidence, intent_name,
                          intent_confidence, slots, resolved_entities, generated_sql,
                          sql_status, row_count, response_text, latency_ms, was_helpful)
SELECT s.session_id, t.turn, t.transcript, t.asr, t.intent, t.iconf,
       t.slots::jsonb, t.resolved::jsonb, t.sql, t.status::ai.sql_status, t.rows, t.response, t.ms, t.helpful
FROM s, (VALUES
 (1, 'how much has jon smyth spent with us', 0.82, 'customer_spend', 0.91,
     '{"customer":"jon smyth"}', '{"customer_id":1,"match_score":0.71,"match_reason":"alias"}',
     'SELECT customer_name, order_count, lifetime_value FROM v_customer_360 WHERE customer_id = 1',
     'ok', 1, 'John Smith has placed 3 orders totalling 4,216 dollars.', 640, true),
 (2, 'and what did he order last time', 0.94, 'customer_last_order', 0.88,
     '{"customer":"he"}', '{"customer_id":1,"source":"session_context"}',
     'SELECT order_number, ordered_at, status, grand_total FROM v_order_summary WHERE customer_id = 1 ORDER BY ordered_at DESC LIMIT 1',
     'ok', 1, 'Order A-1010 on the 14th, delivered, 875 dollars.', 410, true),
 (3, 'do we have any more of those mowse things', 0.61, 'product_stock', 0.54,
     '{"product":"mowse"}', '{"candidates":[{"product_id":4,"score":0.44}]}',
     NULL, 'rejected', NULL, 'Did you mean the Wireless Mouse?', 300, NULL)
) AS t(turn, transcript, asr, intent, iconf, slots, resolved, sql, status, rows, response, ms, helpful);

-- Keep the last-mentioned entity on the session, which is what made turn 2 work.
UPDATE ai.voice_session
SET context = '{"last_customer_id": 1, "last_order_number": "A-1010"}'::jsonb
WHERE device_id = 'amzn1.echo-api.device.SAMPLE';

ANALYZE;

-- 02_core_tables.sql — MySQL port. Employee : Customer : Order : Product core.
--
-- Naming rule is unchanged: table and column names are the words a person would
-- actually say out loud, because the NL->SQL layer reads these identifiers as
-- its primary schema signal.
--
-- PORTING NOTES (differences from the Postgres original, all deliberate):
--
--   bigint GENERATED ALWAYS AS IDENTITY -> BIGINT AUTO_INCREMENT
--   numeric(12,2)                       -> DECIMAL(12,2)
--   citext                              -> VARCHAR (server collation is
--                                          case-insensitive, so UNIQUE(email)
--                                          still rejects Bob@x vs bob@x)
--   text                                -> VARCHAR(n), sized per column. MySQL
--                                          cannot put a DEFAULT on TEXT
--                                          (ERROR 1101) and needs a prefix
--                                          length to index it, so anything
--                                          defaulted or indexed is VARCHAR.
--   timestamptz                         -> DATETIME. *** NO TIMEZONE. ***
--                                          Store UTC by convention. TIMESTAMP
--                                          would keep UTC semantics but dies
--                                          in 2038, so DATETIME it is.
--   named ENUM types                    -> inline ENUM(...) at each use site
--   "order"                             -> `order`
--   set_updated_at() + 4 triggers       -> native ON UPDATE CURRENT_TIMESTAMP
--
-- THREE THINGS THE PORT COULD NOT KEEP AS-WRITTEN:
--
--   1. CHECK (manager_id IS DISTINCT FROM employee_id)
--      MySQL forbids a CHECK that references an AUTO_INCREMENT column
--      (ERROR 3818). Re-implemented as a BEFORE INSERT/UPDATE trigger pair
--      that SIGNALs. Same guarantee, worse error message.
--
--   2. The composite address FKs were ON DELETE SET NULL. MySQL rejects
--      SET NULL when any column in the FK is NOT NULL (ERROR 1830), and
--      customer_id is NOT NULL. They are now ON DELETE RESTRICT.
--      Note this was latent in the Postgres version too: on PG14 a SET NULL
--      there would have tried to null customer_id and failed at runtime.
--      RESTRICT is the behaviour you actually want.
--
--   3. product.search_document (tsvector) is gone. MySQL has no tsvector.
--      Replaced by a FULLTEXT index over the same three columns (see
--      03_indexes.sql); queries change from @@ to MATCH ... AGAINST.

-- ---------------------------------------------------------------------------
-- Employee
-- ---------------------------------------------------------------------------
CREATE TABLE employee (
    employee_id   BIGINT AUTO_INCREMENT PRIMARY KEY,
    first_name    VARCHAR(100) NOT NULL,
    last_name     VARCHAR(100) NOT NULL,
    full_name     VARCHAR(201) GENERATED ALWAYS AS
                      (TRIM(CONCAT(COALESCE(first_name,''), ' ', COALESCE(last_name,'')))) STORED,
    email         VARCHAR(255) NOT NULL UNIQUE,
    phone         VARCHAR(40),
    job_title     VARCHAR(100) NOT NULL,
    department    VARCHAR(100) NOT NULL,
    manager_id    BIGINT,
    hired_on      DATE NOT NULL DEFAULT (CURRENT_DATE),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT employee_manager_fk FOREIGN KEY (manager_id)
        REFERENCES employee(employee_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Customer
-- ---------------------------------------------------------------------------
CREATE TABLE customer (
    customer_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    first_name         VARCHAR(100) NOT NULL,
    last_name          VARCHAR(100) NOT NULL,
    full_name          VARCHAR(201) GENERATED ALWAYS AS
                           (TRIM(CONCAT(COALESCE(first_name,''), ' ', COALESCE(last_name,'')))) STORED,
    email              VARCHAR(255) NOT NULL UNIQUE,
    phone              VARCHAR(40),
    tier               ENUM('standard','silver','gold','platinum') NOT NULL DEFAULT 'standard',
    account_manager_id BIGINT,
    signed_up_on       DATE NOT NULL DEFAULT (CURRENT_DATE),
    is_active          BOOLEAN NOT NULL DEFAULT TRUE,
    created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT customer_account_manager_fk FOREIGN KEY (account_manager_id)
        REFERENCES employee(employee_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE customer_address (
    address_id    BIGINT AUTO_INCREMENT PRIMARY KEY,
    customer_id   BIGINT NOT NULL,
    kind          ENUM('billing','shipping') NOT NULL,
    label         VARCHAR(100),               -- "home", "the office" — what the caller says
    line1         VARCHAR(200) NOT NULL,
    line2         VARCHAR(200),
    city          VARCHAR(100) NOT NULL,
    state_region  VARCHAR(100),
    postal_code   VARCHAR(20) NOT NULL,
    country_code  CHAR(2) NOT NULL DEFAULT 'US',
    is_default    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Replaces the Postgres partial unique index
    --   CREATE UNIQUE INDEX ... ON customer_address (customer_id, kind) WHERE is_default;
    -- MySQL has no partial indexes. This generated column is NULL whenever the
    -- row is not a default, and MySQL permits unlimited NULLs in a UNIQUE index,
    -- so the uniqueness only bites on the rows that are defaults. Same rule:
    -- at most one default address per customer per kind.
    -- VIRTUAL, not STORED: MySQL refuses ON DELETE CASCADE on a column that a
    -- STORED generated column depends on (ERROR 1215), and customer_id is both.
    -- A VIRTUAL column still takes a UNIQUE index and the cascade still fires.
    default_key   VARCHAR(64) GENERATED ALWAYS AS
                      (IF(is_default, CONCAT(customer_id, '/', kind), NULL)) VIRTUAL,

    -- lets orders prove an address belongs to the ordering customer (composite FK below)
    UNIQUE KEY customer_address_addr_cust (address_id, customer_id),
    UNIQUE KEY customer_address_one_default (default_key),
    CONSTRAINT customer_address_customer_fk FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Product
-- ---------------------------------------------------------------------------
CREATE TABLE product_category (
    category_id        BIGINT AUTO_INCREMENT PRIMARY KEY,
    name               VARCHAR(100) NOT NULL UNIQUE,
    parent_category_id BIGINT,
    description        VARCHAR(500),
    CONSTRAINT product_category_parent_fk FOREIGN KEY (parent_category_id)
        REFERENCES product_category(category_id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE product (
    product_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    sku            VARCHAR(64) NOT NULL UNIQUE,
    name           VARCHAR(200) NOT NULL,
    brand          VARCHAR(100),
    description    VARCHAR(1000),
    category_id    BIGINT,
    unit_price     DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    -- What WE pay for one unit. Drives cost of goods sold in the P&L. Like
    -- unit_price this is the CURRENT figure and moves with supplier pricing;
    -- order_item.unit_cost snapshots it at the moment of sale.
    unit_cost      DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
    currency       CHAR(3) NOT NULL DEFAULT 'USD',
    stock_quantity INT NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    reorder_level  INT NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    -- NOTE: the Postgres original had a generated tsvector column here
    -- (search_document) for "do we sell anything like a standing desk?".
    -- MySQL has no tsvector; see the FULLTEXT index in 03_indexes.sql.
    CONSTRAINT product_category_fk FOREIGN KEY (category_id)
        REFERENCES product_category(category_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Order
-- ---------------------------------------------------------------------------
CREATE TABLE `order` (
    order_id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    -- Human- and voice-friendly reference: "order A-1042". Assigned by the
    -- order_number_assign trigger below, because MySQL forbids a stored
    -- function in a column DEFAULT (ERROR 3770).
    order_number        VARCHAR(20) NOT NULL UNIQUE,
    customer_id         BIGINT NOT NULL,
    sales_rep_id        BIGINT,
    status              ENUM('pending','paid','packed','shipped',
                             'delivered','cancelled','refunded') NOT NULL DEFAULT 'pending',
    ordered_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    shipped_at          DATETIME,
    delivered_at        DATETIME,
    cancelled_at        DATETIME,
    method              ENUM('card','paypal','bank_transfer',
                             'cash_on_delivery','store_credit'),
    shipping_address_id BIGINT,
    billing_address_id  BIGINT,
    shipping_fee        DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (shipping_fee >= 0),
    tax_total           DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (tax_total >= 0),
    discount_total      DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (discount_total >= 0),
    currency            CHAR(3) NOT NULL DEFAULT 'USD',
    notes               VARCHAR(1000),
    created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT order_customer_fk FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id) ON DELETE RESTRICT,
    CONSTRAINT order_sales_rep_fk FOREIGN KEY (sales_rep_id)
        REFERENCES employee(employee_id) ON DELETE SET NULL,

    -- An order can only ship to an address owned by the ordering customer.
    -- RESTRICT, not SET NULL: see porting note 2 at the top of this file.
    CONSTRAINT order_shipping_address_fk FOREIGN KEY (shipping_address_id, customer_id)
        REFERENCES customer_address (address_id, customer_id) ON DELETE RESTRICT,
    CONSTRAINT order_billing_address_fk FOREIGN KEY (billing_address_id, customer_id)
        REFERENCES customer_address (address_id, customer_id) ON DELETE RESTRICT,

    CONSTRAINT order_shipped_after_ordered   CHECK (shipped_at IS NULL OR shipped_at >= ordered_at),
    CONSTRAINT order_delivered_after_shipped CHECK (delivered_at IS NULL OR shipped_at IS NULL
                                                    OR delivered_at >= shipped_at),
    CONSTRAINT order_cancelled_consistent    CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
) ENGINE=InnoDB;

CREATE TABLE order_item (
    order_item_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id      BIGINT NOT NULL,
    product_id    BIGINT NOT NULL,
    quantity      INT NOT NULL CHECK (quantity > 0),
    -- Price snapshot. Never join back to product.unit_price for historical money;
    -- the catalogue price moves and old orders must not move with it.
    unit_price    DECIMAL(12,2) NOT NULL CHECK (unit_price >= 0),
    -- COST snapshot, same reasoning as unit_price above: what the unit cost US
    -- when it sold. Historical gross profit must use this, never
    -- product.unit_cost, which moves with supplier pricing.
    unit_cost     DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
    discount      DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    line_total    DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_price - discount) STORED,
    -- Cost side of the line. Customer discounts reduce revenue, not our cost,
    -- so discount is deliberately absent here.
    line_cost     DECIMAL(12,2) GENERATED ALWAYS AS (quantity * unit_cost) STORED,
    UNIQUE KEY order_item_order_product (order_id, product_id),
    CONSTRAINT order_item_order_fk FOREIGN KEY (order_id)
        REFERENCES `order`(order_id) ON DELETE CASCADE,
    CONSTRAINT order_item_product_fk FOREIGN KEY (product_id)
        REFERENCES product(product_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

-- Status transitions, so "when did that ship?" and "who cancelled it?" are answerable.
CREATE TABLE order_status_history (
    history_id  BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id    BIGINT NOT NULL,
    old_status  ENUM('pending','paid','packed','shipped',
                     'delivered','cancelled','refunded'),
    new_status  ENUM('pending','paid','packed','shipped',
                     'delivered','cancelled','refunded') NOT NULL,
    changed_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    changed_by  BIGINT,
    -- VARCHAR not TEXT: MySQL cannot DEFAULT a TEXT column (ERROR 1101).
    source      VARCHAR(16) NOT NULL DEFAULT 'app',   -- 'app' | 'voice' | 'batch'
    CONSTRAINT order_status_history_order_fk FOREIGN KEY (order_id)
        REFERENCES `order`(order_id) ON DELETE CASCADE,
    CONSTRAINT order_status_history_changed_by_fk FOREIGN KEY (changed_by)
        REFERENCES employee(employee_id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- Triggers.
--
-- The four Postgres *_touch triggers are gone: MySQL's native
-- ON UPDATE CURRENT_TIMESTAMP on each updated_at column does the same job.
--
-- What IS here replaces three things MySQL would not accept as declarations:
--   1. the order_number DEFAULT   (no stored function in a DEFAULT, ERROR 3770)
--   2. log_order_status()         (no "AFTER INSERT OR UPDATE OF status",
--                                  and no shared trigger function, so the one
--                                  plpgsql function becomes two triggers)
--   3. employee_not_own_manager   (CHECK cannot reference an AUTO_INCREMENT
--                                  column, ERROR 3818)
--
-- DELIMITER is a mysql *client* directive, not server SQL. It works because
-- load-mysql.sh pipes this file through the `mysql` CLI.
-- ---------------------------------------------------------------------------
DELIMITER $$

-- 1. "order A-1042". Pre-increments, so the first number issued is A-1001,
--    matching Postgres' CREATE SEQUENCE order_number_seq START 1000 + nextval.
CREATE TRIGGER order_number_assign
BEFORE INSERT ON `order`
FOR EACH ROW
BEGIN
    IF NEW.order_number IS NULL OR NEW.order_number = '' THEN
        UPDATE order_number_seq SET last_number = last_number + 1 WHERE only_row = 1;
        SET NEW.order_number = CONCAT('A-', (SELECT last_number FROM order_number_seq WHERE only_row = 1));
    END IF;
END$$

-- 2a. Record the birth of every order.
CREATE TRIGGER order_status_logged_insert
AFTER INSERT ON `order`
FOR EACH ROW
BEGIN
    INSERT INTO order_status_history (order_id, old_status, new_status)
    VALUES (NEW.order_id, NULL, NEW.status);
END$$

-- 2b. Record every subsequent change. `<=>` is MySQL's NULL-safe equality,
--     i.e. exactly Postgres' IS NOT DISTINCT FROM.
CREATE TRIGGER order_status_logged_update
AFTER UPDATE ON `order`
FOR EACH ROW
BEGIN
    IF NOT (NEW.status <=> OLD.status) THEN
        INSERT INTO order_status_history (order_id, old_status, new_status)
        VALUES (NEW.order_id, OLD.status, NEW.status);
    END IF;
END$$

-- 3. Nobody manages themselves. On INSERT, employee_id is 0 until AUTO_INCREMENT
--    assigns it, so this only bites when an explicit id is supplied (as the seed
--    does). On UPDATE the id is known and the check is exact.
CREATE TRIGGER employee_not_own_manager_insert
BEFORE INSERT ON employee
FOR EACH ROW
BEGIN
    IF NEW.manager_id IS NOT NULL AND NEW.manager_id = NEW.employee_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'employee_not_own_manager: an employee cannot be their own manager';
    END IF;
END$$

CREATE TRIGGER employee_not_own_manager_update
BEFORE UPDATE ON employee
FOR EACH ROW
BEGIN
    IF NEW.manager_id IS NOT NULL AND NEW.manager_id = NEW.employee_id THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'employee_not_own_manager: an employee cannot be their own manager';
    END IF;
END$$

DELIMITER ;

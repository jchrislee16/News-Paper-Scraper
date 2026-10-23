-- 02_core_tables.sql — Employee : Customer : Order : Product core.
--
-- Naming rule for this database: table and column names are the words a person
-- would actually say out loud. The NL->SQL layer reads these identifiers as its
-- primary schema signal, so `ordered_at` beats `ord_dt` and `unit_price` beats `amt`.

-- ---------------------------------------------------------------------------
-- Employee
-- ---------------------------------------------------------------------------
CREATE TABLE employee (
    employee_id   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name    text NOT NULL,
    last_name     text NOT NULL,
    full_name     text GENERATED ALWAYS AS
                      (btrim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))) STORED,
    email         citext NOT NULL UNIQUE,
    phone         text,
    job_title     text NOT NULL,
    department    text NOT NULL,
    manager_id    bigint REFERENCES employee(employee_id) ON DELETE SET NULL,
    hired_on      date NOT NULL DEFAULT current_date,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT employee_not_own_manager CHECK (manager_id IS DISTINCT FROM employee_id)
);

-- ---------------------------------------------------------------------------
-- Customer
-- ---------------------------------------------------------------------------
CREATE TABLE customer (
    customer_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    first_name         text NOT NULL,
    last_name          text NOT NULL,
    full_name          text GENERATED ALWAYS AS
                           (btrim(coalesce(first_name,'') || ' ' || coalesce(last_name,''))) STORED,
    email              citext NOT NULL UNIQUE,
    phone              text,
    tier               loyalty_tier NOT NULL DEFAULT 'standard',
    account_manager_id bigint REFERENCES employee(employee_id) ON DELETE SET NULL,
    signed_up_on       date NOT NULL DEFAULT current_date,
    is_active          boolean NOT NULL DEFAULT true,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE customer_address (
    address_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id   bigint NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    kind          address_type NOT NULL,
    label         text,                       -- "home", "the office" — what the caller says
    line1         text NOT NULL,
    line2         text,
    city          text NOT NULL,
    state_region  text,
    postal_code   text NOT NULL,
    country_code  char(2) NOT NULL DEFAULT 'US',
    is_default    boolean NOT NULL DEFAULT false,
    created_at    timestamptz NOT NULL DEFAULT now(),

    -- At most one default address per customer per kind, enforced via a UNIQUE
    -- index on this key rather than a partial index, so the MySQL port in
    -- sql-mysql/ can use the SAME column name and the SAME mechanism (MySQL has
    -- no partial indexes, but does allow unlimited NULLs in a UNIQUE index).
    --
    -- The CASE spells both enum labels out instead of casting `kind` to text,
    -- because enum_out() is only STABLE and a generated column needs an
    -- IMMUTABLE expression. ADD A NEW address_type AND YOU MUST ADD AN ARM HERE
    -- — the CHECK below is what stops that being a silent hole.
    default_key   text GENERATED ALWAYS AS (
        CASE WHEN is_default THEN customer_id::text || '/' ||
             (CASE kind WHEN 'billing' THEN 'billing' WHEN 'shipping' THEN 'shipping' END)
        END
    ) STORED,

    -- lets orders prove an address belongs to the ordering customer (composite FK below)
    UNIQUE (address_id, customer_id),

    -- If a future address_type has no arm in the CASE above, default_key silently
    -- goes NULL and the uniqueness stops applying to it. This turns that into a
    -- loud failure on the very first insert instead.
    CONSTRAINT customer_address_default_key_complete
        CHECK (is_default = (default_key IS NOT NULL))
);

CREATE UNIQUE INDEX customer_address_one_default
    ON customer_address (default_key);

-- ---------------------------------------------------------------------------
-- Product
-- ---------------------------------------------------------------------------
CREATE TABLE product_category (
    category_id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name               text NOT NULL UNIQUE,
    parent_category_id bigint REFERENCES product_category(category_id) ON DELETE SET NULL,
    description        text
);

CREATE TABLE product (
    product_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku            text NOT NULL UNIQUE,
    name           text NOT NULL,
    brand          text,
    description    text,
    category_id    bigint REFERENCES product_category(category_id) ON DELETE SET NULL,
    unit_price     numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    -- What WE pay for one unit. Drives cost of goods sold in the P&L. Like
    -- unit_price this is the CURRENT figure and moves with supplier pricing;
    -- order_item.unit_cost snapshots it at the moment of sale.
    unit_cost      numeric(12,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
    currency       char(3) NOT NULL DEFAULT 'USD',
    stock_quantity integer NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    reorder_level  integer NOT NULL DEFAULT 0 CHECK (reorder_level >= 0),
    is_active      boolean NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    -- Full-text handle for "do we sell anything like a standing desk?"
    search_document tsvector GENERATED ALWAYS AS (
        to_tsvector('english',
            coalesce(name,'') || ' ' || coalesce(brand,'') || ' ' || coalesce(description,''))
    ) STORED
);

-- ---------------------------------------------------------------------------
-- Order
-- ---------------------------------------------------------------------------
CREATE SEQUENCE order_number_seq START 1000;

-- Human- and voice-friendly order reference: "order A-1042".
CREATE OR REPLACE FUNCTION next_order_number() RETURNS text
LANGUAGE sql VOLATILE AS $$
    SELECT 'A-' || nextval('order_number_seq')::text;
$$;

CREATE TABLE "order" (
    order_id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_number        text NOT NULL UNIQUE DEFAULT next_order_number(),
    customer_id         bigint NOT NULL REFERENCES customer(customer_id) ON DELETE RESTRICT,
    sales_rep_id        bigint REFERENCES employee(employee_id) ON DELETE SET NULL,
    status              order_status NOT NULL DEFAULT 'pending',
    ordered_at          timestamptz NOT NULL DEFAULT now(),
    shipped_at          timestamptz,
    delivered_at        timestamptz,
    cancelled_at        timestamptz,
    method              payment_method,
    shipping_address_id bigint,
    billing_address_id  bigint,
    shipping_fee        numeric(12,2) NOT NULL DEFAULT 0 CHECK (shipping_fee >= 0),
    tax_total           numeric(12,2) NOT NULL DEFAULT 0 CHECK (tax_total >= 0),
    discount_total      numeric(12,2) NOT NULL DEFAULT 0 CHECK (discount_total >= 0),
    currency            char(3) NOT NULL DEFAULT 'USD',
    notes               text,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    -- An order can only ship to an address owned by the ordering customer.
    FOREIGN KEY (shipping_address_id, customer_id)
        REFERENCES customer_address (address_id, customer_id) ON DELETE SET NULL,
    FOREIGN KEY (billing_address_id, customer_id)
        REFERENCES customer_address (address_id, customer_id) ON DELETE SET NULL,

    CONSTRAINT order_shipped_after_ordered   CHECK (shipped_at   IS NULL OR shipped_at   >= ordered_at),
    CONSTRAINT order_delivered_after_shipped CHECK (delivered_at IS NULL OR shipped_at IS NULL
                                                    OR delivered_at >= shipped_at),
    CONSTRAINT order_cancelled_consistent    CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL))
);

CREATE TABLE order_item (
    order_item_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id      bigint NOT NULL REFERENCES "order"(order_id) ON DELETE CASCADE,
    product_id    bigint NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    quantity      integer NOT NULL CHECK (quantity > 0),
    -- Price snapshot. Never join back to product.unit_price for historical money;
    -- the catalogue price moves and old orders must not move with it.
    unit_price    numeric(12,2) NOT NULL CHECK (unit_price >= 0),
    -- COST snapshot, same reasoning as unit_price above: what the unit cost US
    -- when it sold. Historical gross profit must use this, never
    -- product.unit_cost, which moves with supplier pricing.
    unit_cost     numeric(12,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
    discount      numeric(12,2) NOT NULL DEFAULT 0 CHECK (discount >= 0),
    line_total    numeric(12,2) GENERATED ALWAYS AS (quantity * unit_price - discount) STORED,
    -- Cost side of the line. Customer discounts reduce revenue, not our cost,
    -- so discount is deliberately absent here.
    line_cost     numeric(12,2) GENERATED ALWAYS AS (quantity * unit_cost) STORED,
    UNIQUE (order_id, product_id)
);

-- Status transitions, so "when did that ship?" and "who cancelled it?" are answerable.
CREATE TABLE order_status_history (
    history_id  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id    bigint NOT NULL REFERENCES "order"(order_id) ON DELETE CASCADE,
    old_status  order_status,
    new_status  order_status NOT NULL,
    changed_at  timestamptz NOT NULL DEFAULT now(),
    changed_by  bigint REFERENCES employee(employee_id) ON DELETE SET NULL,
    source      text NOT NULL DEFAULT 'app'   -- 'app' | 'voice' | 'batch'
);

CREATE TRIGGER employee_touch BEFORE UPDATE ON employee
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER customer_touch BEFORE UPDATE ON customer
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER product_touch BEFORE UPDATE ON product
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER order_touch BEFORE UPDATE ON "order"
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Record every status change without the application having to remember to.
CREATE OR REPLACE FUNCTION log_order_status() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO order_status_history (order_id, old_status, new_status)
        VALUES (NEW.order_id, NULL, NEW.status);
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO order_status_history (order_id, old_status, new_status)
        VALUES (NEW.order_id, OLD.status, NEW.status);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER order_status_logged AFTER INSERT OR UPDATE OF status ON "order"
    FOR EACH ROW EXECUTE FUNCTION log_order_status();

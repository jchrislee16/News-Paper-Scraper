-- 01_setup.sql — MySQL 8/9 port of the Postgres 01_extensions.sql.
--
-- Almost all of the Postgres original has no MySQL equivalent and is gone:
--
--   CREATE EXTENSION citext        -> not needed. The server collation
--                                    utf8mb4_0900_ai_ci is already
--                                    case-insensitive, so VARCHAR compares
--                                    case-insensitively for free.
--   CREATE EXTENSION pg_trgm      -> NO EQUIVALENT. similarity() does not
--                                    exist in MySQL. See 05_ai_layer.sql for
--                                    what this costs the resolvers.
--   CREATE EXTENSION fuzzystrmatch-> partially. MySQL has SOUNDEX() but no
--                                    dmetaphone() and no levenshtein().
--   CREATE EXTENSION unaccent     -> NO EQUIVALENT.
--
--   CREATE TYPE ... AS ENUM (x4)  -> MySQL has no reusable named enum types.
--                                    The four vocabularies are now declared
--                                    INLINE on each column in 02_core_tables.
--                                    They are repeated at every use site; if
--                                    you add a status you must edit every one.
--                                    `order_status` is the one to watch: it
--                                    appears on `order`.status AND on
--                                    order_status_history.old_status/new_status.
--
--   set_updated_at() trigger fn   -> not needed. MySQL has native
--                                    `ON UPDATE CURRENT_TIMESTAMP` on the
--                                    column itself, which replaces all four
--                                    _touch triggers.
--
-- What remains: a stand-in for the order_number sequence. MySQL has no
-- CREATE SEQUENCE and forbids a stored function in a column DEFAULT
-- (ERROR 3770), so the human-friendly order reference "A-1042" is produced by
-- a counter table plus a BEFORE INSERT trigger (see 02_core_tables.sql).

-- NOTE: sql_mode and NAMES are NOT set here. load-mysql.sh runs each file in a
-- separate `mysql` process, so a SET SESSION in this file would apply only to
-- this file and silently not to 02..08 — exactly the kind of difference that
-- makes one file strict and the next lenient. They are set once, for every
-- connection, via --init-command in load-mysql.sh instead.

-- Stands in for: CREATE SEQUENCE order_number_seq START 1000;
-- Pre-incremented by the trigger, so the first order number issued is A-1001,
-- matching the Postgres original.
CREATE TABLE order_number_seq (
    only_row   TINYINT NOT NULL DEFAULT 1 PRIMARY KEY,
    last_number BIGINT  NOT NULL,
    CONSTRAINT order_number_seq_single_row CHECK (only_row = 1)
) ENGINE=InnoDB;

INSERT INTO order_number_seq (only_row, last_number) VALUES (1, 1000);

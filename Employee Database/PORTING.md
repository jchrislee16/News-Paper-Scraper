# Postgres → MySQL port

The schema exists twice. `sql/` is the PostgreSQL original; `sql-mysql/` is the
MySQL 8/9 port. All 8 tables, 15 CHECK constraints, 13 foreign keys, 5 generated
columns, 11 views and the accounting reports made it across. The fuzzy entity
resolution did not, and two runaway-query guards got weaker.

Ported and verified against MySQL 9.2.0 (Homebrew) and PostgreSQL 14.19.

    ./load.sh                   # build the PostgreSQL database
    ./load-mysql.sh             # build the MySQL database
    ./load-mysql.sh scratch_db  # a differently-named MySQL database

## Parity

Every view and report was compared row by row between the two engines after a
clean rebuild of each. 11 of 11 checks identical to the cent:

| Check | Rows |
|---|---|
| row counts, all 8 tables | 8 |
| `v_order_summary` | 17 |
| `v_order_line` | 36 |
| `v_customer_360` (incl. `average_order_value`) | 8 |
| `v_product_performance` (incl. `cogs`, `gross_profit`, `margin_pct`) | 14 |
| `v_employee_sales` | 6 |
| `v_daily_sales` | 15 |
| `v_customer_balance` | 2 |
| `v_ar_aging` | 2 |
| `order_status_history` (trigger-written) | 17 |
| `fn_profit_and_loss` vs `fn_profit_and_loss` | 14 lines |

Two comparisons initially showed differences that turned out to be client
rendering, not data: Postgres prints a numeric zero as `0` where MySQL prints
`0.00`, and `psql -At` prints NULL as empty where `mysql -N` prints the literal
`NULL`. Both were confirmed identical once normalised. Worth knowing before you
trust a future diff.

## What was lost

**Trigram similarity. This is the big one.** `similarity()`, `dmetaphone()`,
`levenshtein()` and `unaccent()` do not exist in MySQL — only `SOUNDEX()` does.
The Postgres resolvers scored on a *continuous* similarity that degraded
gracefully with each wrong character. The MySQL resolvers score on *discrete
tiers* (alias 1.00 / exact 0.95 / email 0.90 / prefix 0.80 / substring 0.75 /
fulltext 0.41–0.90 scaled by relevance / soundex 0.70 / word 0.65). A typo that
clears no tier returns **nothing** rather than a low score.

Measured on the seed data, the practical damage is smaller than that sounds:

| Spoken | Postgres | MySQL |
|---|---|---|
| `jon smyth` | 1.00 alias | 1.00 alias |
| `bobby` | 1.00 alias | 1.00 alias |
| `maria gonzales` | 0.76 fuzzy_name | 0.70 sounds_like |
| `smyth` | 0.90 word_match | 0.65 word_match |
| `keybord` | 0.49 word_match | 0.65 word_match |
| `mackbook` | 0.55 sounds_like | 0.65 word_match |
| `ergonomic chiar` | 0.56 word_match | 0.41 fulltext |
| `jhon` | **no match** | 0.65 word_match |

MySQL found everything Postgres found, and one thing it didn't. The loss is in
*confidence resolution*, not raw hit rate: the scores are coarser, so "did you
mean…?" has less to work with, and the failure mode is abrupt rather than
gradual. If resolution quality starts to matter, do the fuzzy match in the
application (`rapidfuzz`) and use the procedures only for the exact tiers.

**`fn_profit_and_loss` is no longer composable.** MySQL functions cannot return
a result set, so it is `CALL fn_profit_and_loss(from, to)` now. You cannot
`SELECT FROM` it, filter it, join it, or wrap it in a view. `web/app_mysql.py`
does the trimming that used to be a `SELECT` list.

**Two runaway-query guards.** `07_roles.sql` attached `statement_timeout = '5s'`
to the `ai_assistant` role, so the guard held regardless of which client
connected. MySQL cannot attach an execution limit to a user or role — only
`max_execution_time`, per session, SELECT-only. It is now set by the client
(`web/app_mysql.py`), so **any new client must set it too**.
`idle_in_transaction_session_timeout` has no MySQL equivalent at all.

**Timezone fidelity.** `timestamptz` → `DATETIME`, which carries no timezone.
Store UTC by convention. `TIMESTAMP` would have kept UTC semantics but caps out
in 2038.

**Partial indexes.** Four Postgres indexes carried a `WHERE`; MySQL has none, so
they now cover every row. `product.search_document` (tsvector) was replaced by a
`FULLTEXT` index — same columns, `MATCH … AGAINST` instead of `@@`.

## What MySQL refused, and why each refusal was fair

Four restrictions forced real design changes rather than syntax swaps. Three of
them exposed latent problems in the Postgres version.

**`CHECK` cannot reference an `AUTO_INCREMENT` column** (ERROR 3818).
`employee_not_own_manager` became a `BEFORE INSERT`/`BEFORE UPDATE` trigger pair
that `SIGNAL`s. Same guarantee, worse error message.

**`ON DELETE SET NULL` is rejected when any column in the foreign key is
`NOT NULL`** (ERROR 1830). The two composite address FKs are `RESTRICT` now.
This was already broken in Postgres: on PG14, `SET NULL` across
`(shipping_address_id, customer_id)` would have tried to null `customer_id`,
which is `NOT NULL`, and failed at delete time. `RESTRICT` is the behaviour you
actually want.

**`CHECK` cannot reference a column that carries a referential action**
(ERROR 3823). `voice_session_has_a_speaker` became triggers. Also a latent
Postgres bug: both speaker FKs are `ON DELETE SET NULL`, so deleting the one
employee a session named would null the column and violate the CHECK. The
trigger version guards the write path without making a later cascade illegal.

**`ON DELETE CASCADE` is rejected on the base column of a `STORED` generated
column** (ERROR 1215). `customer_address.default_key` is `VIRTUAL` instead. It
still takes a UNIQUE index and the cascade still fires.

## Things that needed inventing

**The partial unique index survived.** Postgres had
`CREATE UNIQUE INDEX … ON customer_address (customer_id, kind) WHERE is_default`
for "at most one default address per customer per kind". MySQL has no partial
indexes, but it permits unlimited NULLs in a UNIQUE index, so a generated column
that is `NULL` for non-defaults reproduces the rule exactly:

```sql
default_key VARCHAR(64) GENERATED ALWAYS AS
    (IF(is_default, CONCAT(customer_id, '/', kind), NULL)) VIRTUAL,
UNIQUE KEY customer_address_one_default (default_key)
```

**View comments had to be rebuilt.** MySQL cannot comment a view at all:
`ALTER TABLE v COMMENT` fails with *"not BASE TABLE"*, there is no
`ALTER VIEW … COMMENT`, and `TABLES.TABLE_COMMENT` for a view is the literal
string `'VIEW'`. Ten view descriptions would have vanished silently out of the
model's prompt — including "`v_customer_360` already excludes refunded orders"
and "the P&L bottom line is gross profit, not net income". They live in the
`ai_object_doc` table, which `ai_schema_context` joins back in.

**`ai_enum_values` parses `COLUMN_TYPE`.** Postgres read `pg_enum` because its
enums are named types. MySQL enums are inline column definitions, so the only
record of a vocabulary is the string `enum('pending','paid',…)`. A recursive CTE
splits it. Consequence: `enum_name` is now `table.column`, and the same
vocabulary appears more than once (`order.status`,
`ai_utterance.new_status`, …).

**`ai_schema_context` survived, which was the point.** MySQL exposes
`COLUMNS.COLUMN_COMMENT` and `TABLES.TABLE_COMMENT`, so documenting a column is
still the same act as teaching the assistant about it. Keep `06_comments.sql`
current.

## Mechanical substitutions

| Postgres | MySQL | Sites |
|---|---|---|
| `bigint GENERATED ALWAYS AS IDENTITY` | `BIGINT AUTO_INCREMENT` | 10 |
| `numeric(12,2)` | `DECIMAL(12,2)` | 16 |
| `citext` | `VARCHAR` + `utf8mb4_0900_ai_ci` collation | 5 |
| `timestamptz` | `DATETIME` | 19 |
| named `CREATE TYPE … AS ENUM` | inline `ENUM(…)` at each column | 4 types |
| `FILTER (WHERE p)` | `SUM/COUNT/MAX(CASE WHEN p THEN x END)` | 21 |
| `::cast` | `CAST(x AS …)` | 67 |
| `DISTINCT ON (k)` | `ROW_NUMBER() OVER (PARTITION BY k ORDER BY …) = 1` | 3 |
| `date_trunc('day', x)::date` | `DATE(x)` | 1 |
| `current_date - d` | `DATEDIFF(CURRENT_DATE, d)` | 4 |
| `IS DISTINCT FROM` | `NOT (a <=> b)` | 3 |
| `set_updated_at()` + 4 triggers | native `ON UPDATE CURRENT_TIMESTAMP` | 4 |
| `CREATE SEQUENCE` + `nextval` in a DEFAULT | counter table + `BEFORE INSERT` trigger | 1 |
| `text[]` | `JSON` + `JSON_TABLE` to read back | 2 |
| `jsonb` | `JSON` | 4 |
| `uuid DEFAULT gen_random_uuid()` | `CHAR(36) DEFAULT (UUID())` | 1 |
| `INSERT … RETURNING` | `INSERT` then look up the natural key | 1 |
| `UPDATE … FROM` | `UPDATE … JOIN … SET` | 3 |
| `JOIN (VALUES …) AS a(c1, c2)` | `UNION ALL` of `SELECT`s (MySQL has no derived column list) | 6 |
| `array_agg(… ORDER BY …)[1:5]` | `SUBSTRING_INDEX(GROUP_CONCAT(… ORDER BY …), sep, 5)` | 1 |
| `GRANT … ON ALL TABLES IN SCHEMA` | `GRANT … ON \`db\`.*` | 6 |
| `ALTER DEFAULT PRIVILEGES` | not needed — a database grant covers future tables | 2 |
| `ai.` schema | `ai_` table prefix | 7 objects |
| `LATERAL` | works as-is (MySQL 8.0.14+) | 3 |

`%s` placeholders are identical in `psycopg2` and `PyMySQL`, so every bound
parameter in the web app ported unchanged.

## Two traps for whoever maintains this

**`06_comments.sql` can silently revert a schema change.** MySQL makes you
restate a column's entire definition to set its comment. If you change a type,
default or nullability in `02_core_tables.sql` and do not mirror it in
`06_comments.sql`, loading the comments file will quietly undo your change. The
definitions in there were generated from the live schema, not typed by hand.

**`sql_mode` must be set by the loader, not by a `.sql` file.**
`load-mysql.sh` runs each file in a separate `mysql` process, so a
`SET SESSION sql_mode` inside `01_setup.sql` would apply to that file only and
silently not to `02`..`08`. It is set once via `--init-command`.

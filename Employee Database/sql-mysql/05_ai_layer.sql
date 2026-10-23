-- 05_ai_layer.sql — MySQL port. Everything that exists because of the voice assistant.
--
-- Three jobs live here:
--   1. ENTITY RESOLUTION  — turn a messy spoken phrase into a primary key.
--   2. CONVERSATION STATE — remember the session so "and his last order?" works.
--   3. SELF-DESCRIPTION   — hand the model an accurate schema prompt at runtime.
--
-- ===========================================================================
-- *** THIS IS THE FILE THE PORT DAMAGED. READ BEFORE TRUSTING A RESOLVER. ***
-- ===========================================================================
--
-- NAMESPACE. Postgres kept all of this in a separate `ai` schema. MySQL has no
-- schemas inside a database ("schema" IS "database"), so these objects live in
-- the SAME database with an `ai_` name prefix: ai.utterance -> ai_utterance.
-- Nothing is lost in the privilege model — the Postgres grants for this schema
-- were already per-table (see 07_roles.sql) — and it keeps `./load.sh mydb`
-- parameterizable instead of hardcoding a second database name.
--
-- SCORING. The Postgres resolvers scored on a CONTINUOUS trigram similarity:
--     similarity(lower(c.full_name), phrase.q)
-- which gave "jon smyth" -> "John Smith" a real number around 0.6 and degraded
-- gracefully with the number of wrong characters. MySQL has no similarity() and
-- no trigram support of any kind, so that tier is gone. What replaces it is a
-- ladder of DISCRETE tiers (prefix / substring / soundex / word), which means:
--
--   * A near-miss now either clears a tier or scores nothing. There is no
--     "0.58 confident" any more — the resolver cannot express partial doubt.
--   * SOUNDEX replaces dmetaphone. It keeps the first letter plus three
--     consonant codes, so it collides hard on short names and misses
--     vowel-shifted pairs dmetaphone catches.
--   * Transposition and insertion typos ("wireless mowse" -> "wireless mouse")
--     that trigrams handled well now fall through to SOUNDEX or miss entirely.
--
-- The (score, reason) contract is preserved, so callers that set their own
-- confirmation threshold still work. The scores are just coarser and the misses
-- are more abrupt. If resolution quality matters, do the fuzzy match in the
-- application (rapidfuzz) and use these procedures only for the exact tiers.
--
-- SHAPE. Postgres used RETURNS TABLE + DISTINCT ON + LATERAL. MySQL has no
-- RETURNS TABLE (functions cannot return result sets) and no DISTINCT ON, so
-- each resolver is now a PROCEDURE you CALL, and DISTINCT ON is replaced by
-- ROW_NUMBER() OVER (PARTITION BY id ORDER BY score DESC) = 1. LATERAL exists
-- in MySQL 8.0.14+ but is not needed once the strategies are a plain UNION ALL.
--
-- Procedures cannot have default parameter values in MySQL. Pass NULL for
-- min_score to get the original default.

-- ---------------------------------------------------------------------------
-- 1. ENTITY RESOLUTION
-- ---------------------------------------------------------------------------

-- Spoken alternatives for a row: nicknames, trade names, common ASR manglings.
-- "the blue mouse", "Bobby" -> Robert Chen, "MBP" -> MacBook Pro.
CREATE TABLE ai_entity_alias (
    alias_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
    entity_type  ENUM('customer','product','category','employee','order','status') NOT NULL,
    entity_id    BIGINT NOT NULL,          -- deliberately not a FK: one table, many targets
    -- was citext; the CI server collation gives case-insensitive matching free
    alias        VARCHAR(200) NOT NULL,
    alias_kind   VARCHAR(20) NOT NULL DEFAULT 'nickname',
    confidence   DECIMAL(3,2) NOT NULL DEFAULT 1.00,
    -- Learned aliases (from confirmed corrections) vs. ones a human curated.
    is_learned   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY ai_entity_alias_unique (entity_type, entity_id, alias),
    CONSTRAINT ai_entity_alias_kind_chk CHECK (alias_kind IN
        ('nickname','abbreviation','misspelling','asr_error','trade_name')),
    CONSTRAINT ai_entity_alias_conf_chk CHECK (confidence BETWEEN 0 AND 1)
) ENGINE=InnoDB;

CREATE INDEX ai_entity_alias_lookup   ON ai_entity_alias (entity_type, alias);
-- DELETED: entity_alias_trgm (GIN trigram) — no MySQL equivalent.
-- DEGRADED: dmetaphone -> SOUNDEX.
CREATE INDEX ai_entity_alias_phonetic ON ai_entity_alias (entity_type, (SOUNDEX(alias)));

DELIMITER $$

-- Match a spoken phrase against customers. Best score per customer wins:
--   1.00  curated alias hit
--   0.95  exact (case-insensitive) full name
--   0.90  exact email
--   0.80  name starts with the phrase          <- replaces part of trigram tier
--   0.75  name contains the phrase             <- replaces part of trigram tier
--   0.70  whole name sounds like the phrase
--   0.65  one WORD of the name matches or sounds like it
CREATE PROCEDURE ai_resolve_customer(IN spoken VARCHAR(255), IN min_score DECIMAL(4,2))
READS SQL DATA
BEGIN
    DECLARE q VARCHAR(255);
    SET q = TRIM(LOWER(COALESCE(spoken, '')));
    IF min_score IS NULL THEN SET min_score = 0.35; END IF;

    WITH cand AS (
        SELECT c.customer_id, c.full_name AS nm, CAST(c.email AS CHAR) AS em,
               1.00 AS score, 'alias' AS reason
          FROM customer c
         WHERE q <> '' AND EXISTS (SELECT 1 FROM ai_entity_alias a
                 WHERE a.entity_type = 'customer' AND a.entity_id = c.customer_id
                   AND a.alias = q)
        UNION ALL
        SELECT c.customer_id, c.full_name, CAST(c.email AS CHAR), 0.95, 'exact_name'
          FROM customer c WHERE q <> '' AND LOWER(c.full_name) = q
        UNION ALL
        SELECT c.customer_id, c.full_name, CAST(c.email AS CHAR), 0.90, 'exact_email'
          FROM customer c WHERE q <> '' AND LOWER(c.email) = q
        UNION ALL
        SELECT c.customer_id, c.full_name, CAST(c.email AS CHAR), 0.80, 'prefix'
          FROM customer c WHERE q <> '' AND LOWER(c.full_name) LIKE CONCAT(q, '%')
        UNION ALL
        SELECT c.customer_id, c.full_name, CAST(c.email AS CHAR), 0.75, 'substring'
          FROM customer c WHERE q <> '' AND LOWER(c.full_name) LIKE CONCAT('%', q, '%')
        UNION ALL
        SELECT c.customer_id, c.full_name, CAST(c.email AS CHAR), 0.70, 'sounds_like'
          FROM customer c WHERE q <> '' AND SOUNDEX(c.full_name) = SOUNDEX(q)
        UNION ALL
        -- People say "smyth", not "jon smyth". Compare against the first and last
        -- word of the name, exactly and phonetically. The Postgres original also
        -- compared against every word of every ALIAS; that needed unnest() +
        -- string_to_array(), which MySQL lacks, so alias word-matching is gone.
        SELECT c.customer_id, c.full_name, CAST(c.email AS CHAR), 0.65, 'word_match'
          FROM customer c
         WHERE q <> '' AND CHAR_LENGTH(q) > 2 AND (
                  LOWER(SUBSTRING_INDEX(c.full_name, ' ',  1)) = q
               OR LOWER(SUBSTRING_INDEX(c.full_name, ' ', -1)) = q
               OR SOUNDEX(SUBSTRING_INDEX(c.full_name, ' ',  1)) = SOUNDEX(q)
               OR SOUNDEX(SUBSTRING_INDEX(c.full_name, ' ', -1)) = SOUNDEX(q))
    ),
    ranked AS (
        SELECT customer_id, nm, em, score, reason,
               ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY score DESC) AS rn
          FROM cand
    )
    SELECT customer_id,
           nm     AS customer_name,
           em     AS email,
           score  AS match_score,
           reason AS match_reason
      FROM ranked
     WHERE rn = 1 AND score >= min_score
     ORDER BY score DESC, customer_name
     LIMIT 10;
END$$

-- Same ladder, plus SKU as an exact tier.
CREATE PROCEDURE ai_resolve_product(IN spoken VARCHAR(255), IN min_score DECIMAL(4,2))
READS SQL DATA
BEGIN
    DECLARE q VARCHAR(255);
    SET q = TRIM(LOWER(COALESCE(spoken, '')));
    IF min_score IS NULL THEN SET min_score = 0.30; END IF;

    WITH cand AS (
        SELECT p.product_id, p.name AS nm, p.sku, p.unit_price, p.stock_quantity,
               1.00 AS score, 'alias' AS reason
          FROM product p
         WHERE q <> '' AND EXISTS (SELECT 1 FROM ai_entity_alias a
                 WHERE a.entity_type = 'product' AND a.entity_id = p.product_id
                   AND a.alias = q)
        UNION ALL
        SELECT p.product_id, p.name, p.sku, p.unit_price, p.stock_quantity, 0.98, 'exact_sku'
          FROM product p WHERE q <> '' AND LOWER(p.sku) = q
        UNION ALL
        SELECT p.product_id, p.name, p.sku, p.unit_price, p.stock_quantity, 0.95, 'exact_name'
          FROM product p WHERE q <> '' AND LOWER(p.name) = q
        UNION ALL
        SELECT p.product_id, p.name, p.sku, p.unit_price, p.stock_quantity, 0.80, 'prefix'
          FROM product p WHERE q <> '' AND LOWER(p.name) LIKE CONCAT(q, '%')
        UNION ALL
        SELECT p.product_id, p.name, p.sku, p.unit_price, p.stock_quantity, 0.75, 'substring'
          FROM product p WHERE q <> '' AND LOWER(p.name) LIKE CONCAT('%', q, '%')
        UNION ALL
        -- FULLTEXT stands in for the deleted trigram index. It is word-based, so
        -- it finds "standing desk" inside a description but will NOT survive a
        -- misspelling the way trigrams did.
        --
        -- The score is SCALED BY RELEVANCE rather than flat, and that is not
        -- cosmetic. Measured on the seed data: a real two-word hit scores
        -- 2.74-3.34, while a single common word shared with an unrelated row
        -- ("wireless" also appears in the headset description, "desk" in the
        -- monitor arm's) scores exactly 0.7142. A flat score made those
        -- false positives indistinguishable from real matches and put them above
        -- the default min_score. Scaling keeps them in the result — sometimes a
        -- weak hit is the only hit, e.g. "ergonomic chiar" — but ranks them as
        -- the weak guesses they are. This also restores a CONTINUOUS component
        -- to the scoring, which is the part losing similarity() took away.
        --   relevance 0.71 -> 0.41    (weak, clearly below a real name match)
        --   relevance 2.74 -> 0.71
        --   relevance 3.34 -> 0.80
        SELECT p.product_id, p.name, p.sku, p.unit_price, p.stock_quantity,
               -- ROUND to 2dp: MATCH relevance is a FLOAT, and without this the
               -- score comes back as 0.4071286082267761, which breaks the
               -- (score, reason) contract's shape (Postgres returned numeric).
               ROUND(LEAST(0.90, 0.30 + 0.15 * MATCH(p.search_document)
                                               AGAINST (q IN NATURAL LANGUAGE MODE)), 2),
               'fulltext'
          FROM product p
         WHERE q <> '' AND MATCH(p.search_document) AGAINST (q IN NATURAL LANGUAGE MODE)
        UNION ALL
        SELECT p.product_id, p.name, p.sku, p.unit_price, p.stock_quantity, 0.70, 'sounds_like'
          FROM product p WHERE q <> '' AND SOUNDEX(p.name) = SOUNDEX(q)
        UNION ALL
        SELECT p.product_id, p.name, p.sku, p.unit_price, p.stock_quantity, 0.65, 'word_match'
          FROM product p
         WHERE q <> '' AND CHAR_LENGTH(q) > 2 AND (
                  LOWER(SUBSTRING_INDEX(p.name, ' ',  1)) = q
               OR LOWER(SUBSTRING_INDEX(p.name, ' ', -1)) = q
               -- first-word SOUNDEX matters: 'mackbook' -> M212 -> 'MacBook'.
               -- Comparing against the WHOLE name fails here because
               -- SOUNDEX('MacBook Pro 14') is M21216.
               OR SOUNDEX(SUBSTRING_INDEX(p.name, ' ',  1)) = SOUNDEX(q)
               OR SOUNDEX(SUBSTRING_INDEX(p.name, ' ', -1)) = SOUNDEX(q))
    ),
    ranked AS (
        SELECT product_id, nm, sku, unit_price, stock_quantity, score, reason,
               ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY score DESC) AS rn
          FROM cand
    )
    -- CAST the score: the fulltext branch contributes a FLOAT (MATCH relevance),
    -- which promotes the whole UNION column and makes an exact 1.00 render as
    -- "1.0". The other resolvers return DECIMAL, and callers compare scores
    -- across resolvers, so the contract needs one shape.
    SELECT product_id, nm AS product_name, sku, unit_price, stock_quantity,
           CAST(score AS DECIMAL(4,2)) AS match_score, reason AS match_reason
      FROM ranked
     WHERE rn = 1 AND score >= min_score
     ORDER BY score DESC, product_name
     LIMIT 10;
END$$

CREATE PROCEDURE ai_resolve_employee(IN spoken VARCHAR(255), IN min_score DECIMAL(4,2))
READS SQL DATA
BEGIN
    DECLARE q VARCHAR(255);
    SET q = TRIM(LOWER(COALESCE(spoken, '')));
    IF min_score IS NULL THEN SET min_score = 0.35; END IF;

    WITH cand AS (
        SELECT e.employee_id, e.full_name AS nm, e.job_title,
               1.00 AS score, 'alias' AS reason
          FROM employee e
         WHERE q <> '' AND EXISTS (SELECT 1 FROM ai_entity_alias a
                 WHERE a.entity_type = 'employee' AND a.entity_id = e.employee_id
                   AND a.alias = q)
        UNION ALL
        SELECT e.employee_id, e.full_name, e.job_title, 0.95, 'exact_name'
          FROM employee e WHERE q <> '' AND LOWER(e.full_name) = q
        UNION ALL
        SELECT e.employee_id, e.full_name, e.job_title, 0.90, 'exact_email'
          FROM employee e WHERE q <> '' AND LOWER(e.email) = q
        UNION ALL
        SELECT e.employee_id, e.full_name, e.job_title, 0.80, 'prefix'
          FROM employee e WHERE q <> '' AND LOWER(e.full_name) LIKE CONCAT(q, '%')
        UNION ALL
        SELECT e.employee_id, e.full_name, e.job_title, 0.75, 'substring'
          FROM employee e WHERE q <> '' AND LOWER(e.full_name) LIKE CONCAT('%', q, '%')
        UNION ALL
        SELECT e.employee_id, e.full_name, e.job_title, 0.70, 'sounds_like'
          FROM employee e WHERE q <> '' AND SOUNDEX(e.full_name) = SOUNDEX(q)
        UNION ALL
        SELECT e.employee_id, e.full_name, e.job_title, 0.65, 'word_match'
          FROM employee e
         WHERE q <> '' AND CHAR_LENGTH(q) > 2 AND (
                  LOWER(SUBSTRING_INDEX(e.full_name, ' ',  1)) = q
               OR LOWER(SUBSTRING_INDEX(e.full_name, ' ', -1)) = q
               OR SOUNDEX(SUBSTRING_INDEX(e.full_name, ' ',  1)) = SOUNDEX(q)
               OR SOUNDEX(SUBSTRING_INDEX(e.full_name, ' ', -1)) = SOUNDEX(q))
    ),
    ranked AS (
        SELECT employee_id, nm, job_title, score, reason,
               ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY score DESC) AS rn
          FROM cand
    )
    SELECT employee_id, nm AS employee_name, job_title,
           score AS match_score, reason AS match_reason
      FROM ranked
     WHERE rn = 1 AND score >= min_score
     ORDER BY score DESC, employee_name
     LIMIT 10;
END$$

-- "order A dash ten oh three" / "a1003" / "1003" all land on A-1003.
-- This one ports almost exactly: MySQL 8 has REGEXP_REPLACE, and the squashed
-- functional index from 03_indexes.sql serves it.
CREATE PROCEDURE ai_resolve_order(IN spoken VARCHAR(255))
READS SQL DATA
BEGIN
    DECLARE q VARCHAR(255);
    SET q = UPPER(REGEXP_REPLACE(COALESCE(spoken, ''), '[^A-Za-z0-9]', ''));

    SELECT v.order_id, v.order_number, v.customer_name, v.status, v.ordered_at, v.grand_total
      FROM v_order_summary v
     WHERE q <> ''
       AND (UPPER(REPLACE(v.order_number, '-', '')) = q
         OR UPPER(REPLACE(v.order_number, '-', '')) = CONCAT('A', q))
     ORDER BY v.ordered_at DESC
     LIMIT 5;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------------
-- 2. CONVERSATION STATE
-- ---------------------------------------------------------------------------

-- What the assistant is allowed to be asked, and what it needs to know to answer.
-- Doubles as the few-shot source for the NL->SQL prompt.
-- text[] -> JSON: MySQL has no array type.
CREATE TABLE ai_intent (
    intent_name       VARCHAR(100) PRIMARY KEY,
    description       VARCHAR(500) NOT NULL,
    sample_utterances JSON NOT NULL DEFAULT (JSON_ARRAY()),
    required_slots    JSON NOT NULL DEFAULT (JSON_ARRAY()),
    -- A hand-written, known-good query. The model is far more reliable picking
    -- and parameterising one of these than authoring SQL from scratch.
    sql_template      TEXT,
    is_write          BOOLEAN NOT NULL DEFAULT FALSE,
    is_enabled        BOOLEAN NOT NULL DEFAULT TRUE
) ENGINE=InnoDB;

-- uuid -> CHAR(36) with DEFAULT (UUID()); jsonb -> JSON.
CREATE TABLE ai_voice_session (
    session_id   CHAR(36) NOT NULL DEFAULT (UUID()) PRIMARY KEY,
    channel      ENUM('alexa','google_assistant','phone','web_chat','sms') NOT NULL DEFAULT 'alexa',
    device_id    VARCHAR(100),
    -- Who is talking: a staff member (full access) or a customer (own data only).
    employee_id  BIGINT,
    customer_id  BIGINT,
    locale       VARCHAR(16) NOT NULL DEFAULT 'en-US',
    started_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at     DATETIME,
    -- Anaphora resolution: "and when did IT ship?" needs the last entity mentioned.
    context      JSON NOT NULL DEFAULT (JSON_OBJECT()),
    CONSTRAINT ai_voice_session_employee_fk FOREIGN KEY (employee_id)
        REFERENCES employee(employee_id) ON DELETE SET NULL,
    CONSTRAINT ai_voice_session_customer_fk FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id) ON DELETE SET NULL
    -- The Postgres CHECK voice_session_has_a_speaker lived here. MySQL refuses a
    -- CHECK on a column that carries a referential action (ERROR 3823), and it
    -- is right to: both FKs are ON DELETE SET NULL, so deleting the one employee
    -- a session names would null the column and violate the CHECK at DELETE
    -- time. Postgres accepts the declaration and then fails that delete.
    -- Enforced as BEFORE INSERT/UPDATE triggers below instead, which guards the
    -- write path (where a missing speaker is a bug) without making a later
    -- SET NULL retroactively illegal.
) ENGINE=InnoDB;

DELIMITER $$

CREATE TRIGGER ai_voice_session_speaker_insert
BEFORE INSERT ON ai_voice_session
FOR EACH ROW
BEGIN
    IF NEW.employee_id IS NULL AND NEW.customer_id IS NULL AND NEW.device_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ai_voice_session_has_a_speaker: need an employee_id, customer_id or device_id';
    END IF;
END$$

CREATE TRIGGER ai_voice_session_speaker_update
BEFORE UPDATE ON ai_voice_session
FOR EACH ROW
BEGIN
    -- Only block a write that CLEARS the last speaker. A cascade from
    -- ON DELETE SET NULL is a different statement and is deliberately allowed.
    IF NEW.employee_id IS NULL AND NEW.customer_id IS NULL AND NEW.device_id IS NULL
       AND (OLD.employee_id IS NOT NULL OR OLD.customer_id IS NOT NULL OR OLD.device_id IS NOT NULL) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'ai_voice_session_has_a_speaker: cannot clear the last speaker';
    END IF;
END$$

DELIMITER ;

CREATE INDEX ai_voice_session_started_idx ON ai_voice_session (started_at DESC);

-- One row per spoken turn. This is the training/debugging record: what was heard,
-- what SQL it became, whether that worked, and how long the user waited.
CREATE TABLE ai_utterance (
    utterance_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    session_id        CHAR(36) NOT NULL,
    turn_no           INT NOT NULL,
    spoken_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    transcript        VARCHAR(1000) NOT NULL,
    asr_confidence    DECIMAL(3,2),
    intent_name       VARCHAR(100),
    intent_confidence DECIMAL(3,2),
    slots             JSON NOT NULL DEFAULT (JSON_OBJECT()),  -- {"customer":"john smith"}
    resolved_entities JSON NOT NULL DEFAULT (JSON_OBJECT()),  -- {"customer_id":4}
    generated_sql     TEXT,
    sql_status        ENUM('ok','no_rows','rejected','error','timeout'),
    row_count         INT,
    response_text     VARCHAR(2000),                          -- what was spoken back
    latency_ms        INT,
    error_message     VARCHAR(1000),
    -- Thumbs up/down or an explicit "no, I meant..." correction.
    was_helpful       BOOLEAN,
    correction_text   VARCHAR(1000),
    UNIQUE KEY ai_utterance_session_turn (session_id, turn_no),
    CONSTRAINT ai_utterance_session_fk FOREIGN KEY (session_id)
        REFERENCES ai_voice_session(session_id) ON DELETE CASCADE,
    CONSTRAINT ai_utterance_intent_fk FOREIGN KEY (intent_name)
        REFERENCES ai_intent(intent_name) ON DELETE SET NULL,
    CONSTRAINT ai_utterance_asr_chk     CHECK (asr_confidence    BETWEEN 0 AND 1),
    CONSTRAINT ai_utterance_intent_chk  CHECK (intent_confidence BETWEEN 0 AND 1),
    CONSTRAINT ai_utterance_latency_chk CHECK (latency_ms >= 0)
) ENGINE=InnoDB;

CREATE INDEX ai_utterance_intent_idx ON ai_utterance (intent_name, spoken_at DESC);
-- The Postgres original was partial:
--   ... WHERE sql_status IN ('error','rejected','timeout') OR was_helpful IS false
-- MySQL has no partial indexes, so this now covers every turn, not just failures.
CREATE INDEX ai_utterance_failures_idx ON ai_utterance (spoken_at DESC);

-- What is going wrong, most-common first. Feed this back into aliases/intents.
CREATE VIEW ai_v_failure_review AS
SELECT
    u.intent_name,
    u.sql_status,
    COUNT(*)          AS occurrences,
    MAX(u.spoken_at)  AS last_seen,
    -- Replaces Postgres (array_agg(... ORDER BY ...))[1:5]. MySQL has no arrays
    -- and JSON_ARRAYAGG cannot be ordered, so: ordered GROUP_CONCAT, then take
    -- the first 5 fields. Capped by group_concat_max_len (1024 by default), so
    -- raise that session variable if transcripts are long.
    SUBSTRING_INDEX(
        GROUP_CONCAT(u.transcript ORDER BY u.spoken_at DESC SEPARATOR ' ~ '),
        ' ~ ', 5)                                     AS recent_transcripts,
    CAST(AVG(u.asr_confidence) AS DECIMAL(3,2))       AS avg_asr_confidence
FROM ai_utterance u
WHERE NOT (u.sql_status <=> 'ok') OR u.was_helpful = FALSE
GROUP BY u.intent_name, u.sql_status
ORDER BY occurrences DESC;

-- ---------------------------------------------------------------------------
-- Documentation for objects MySQL cannot carry a comment on.
--
-- MySQL has NO way to comment a view: ALTER TABLE v COMMENT fails with
-- "not BASE TABLE", there is no ALTER VIEW ... COMMENT, and
-- information_schema.TABLES.TABLE_COMMENT for a view is the literal string
-- 'VIEW'. Tables, columns and routines are fine (ALTER TABLE ... COMMENT,
-- MODIFY COLUMN ... COMMENT, ALTER PROCEDURE ... COMMENT) — views are the gap.
--
-- Those view comments are the highest-value text in 06_comments.sql: they are
-- what tells the model "v_customer_360 already excludes refunded orders" and
-- "the P&L bottom line is gross profit, not net income". Losing them silently
-- would be the worst outcome of this whole port, so they are stored here and
-- joined back in by ai_schema_context below.
--
-- Populated by 06_comments.sql, alongside the real COMMENTs.
-- ---------------------------------------------------------------------------
CREATE TABLE ai_object_doc (
    object_name  VARCHAR(128) NOT NULL,
    object_type  ENUM('view','procedure','function','schema') NOT NULL,
    purpose      VARCHAR(2000) NOT NULL,
    PRIMARY KEY (object_name, object_type)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------------
-- 3. SELF-DESCRIPTION
--
-- THIS SURVIVED THE PORT INTACT, which matters: it is the mechanism by which
-- documenting a column is the same act as teaching the assistant about it.
-- Postgres read obj_description()/col_description(); MySQL exposes the same
-- information as TABLES.TABLE_COMMENT and COLUMNS.COLUMN_COMMENT. Keep
-- 06_comments.sql current and the model's prompt stays current.
-- ---------------------------------------------------------------------------
CREATE VIEW ai_schema_context AS
SELECT
    c.TABLE_SCHEMA                  AS schema_name,
    c.TABLE_NAME                    AS table_name,
    -- For a base table this is the real COMMENT. For a VIEW, TABLE_COMMENT is
    -- always the useless literal 'VIEW', so fall back to ai_object_doc.
    COALESCE(d.purpose, NULLIF(t.TABLE_COMMENT, ''), NULL) AS table_purpose,
    c.ORDINAL_POSITION              AS ordinal_position,
    c.COLUMN_NAME                   AS column_name,
    c.COLUMN_TYPE                   AS data_type,
    (c.IS_NULLABLE = 'YES')         AS is_nullable,
    NULLIF(c.COLUMN_COMMENT, '')    AS column_meaning
FROM information_schema.COLUMNS c
JOIN information_schema.TABLES t
     ON t.TABLE_SCHEMA = c.TABLE_SCHEMA AND t.TABLE_NAME = c.TABLE_NAME
LEFT JOIN ai_object_doc d
     ON d.object_name = c.TABLE_NAME AND d.object_type = 'view'
WHERE c.TABLE_SCHEMA = DATABASE()
ORDER BY c.TABLE_NAME, c.ORDINAL_POSITION;

-- The closed vocabularies, so the model maps spoken words to legal values
-- instead of guessing at string literals.
--
-- Postgres could just read pg_enum, because its enums are named types. MySQL
-- enums are inline column definitions, so the only record of the vocabulary is
-- the COLUMN_TYPE string "enum('pending','paid',...)". This recursive CTE
-- splits it back apart. Consequence of the inline-enum port: the "enum name" is
-- now table.column rather than a type name, and the SAME vocabulary appears
-- more than once (order.status, ai_utterance.old_status, ...).
--
-- Caveat: splits on commas, so an enum label containing a comma would break it.
-- None of ours do.
CREATE VIEW ai_enum_values AS
WITH RECURSIVE raw AS (
    SELECT CONCAT(TABLE_NAME, '.', COLUMN_NAME) AS enum_name,
           SUBSTRING(COLUMN_TYPE, 6, CHAR_LENGTH(COLUMN_TYPE) - 6) AS vals
      FROM information_schema.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND DATA_TYPE = 'enum'
),
split AS (
    SELECT enum_name,
           1 AS sort_order,
           TRIM(BOTH '''' FROM SUBSTRING_INDEX(vals, ',', 1)) AS allowed_value,
           CASE WHEN LOCATE(',', vals) > 0
                THEN SUBSTRING(vals, LOCATE(',', vals) + 1) END AS rest
      FROM raw
    UNION ALL
    SELECT enum_name,
           sort_order + 1,
           TRIM(BOTH '''' FROM SUBSTRING_INDEX(rest, ',', 1)),
           CASE WHEN LOCATE(',', rest) > 0
                THEN SUBSTRING(rest, LOCATE(',', rest) + 1) END
      FROM split
     WHERE rest IS NOT NULL
)
SELECT enum_name, allowed_value, sort_order
  FROM split
 ORDER BY enum_name, sort_order;

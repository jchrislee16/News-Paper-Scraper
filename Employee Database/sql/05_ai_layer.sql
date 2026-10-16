-- 05_ai_layer.sql — everything that exists because of the voice assistant.
--
-- Kept in its own `ai` schema so the business tables stay clean and so the
-- assistant's write grants can be scoped to exactly this schema.
--
-- Three jobs live here:
--   1. ENTITY RESOLUTION  — turn a messy spoken phrase into a primary key.
--   2. CONVERSATION STATE — remember the session so "and his last order?" works.
--   3. SELF-DESCRIPTION   — hand the model an accurate schema prompt at runtime.

CREATE SCHEMA ai;

CREATE TYPE ai.channel AS ENUM ('alexa', 'google_assistant', 'phone', 'web_chat', 'sms');
CREATE TYPE ai.sql_status AS ENUM ('ok', 'no_rows', 'rejected', 'error', 'timeout');
CREATE TYPE ai.entity_kind AS ENUM ('customer', 'product', 'category', 'employee', 'order', 'status');

-- ---------------------------------------------------------------------------
-- 1. ENTITY RESOLUTION
-- ---------------------------------------------------------------------------

-- Spoken alternatives for a row: nicknames, trade names, common ASR manglings.
-- "the blue mouse", "Bobby" -> Robert Chen, "MBP" -> MacBook Pro.
CREATE TABLE ai.entity_alias (
    alias_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    entity_type  ai.entity_kind NOT NULL,
    entity_id    bigint NOT NULL,          -- deliberately not a FK: one table, many targets
    alias        citext NOT NULL,
    alias_kind   text NOT NULL DEFAULT 'nickname'
                 CHECK (alias_kind IN ('nickname','abbreviation','misspelling','asr_error','trade_name')),
    confidence   numeric(3,2) NOT NULL DEFAULT 1.00 CHECK (confidence BETWEEN 0 AND 1),
    -- Learned aliases (from confirmed corrections) vs. ones a human curated.
    is_learned   boolean NOT NULL DEFAULT false,
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (entity_type, entity_id, alias)
);

CREATE INDEX entity_alias_lookup ON ai.entity_alias (entity_type, alias);
CREATE INDEX entity_alias_trgm   ON ai.entity_alias USING gin ((alias::text) gin_trgm_ops);
CREATE INDEX entity_alias_phonetic ON ai.entity_alias (entity_type, dmetaphone(alias::text));

-- Match a spoken phrase against customers. Four strategies, best score wins:
--   1.00  curated alias hit
--   0.95  exact (case-insensitive) full name
--   ~sim  trigram similarity  ("jon smyth" -> "John Smith")
--   0.70  phonetic equality when trigrams fail entirely
CREATE OR REPLACE FUNCTION ai.resolve_customer(spoken text, min_score numeric DEFAULT 0.35)
RETURNS TABLE (customer_id bigint, customer_name text, email text,
               match_score numeric, match_reason text)
LANGUAGE sql STABLE AS $$
    WITH phrase AS (SELECT btrim(lower(spoken)) AS q)
    SELECT * FROM (
        SELECT DISTINCT ON (c.customer_id)
               c.customer_id,
               c.full_name,
               c.email::text,
               s.score,
               s.reason
        FROM customer c
        CROSS JOIN phrase
        JOIN LATERAL (
            SELECT 1.00::numeric AS score, 'alias' AS reason
            WHERE EXISTS (
                SELECT 1 FROM ai.entity_alias a
                WHERE a.entity_type = 'customer' AND a.entity_id = c.customer_id
                  AND a.alias = phrase.q
            )
            UNION ALL
            SELECT 0.95, 'exact_name'  WHERE lower(c.full_name) = phrase.q
            UNION ALL
            SELECT 0.90, 'exact_email' WHERE lower(c.email::text) = phrase.q
            UNION ALL
            SELECT similarity(lower(c.full_name), phrase.q)::numeric, 'fuzzy_name'
            UNION ALL
            -- One word out of a multi-word name or alias: people say "mowse", not
            -- "wireless mowse", and "smyth", not "jon smyth". Compare the phrase
            -- against every individual word of the name AND of its aliases.
            SELECT coalesce((
                SELECT max(similarity(w.word, phrase.q))
                FROM (
                    SELECT unnest(string_to_array(lower(c.full_name), ' ')) AS word
                    UNION ALL
                    SELECT unnest(string_to_array(lower(a.alias::text), ' '))
                    FROM ai.entity_alias a
                    WHERE a.entity_type = 'customer' AND a.entity_id = c.customer_id
                ) w
                WHERE length(w.word) > 2
            ), 0)::numeric * 0.90, 'word_match'
            UNION ALL
            SELECT 0.70, 'sounds_like'
            WHERE dmetaphone(c.full_name) = dmetaphone(phrase.q)
              AND dmetaphone(phrase.q) <> ''
        ) s ON true
        ORDER BY c.customer_id, s.score DESC
    ) ranked(customer_id, customer_name, email, match_score, match_reason)
    WHERE match_score >= min_score
    ORDER BY match_score DESC, customer_name
    LIMIT 10;
$$;

CREATE OR REPLACE FUNCTION ai.resolve_product(spoken text, min_score numeric DEFAULT 0.30)
RETURNS TABLE (product_id bigint, product_name text, sku text, unit_price numeric,
               stock_quantity integer, match_score numeric, match_reason text)
LANGUAGE sql STABLE AS $$
    WITH phrase AS (SELECT btrim(lower(spoken)) AS q)
    SELECT * FROM (
        SELECT DISTINCT ON (p.product_id)
               p.product_id, p.name, p.sku, p.unit_price, p.stock_quantity, s.score, s.reason
        FROM product p
        CROSS JOIN phrase
        JOIN LATERAL (
            SELECT 1.00::numeric AS score, 'alias' AS reason
            WHERE EXISTS (
                SELECT 1 FROM ai.entity_alias a
                WHERE a.entity_type = 'product' AND a.entity_id = p.product_id
                  AND a.alias = phrase.q
            )
            UNION ALL
            SELECT 0.98, 'exact_sku'  WHERE lower(p.sku) = phrase.q
            UNION ALL
            SELECT 0.95, 'exact_name' WHERE lower(p.name) = phrase.q
            UNION ALL
            SELECT similarity(lower(p.name), phrase.q)::numeric, 'fuzzy_name'
            UNION ALL
            -- One word out of a multi-word name or alias: people say "mowse", not
            -- "wireless mowse", and "smyth", not "jon smyth". Compare the phrase
            -- against every individual word of the name AND of its aliases.
            SELECT coalesce((
                SELECT max(similarity(w.word, phrase.q))
                FROM (
                    SELECT unnest(string_to_array(lower(p.name), ' ')) AS word
                    UNION ALL
                    SELECT unnest(string_to_array(lower(a.alias::text), ' '))
                    FROM ai.entity_alias a
                    WHERE a.entity_type = 'product' AND a.entity_id = p.product_id
                ) w
                WHERE length(w.word) > 2
            ), 0)::numeric * 0.90, 'word_match'
            UNION ALL
            -- "something for taking notes" won't trigram-match any title
            SELECT 0.60, 'full_text'
            WHERE p.search_document @@ plainto_tsquery('english', phrase.q)
              AND phrase.q <> ''
            UNION ALL
            SELECT 0.55, 'sounds_like'
            WHERE dmetaphone(p.name) = dmetaphone(phrase.q) AND dmetaphone(phrase.q) <> ''
        ) s ON true
        ORDER BY p.product_id, s.score DESC
    ) ranked(product_id, product_name, sku, unit_price, stock_quantity, match_score, match_reason)
    WHERE match_score >= min_score
    ORDER BY match_score DESC, product_name
    LIMIT 10;
$$;

CREATE OR REPLACE FUNCTION ai.resolve_employee(spoken text, min_score numeric DEFAULT 0.35)
RETURNS TABLE (employee_id bigint, employee_name text, job_title text,
               match_score numeric, match_reason text)
LANGUAGE sql STABLE AS $$
    WITH phrase AS (SELECT btrim(lower(spoken)) AS q)
    SELECT * FROM (
        SELECT DISTINCT ON (e.employee_id)
               e.employee_id, e.full_name, e.job_title, s.score, s.reason
        FROM employee e
        CROSS JOIN phrase
        JOIN LATERAL (
            SELECT 1.00::numeric AS score, 'alias' AS reason
            WHERE EXISTS (
                SELECT 1 FROM ai.entity_alias a
                WHERE a.entity_type = 'employee' AND a.entity_id = e.employee_id
                  AND a.alias = phrase.q
            )
            UNION ALL
            SELECT 0.95, 'exact_name' WHERE lower(e.full_name) = phrase.q
            UNION ALL
            SELECT similarity(lower(e.full_name), phrase.q)::numeric, 'fuzzy_name'
            UNION ALL
            -- One word out of a multi-word name or alias: people say "mowse", not
            -- "wireless mowse", and "smyth", not "jon smyth". Compare the phrase
            -- against every individual word of the name AND of its aliases.
            SELECT coalesce((
                SELECT max(similarity(w.word, phrase.q))
                FROM (
                    SELECT unnest(string_to_array(lower(e.full_name), ' ')) AS word
                    UNION ALL
                    SELECT unnest(string_to_array(lower(a.alias::text), ' '))
                    FROM ai.entity_alias a
                    WHERE a.entity_type = 'employee' AND a.entity_id = e.employee_id
                ) w
                WHERE length(w.word) > 2
            ), 0)::numeric * 0.90, 'word_match'
            UNION ALL
            SELECT 0.70, 'sounds_like'
            WHERE dmetaphone(e.full_name) = dmetaphone(phrase.q) AND dmetaphone(phrase.q) <> ''
        ) s ON true
        ORDER BY e.employee_id, s.score DESC
    ) ranked(employee_id, employee_name, job_title, match_score, match_reason)
    WHERE match_score >= min_score
    ORDER BY match_score DESC, employee_name
    LIMIT 10;
$$;

-- "order A dash ten oh three" / "a1003" / "1003" all land on A-1003.
CREATE OR REPLACE FUNCTION ai.resolve_order(spoken text)
RETURNS TABLE (order_id bigint, order_number text, customer_name text,
               status order_status, ordered_at timestamptz, grand_total numeric)
LANGUAGE sql STABLE AS $$
    WITH squashed AS (
        SELECT upper(regexp_replace(coalesce(spoken,''), '[^A-Za-z0-9]', '', 'g')) AS q
    )
    SELECT v.order_id, v.order_number, v.customer_name, v.status, v.ordered_at, v.grand_total
    FROM v_order_summary v, squashed
    WHERE upper(replace(v.order_number, '-', '')) = squashed.q
       OR upper(replace(v.order_number, '-', '')) = 'A' || squashed.q
    ORDER BY v.ordered_at DESC
    LIMIT 5;
$$;

-- ---------------------------------------------------------------------------
-- 2. CONVERSATION STATE
-- ---------------------------------------------------------------------------

-- What the assistant is allowed to be asked, and what it needs to know to answer.
-- Doubles as the few-shot source for the NL->SQL prompt.
CREATE TABLE ai.intent (
    intent_name       text PRIMARY KEY,
    description       text NOT NULL,
    sample_utterances text[] NOT NULL DEFAULT '{}',
    required_slots    text[] NOT NULL DEFAULT '{}',
    -- A hand-written, known-good query. The model is far more reliable picking
    -- and parameterising one of these than authoring SQL from scratch.
    sql_template      text,
    is_write          boolean NOT NULL DEFAULT false,
    is_enabled        boolean NOT NULL DEFAULT true
);

CREATE TABLE ai.voice_session (
    session_id   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    channel      ai.channel NOT NULL DEFAULT 'alexa',
    device_id    text,
    -- Who is talking: a staff member (full access) or a customer (own data only).
    employee_id  bigint REFERENCES employee(employee_id) ON DELETE SET NULL,
    customer_id  bigint REFERENCES customer(customer_id) ON DELETE SET NULL,
    locale       text NOT NULL DEFAULT 'en-US',
    started_at   timestamptz NOT NULL DEFAULT now(),
    ended_at     timestamptz,
    -- Anaphora resolution: "and when did IT ship?" needs the last entity mentioned.
    context      jsonb NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT voice_session_has_a_speaker
        CHECK (employee_id IS NOT NULL OR customer_id IS NOT NULL OR device_id IS NOT NULL)
);

CREATE INDEX voice_session_started_idx ON ai.voice_session (started_at DESC);

-- One row per spoken turn. This is the training/debugging record: what was heard,
-- what SQL it became, whether that worked, and how long the user waited.
CREATE TABLE ai.utterance (
    utterance_id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session_id       uuid NOT NULL REFERENCES ai.voice_session(session_id) ON DELETE CASCADE,
    turn_no          integer NOT NULL,
    spoken_at        timestamptz NOT NULL DEFAULT now(),
    transcript       text NOT NULL,
    asr_confidence   numeric(3,2) CHECK (asr_confidence BETWEEN 0 AND 1),
    intent_name      text REFERENCES ai.intent(intent_name) ON DELETE SET NULL,
    intent_confidence numeric(3,2) CHECK (intent_confidence BETWEEN 0 AND 1),
    slots            jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {"customer":"john smith","period":"last month"}
    resolved_entities jsonb NOT NULL DEFAULT '{}'::jsonb,  -- {"customer_id":4} after ai.resolve_*
    generated_sql    text,
    sql_status       ai.sql_status,
    row_count        integer,
    response_text    text,                                  -- what was actually spoken back
    latency_ms       integer CHECK (latency_ms >= 0),
    error_message    text,
    -- Thumbs up/down or an explicit "no, I meant..." correction.
    was_helpful      boolean,
    correction_text  text,
    UNIQUE (session_id, turn_no)
);

CREATE INDEX utterance_session_idx ON ai.utterance (session_id, turn_no);
CREATE INDEX utterance_intent_idx  ON ai.utterance (intent_name, spoken_at DESC);
CREATE INDEX utterance_failures_idx ON ai.utterance (spoken_at DESC)
    WHERE sql_status IN ('error', 'rejected', 'timeout') OR was_helpful IS false;

-- What is going wrong, most-common first. Feed this back into aliases/intents.
CREATE VIEW ai.v_failure_review AS
SELECT
    u.intent_name,
    u.sql_status,
    count(*)                  AS occurrences,
    max(u.spoken_at)          AS last_seen,
    (array_agg(u.transcript ORDER BY u.spoken_at DESC))[1:5] AS recent_transcripts,
    avg(u.asr_confidence)::numeric(3,2) AS avg_asr_confidence
FROM ai.utterance u
WHERE u.sql_status IS DISTINCT FROM 'ok' OR u.was_helpful IS false
GROUP BY u.intent_name, u.sql_status
ORDER BY occurrences DESC;

-- ---------------------------------------------------------------------------
-- 3. SELF-DESCRIPTION
-- ---------------------------------------------------------------------------

-- The schema prompt, generated from the live catalogue instead of a stale
-- hand-maintained string. SELECT * FROM ai.schema_context -> drop into the system
-- prompt. Because it reads COMMENT ON metadata (06_comments.sql), documenting a
-- column is the same act as teaching the assistant about it.
CREATE VIEW ai.schema_context AS
SELECT
    c.table_schema  AS schema_name,
    c.table_name,
    obj_description(format('%I.%I', c.table_schema, c.table_name)::regclass, 'pg_class')
                    AS table_purpose,
    c.ordinal_position,
    c.column_name,
    c.data_type,
    c.is_nullable = 'YES' AS is_nullable,
    col_description(format('%I.%I', c.table_schema, c.table_name)::regclass, c.ordinal_position)
                    AS column_meaning
FROM information_schema.columns c
JOIN information_schema.tables t
     ON t.table_schema = c.table_schema AND t.table_name = c.table_name
WHERE c.table_schema IN ('public', 'ai')
ORDER BY c.table_schema, c.table_name, c.ordinal_position;

-- The closed vocabularies, so the model maps spoken words to legal values
-- instead of guessing at string literals.
CREATE VIEW ai.enum_values AS
SELECT t.typname AS enum_name, e.enumlabel AS allowed_value, e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON e.enumtypid = t.oid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname IN ('public', 'ai')
ORDER BY t.typname, e.enumsortorder;

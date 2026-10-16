-- 07_roles.sql — least privilege for a component that writes its own queries.
--
-- The assistant generates SQL from natural language, so the database, not the
-- prompt, is where destructive statements get stopped. `ai_assistant` can read
-- business data and append to its own logs. It cannot write a single business row.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ai_assistant') THEN
        CREATE ROLE ai_assistant NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_service') THEN
        CREATE ROLE app_service NOLOGIN;
    END IF;
END
$$;

-- --- ai_assistant: read business data, write only its own transcript ---------
GRANT USAGE ON SCHEMA public, ai TO ai_assistant;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO ai_assistant;
GRANT SELECT ON ai.entity_alias, ai.intent, ai.schema_context, ai.enum_values,
                ai.v_failure_review TO ai_assistant;

-- Conversation logging is the only write it gets. No DELETE anywhere, ever.
-- SELECT is part of this on purpose: the assistant reads voice_session.context back
-- to resolve follow-ups ("and his last order?"), and INSERT ... RETURNING needs it.
GRANT SELECT, INSERT, UPDATE ON ai.voice_session, ai.utterance TO ai_assistant;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA ai TO ai_assistant;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ai TO ai_assistant;

-- Runaway generated query -> killed, not a stalled Alexa response.
ALTER ROLE ai_assistant SET statement_timeout = '5s';
ALTER ROLE ai_assistant SET idle_in_transaction_session_timeout = '10s';

-- Note: the guard is the GRANT list above, not a read-only default. The assistant
-- must stay able to INSERT its own transcript without ceremony on every turn.

-- New objects stay readable without re-running grants.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO ai_assistant;

-- --- app_service: the ordinary application ----------------------------------
GRANT USAGE ON SCHEMA public, ai TO app_service;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO app_service;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA ai TO app_service;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public, ai TO app_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA ai TO app_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO app_service;

-- Login users are created per environment, e.g.:
--   CREATE USER alexa_bot LOGIN PASSWORD '...'; GRANT ai_assistant TO alexa_bot;
--   CREATE USER api LOGIN PASSWORD '...';       GRANT app_service  TO api;

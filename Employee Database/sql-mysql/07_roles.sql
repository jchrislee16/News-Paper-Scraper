-- 07_roles.sql — MySQL port. Least privilege for a component that writes its
-- own queries.
--
-- The assistant generates SQL from natural language, so the database, not the
-- prompt, is where destructive statements get stopped. `ai_assistant` can read
-- business data and append to its own logs. It cannot write a single business row.
--
-- PORTING NOTES:
--
--   DO $$ IF NOT EXISTS ... CREATE ROLE $$   -> CREATE ROLE IF NOT EXISTS
--   CREATE ROLE ... NOLOGIN                  -> plain CREATE ROLE. A MySQL role
--                                               is a locked account by default,
--                                               so NOLOGIN is the default.
--   GRANT ... ON ALL TABLES IN SCHEMA public -> GRANT ... ON `db`.*
--   ALTER DEFAULT PRIVILEGES ...             -> DELETED, not needed. A MySQL
--                                               database-level grant already
--                                               covers tables created later,
--                                               which is what the Postgres
--                                               default-privileges line was for.
--   GRANT USAGE, SELECT ON ALL SEQUENCES     -> DELETED. No sequences in MySQL;
--                                               AUTO_INCREMENT needs no grant.
--
-- *** TWO GUARDS GOT WEAKER. THIS IS THE REAL COST OF THIS FILE. ***
--
--   ALTER ROLE ai_assistant SET statement_timeout = '5s'
--       MySQL has max_execution_time, but (a) it only aborts SELECTs, not
--       writes or DDL, and (b) it cannot be attached to a user or role — only
--       set globally or per session. So a runaway generated query is no longer
--       stopped by the database for this role. The application MUST set it on
--       every connection:
--           SET SESSION max_execution_time = 5000;   -- milliseconds
--       web/app.py does this. If you add another client, it must too.
--
--   ALTER ROLE ai_assistant SET idle_in_transaction_session_timeout = '10s'
--       NO EQUIVALENT AT ALL. MySQL's wait_timeout closes idle CONNECTIONS, not
--       connections idling inside an open transaction, so a generated statement
--       that opens a transaction and stalls will hold its locks until the
--       connection dies. Keep autocommit on for the assistant's connection.

CREATE ROLE IF NOT EXISTS ai_assistant;
CREATE ROLE IF NOT EXISTS app_service;

-- MySQL GRANT needs a literal database name, but load-mysql.sh can target any
-- database. This helper substitutes the current one so the file stays
-- parameterizable instead of hardcoding `employee_db`. Inside a stored
-- procedure DATABASE() is the procedure's own database, which is the target.
DELIMITER $$
CREATE PROCEDURE grant_here(IN tmpl TEXT)
BEGIN
    SET @sql_text = REPLACE(tmpl, '{db}', DATABASE());
    PREPARE st FROM @sql_text;
    EXECUTE st;
    DEALLOCATE PREPARE st;
END$$
DELIMITER ;

-- --- ai_assistant: read business data, write only its own transcript ---------
CALL grant_here('GRANT SELECT ON `{db}`.* TO ai_assistant');

-- Conversation logging is the only write it gets. No DELETE anywhere, ever.
-- SELECT is part of this on purpose: the assistant reads ai_voice_session.context
-- back to resolve follow-ups ("and his last order?").
CALL grant_here('GRANT INSERT, UPDATE ON `{db}`.ai_voice_session TO ai_assistant');
CALL grant_here('GRANT INSERT, UPDATE ON `{db}`.ai_utterance     TO ai_assistant');

-- The resolvers and the P&L are procedures now, so EXECUTE is required to reach
-- them at all — in Postgres they were functions called inside a SELECT.
CALL grant_here('GRANT EXECUTE ON `{db}`.* TO ai_assistant');

-- Note: the guard is the GRANT list above, not a read-only default. The assistant
-- must stay able to INSERT its own transcript without ceremony on every turn.

-- --- app_service: the ordinary application ----------------------------------
CALL grant_here('GRANT SELECT, INSERT, UPDATE ON `{db}`.* TO app_service');
CALL grant_here('GRANT EXECUTE ON `{db}`.* TO app_service');

DROP PROCEDURE grant_here;

-- Login users are created per environment, e.g.:
--   CREATE USER 'alexa_bot'@'localhost' IDENTIFIED BY '...';
--   GRANT ai_assistant TO 'alexa_bot'@'localhost';
--   SET DEFAULT ROLE ai_assistant TO 'alexa_bot'@'localhost';
--
--   CREATE USER 'api'@'localhost' IDENTIFIED BY '...';
--   GRANT app_service TO 'api'@'localhost';
--   SET DEFAULT ROLE app_service TO 'api'@'localhost';
--
-- SET DEFAULT ROLE has no Postgres counterpart and is easy to forget: without
-- it a MySQL user holds the role but has none of its privileges active on
-- connect, and every query fails with a permission error.

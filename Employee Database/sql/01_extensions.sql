-- 01_extensions.sql — extensions the voice/NL layer depends on.
-- All are core contrib modules; no third-party installs.

CREATE EXTENSION IF NOT EXISTS citext;        -- case-insensitive email / alias text
CREATE EXTENSION IF NOT EXISTS pg_trgm;       -- trigram similarity: fuzzy name matching for ASR typos
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch; -- soundex / dmetaphone: "sounds like" matching for speech
CREATE EXTENSION IF NOT EXISTS unaccent;      -- strip diacritics before matching

-- Status vocabularies. ENUMs (not free text) so the NL->SQL layer has a closed,
-- discoverable set of values to map spoken words onto.
CREATE TYPE order_status AS ENUM (
    'pending', 'paid', 'packed', 'shipped', 'delivered', 'cancelled', 'refunded'
);

CREATE TYPE payment_method AS ENUM (
    'card', 'paypal', 'bank_transfer', 'cash_on_delivery', 'store_credit'
);

CREATE TYPE address_type AS ENUM ('billing', 'shipping');

CREATE TYPE loyalty_tier AS ENUM ('standard', 'silver', 'gold', 'platinum');

-- Shared updated_at trigger.
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

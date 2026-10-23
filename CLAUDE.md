# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## There is ONE schema

`Employee Database/sql-mysql/` (MySQL) and `Employee Database/sql/` (PostgreSQL) are
the SAME schema — same 8 tables, same 92 columns, 11 of 11 view/report parity checks
identical to the cent. `sql/` is not a second design; see `PORTING.md`.

The old root-level `sql db` and `dummy_data.py` were an independent 2-table draft and
have been removed. The generator survives as `Employee Database/generate_data.py`,
rewritten to target the real schema and cover all seven business tables. Recover the
originals from `git show 1c5f63f:'sql db'` if ever needed.

Do not reintroduce a second set of table definitions anywhere in this repo.

## Current project: `Employee Database/`

A PostgreSQL schema for Employee : Customer : Order : Product, built to sit under a
voice assistant. Nothing else in this repo is live. See `Employee Database/README.md`
for the design rationale; the short version:

- `./load.sh` rebuilds the local Postgres database, `./load-mysql.sh` the MySQL one,
  `./deploy.sh` pushes to the VM and rebuilds there. All DROP the target first.
  `deploy.sh` now REQUIRES VM_HOST/VM_USER/VM_KEY from the environment (they used to
  be hardcoded, which published the VM's IP); real values live in untracked
  `.env.deploy`, so `source .env.deploy` before deploying.
- `generate_data.py` adds bulk rows on top of the hand seed:
  `python3 generate_data.py --customers 2000 --orders 8000`. It never writes
  generated columns (full_name, line_total, line_cost, search_document) and never
  sets order_number or order_status_history — triggers own those.
- `sql/` is numbered and order-dependent (`01`..`08`).

### The schema exists twice: Postgres AND MySQL

`sql/` is the PostgreSQL original. `sql-mysql/` is a MySQL 8/9 port, added to converge
with the partner's MySQL work. `./load-mysql.sh` builds it; `web/app_mysql.py` +
`web/requirements-mysql.txt` are the PyMySQL version of the viewer.

**`PORTING.md` is the authority on the differences — read it before editing either
tree.** The short version:

- Parity is verified: 11 of 11 view/report checks identical to the cent after a clean
  rebuild of each engine. Re-verify after any schema change; the 21 `FILTER` →
  `CASE WHEN` rewrites in `04_views.sql` are the likeliest place for a silent drift,
  and `average_order_value` specifically has already had a fan-out bug once.
- **Lost in MySQL:** `similarity()`/`dmetaphone()`/`unaccent()` (so the resolvers score
  discrete tiers, not continuous similarity — `sp_resolve_*`, not `ai.resolve_*`);
  `fn_profit_and_loss` is now `CALL sp_profit_and_loss(...)` and cannot be
  selected/joined/filtered; `timestamptz` → `DATETIME` (no timezone, store UTC);
  partial indexes; `statement_timeout` on the role (the client must now
  `SET SESSION max_execution_time` — `app_mysql.py` does, any new client must too).
- **MySQL has no schemas inside a database**, so the `ai` schema became an `ai_` table
  prefix (`ai.utterance` → `ai_utterance`).
- **MySQL cannot comment a view at all.** View descriptions live in the `ai_object_doc`
  table, which `ai_schema_context` joins back in. Adding a view means adding its row
  there too, or its description silently never reaches the model's prompt.
- **`sql-mysql/06_comments.sql` can silently revert a schema change.** MySQL requires
  restating a column's whole definition to set its comment, so a type/default/nullability
  change in `02_core_tables.sql` must be mirrored there.
- `sql_mode` is set by `load-mysql.sh` via `--init-command`, not inside a `.sql` file —
  each file runs in its own `mysql` process, so a `SET SESSION` would cover one file only.
- `deploy-mysql.sh` exists but **has never been run**: the VM runs PostgreSQL 14.24, not
  MySQL. It checks for a `mysql` client and aborts if absent.
- The `ai` schema holds entity resolution, the conversation log, and `ai.schema_context`
  — a view that generates the model's schema prompt from live `COMMENT ON` metadata.
  **Documenting a column is how you teach the assistant about it**, so keep
  `06_comments.sql` current with any schema change.
- `order` is a reserved word: always `"order"`. Historical money comes from
  `order_item.unit_price` (a snapshot), never `product.unit_price`.

There is no test suite. Verification = `./load.sh` clean + spot-checking the
`ai.resolve_*` functions and `v_*` views in psql.

## `free-server_key.pem` — untracked, never commit

The SSH private key for the Azure VM sits in the repo root and is **untracked with no
`.gitignore` in place** (the old one went with the clear-out). A bare `git add -A` or
`git add .` will stage it. Stage files explicitly, or add a `.gitignore` first.

## The v1 archive lives in `.git`

The previous site — a personalized news feed (static GitHub Pages frontend + Flask/TF-IDF
backend on an Azure VM) — is preserved in full at tag **`archive/v1`** (41 files). Nothing
outside `.git` holds that history, so **`.git` must survive any future cleanup**.

    git show archive/v1:CLAUDE.md      # full v1 architecture doc: ranking, data flow, deploy
    git ls-tree -r archive/v1 --name-only
    git checkout archive/v1

Read the archived `CLAUDE.md` before reviving or referencing any v1 behavior — the ranking
pipeline and its tuning constants are documented there with the measurements behind them.

Belt-and-braces copies (outside git, not a substitute for the tag): zips at
`~/Desktop/News-Paper-Scraper-Archive-2026-09-03/`. The backend never lived in this repo
and was archived off-VM the same day.

## `main` is the deploy branch

Remote is `https://github.com/jchrislee16/News-Paper-Scraper.git`, and `main` is served by
GitHub Pages. Pushing to `main` publishes to the live site — everything committed here is
public. Backend source and credentials stayed on the VM for that reason.

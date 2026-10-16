# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Current project: `Employee Database/`

A PostgreSQL schema for Employee : Customer : Order : Product, built to sit under a
voice assistant. Nothing else in this repo is live. See `Employee Database/README.md`
for the design rationale; the short version:

- `./load.sh` rebuilds the local database, `./deploy.sh` pushes to the VM and rebuilds
  there. Both DROP the target database first.
- `sql/` is numbered and order-dependent (`01`..`08`).
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

-- 009_pins_source_unique_index.sql
-- Make (source, source_external_id) UNIQUE so the importer's PostgREST upsert
-- (Prefer: resolution=merge-duplicates, on_conflict=source,source_external_id)
-- has a matching, inferable unique index.
--
-- Migration 008 created this as a PLAIN PARTIAL index
-- (pins_source_external_id_idx ... WHERE source_external_id IS NOT NULL).
-- PostgREST emits `ON CONFLICT (source, source_external_id)` with no predicate,
-- so Postgres cannot infer a partial index as the arbiter and the upsert fails
-- with "no unique or exclusion constraint matching the ON CONFLICT specification".
--
-- This replaces it with a NON-partial UNIQUE index. NULL source_external_id
-- rows (every pre-existing user pin) are permitted to repeat because NULLs are
-- distinct in a unique index by default; only non-null (source, external_id)
-- pairs are constrained to be unique — exactly the importer's dedup key.
--
-- Safe to apply: on staging the only non-null external_ids are the
-- staging_density_seed rows, each carrying a unique (source, source_external_id);
-- on prod every pin is source='user' with NULL external_id.
--
-- Spec: docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md §3
-- Plan: docs/superpowers/plans/2026-05-24-pre-populate-pins-phase-2.md

DROP INDEX IF EXISTS pins_source_external_id_idx;

CREATE UNIQUE INDEX IF NOT EXISTS pins_source_external_id_key
  ON pins (source, source_external_id);

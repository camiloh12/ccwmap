# Production pre-populate — manual health check (Stage B / B5)

Manual daily monitoring for the first production pre-populate import (TX/FL/PA,
7 sources, ~23,813 system pins imported 2026-07-06). Run this once a day; after
**≥ 7 consecutive clean days**, declare the pilot stable.

> **Why manual:** the spec (`docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md`
> § Observability) designed an automated daily `pin-health-check` Edge Function
> that emails a digest — **it was never built.** The only deployed Edge
> Functions are `delete-account` and `send-moderation-email`. Until the
> automated check exists, use this runbook. (`recent_deletes` does **not** need
> pruning here — the `enforce_delete_rate_limit` trigger self-prunes per user on
> each delete, so it stays bounded without a cron.)

- **System user** (owns every imported pin): `81775f8b-1a6a-47d6-b793-e9ab7e38634e`
- **Prod project ref:** `gqbxloaqamokbolcvesg`
- Run all SQL in the **prod dashboard SQL editor** (read-only; no MCP repoint needed).

---

## Daily queries

```sql
-- 1. System pins by source/status — compare to the import baseline below.
SELECT source, status, count(*)
FROM pins
WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
GROUP BY source, status
ORDER BY source, status;

-- 2. Deletions in the last 24h (mass-delete / scripted-attack signal).
SELECT count(*) AS deletions_24h
FROM pin_deletions
WHERE deleted_at > now() - interval '24 hours';

-- 3. Orphaned system pins (stays 0 until a re-import runs).
SELECT count(*) AS orphaned
FROM pins
WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
  AND source_orphaned_at IS NOT NULL;

-- 4. Clusters still resolve — regression guard for BUG-005 (geography/geometry).
--    Must return 'cluster' rows, never error 42883.
SELECT kind, count(*)
FROM get_pins_in_view(25.0, -107.0, 37.0, -93.0, 5)
GROUP BY kind;
```

### Import baseline (query 1) — total 23,813

| source   | status          | count  |
|----------|-----------------|--------|
| nces     | 2 (NO_GUN)      | 15,414 |
| gsa      | 2 (NO_GUN)      | 4,216  |
| osm      | **1 (UNCERTAIN)** | 3,287 |
| courts   | 2 (NO_GUN)      | 469    |
| ipeds    | 2 (NO_GUN)      | 290    |
| military | 2 (NO_GUN)      | 77     |
| faa      | 2 (NO_GUN)      | 60     |

`osm` is intentionally **status 1 / UNCERTAIN** (yellow), not NO_GUN — OSM tags
can't confirm the TX 51% / FL "primarily-devoted" bar test. Everything else is
status 2 / NO_GUN.

---

## What counts as a clean day

| Signal | Clean | Investigate |
|---|---|---|
| Query 1 per-source counts | roughly stable; a handful of user edits/deletes is normal | any source **drops > 10%** day-over-day (mass-delete or mass-orphan) |
| Query 2 deletions_24h | small / expected | **> ~1,000** (scripted-attack signal) |
| Query 3 orphaned | `0` | `> 0` before any re-import ran (unexpected) |
| Query 4 | returns `cluster` rows | any error, or `0` rows over populated area |

### Also glance (prod dashboard)

- **Logs → Postgres** — filter for `P0001` (delete-rate-limit trigger firing)
  and any RLS `permission denied` / `row violates row-level security` write
  anomalies. These are the two specific signals B5 calls out.
- **Advisors** (Reports → Security / Performance) — weekly; no *new* warnings vs.
  the set staging shows (all pre-existing are expected 008 infra lints).

---

## Gate + rollback

- **Gate:** 7 consecutive clean days → declare the pilot stable (Stage B done).
- **Rollback** (bad data / instability / any go-back decision), once in the prod
  dashboard SQL editor — removes ONLY importer-written pins (real user pins have
  a different `created_by` and are never matched):

  ```sql
  DELETE FROM pins WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e';
  ```

---

## Follow-up: automate this

Replace this runbook with the spec's `pin-health-check` Edge Function — the four
queries above on a daily `pg_cron` schedule, emailing `camilo@kyberneticlabs.com`
via the existing Brevo / `send-moderation-email` pattern, alerting only on
threshold breaches. Self-contained: function + cron migration + staging test.
See the spec's § Observability for the original design.

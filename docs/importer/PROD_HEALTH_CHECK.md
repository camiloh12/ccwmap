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

## Daily query

One read-only statement — the SQL editor only renders the last statement's
result, so the four checks are combined into a single result set (`chk`
column says which check each row belongs to).

```sql
-- 1_source_status / 1_total: system pins by source/status — compare to the import baseline below.
-- 2_deletions_24h: deletions in the last 24h (mass-delete / scripted-attack signal).
-- 3_orphaned: orphaned system pins (stays 0 until a re-import runs).
-- 4_clusters: clusters still resolve — regression guard for BUG-005 (geography/geometry).
--             Must return 'cluster' rows, never error 42883.
SELECT '1_source_status' AS chk, coalesce(source,'?') || ' / ' || status AS key, count(*)::text AS value
FROM pins WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e' GROUP BY source, status
UNION ALL
SELECT '1_total', 'all', count(*)::text FROM pins WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
UNION ALL
SELECT '2_deletions_24h', '-', count(*)::text FROM pin_deletions WHERE deleted_at > now() - interval '24 hours'
UNION ALL
SELECT '3_orphaned', '-', count(*)::text FROM pins WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e' AND source_orphaned_at IS NOT NULL
UNION ALL
SELECT '4_clusters', kind, count(*)::text FROM get_pins_in_view(25.0, -107.0, 37.0, -93.0, 5) GROUP BY kind
ORDER BY 1, 2;
```

### Expected output (import baseline, 2026-07-06)

| chk             | key                | value  |
|-----------------|--------------------|--------|
| 1_source_status | faa / 2            | 60     |
| 1_source_status | gsa / 2            | 4216   |
| 1_source_status | hifld_courts / 2   | 469    |
| 1_source_status | hifld_military / 2 | 77     |
| 1_source_status | ipeds / 2          | 290    |
| 1_source_status | nces / 2           | 15414  |
| 1_source_status | **osm / 1**        | 3287   |
| 1_total         | all                | 23813  |
| 2_deletions_24h | -                  | 0      |
| 3_orphaned      | -                  | 0      |
| 4_clusters      | cluster            | 28     |

Source keys are the literal `pins.source` values (`hifld_courts`,
`hifld_military` — not `courts` / `military`).

`osm` is intentionally **status 1 / UNCERTAIN** (yellow), not NO_GUN — OSM tags
can't confirm the TX 51% / FL "primarily-devoted" bar test. Everything else is
status 2 / NO_GUN.

---

## What counts as a clean day

| Signal | Clean | Investigate |
|---|---|---|
| `1_source_status` / `1_total` | roughly stable; a handful of user edits/deletes is normal | any source **drops > 10%** day-over-day (mass-delete or mass-orphan), or `osm` not status 1 |
| `2_deletions_24h` | small / expected | **> ~1,000** (scripted-attack signal) |
| `3_orphaned` | `0` | `> 0` before any re-import ran (unexpected) |
| `4_clusters` | `cluster` rows (28 at baseline) | the query errors (e.g. `42883`), or no `4_clusters` row over populated area |

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
checks in the daily query above on a daily `pg_cron` schedule, emailing `camilo@kyberneticlabs.com`
via the existing Brevo / `send-moderation-email` pattern, alerting only on
threshold breaches. Self-contained: function + cron migration + staging test.
See the spec's § Observability for the original design.

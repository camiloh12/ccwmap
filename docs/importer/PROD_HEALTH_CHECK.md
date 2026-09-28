# Production health check

## Automated daily check

`.github/workflows/health-check.yml` (Actions → *Daily Health Check*) checks
prod and staging every day at 11:00 UTC (07:00 ET). It stays silent while
everything is fine.

- **Digest:** open a run → *Summary*. Each environment lists every signal
  with its value and threshold, imported pins by source and status, user
  pins, imported pins users have corrected, and reports filed on imported
  pins in the last 7 days.
- **Alert:** when a check fails, the run goes red and the `alert` job opens
  one issue, *Daily health check failing* (label `health-check`), listing the
  findings per environment. While that issue is open, each failing run adds a
  comment instead of opening another. Close it once the cause is fixed.
- **Staging** is judged only on checks 1–2, because its data is wiped and
  re-imported during testing. The daily query also keeps the free-tier
  project from auto-pausing.
- **Test the alert path:** *Run workflow* from `master` with
  *simulate_failure* checked. From any other branch the `prod` job can't read
  `PROD_DB_URL` (`production-plan` allows only `master`), so it fails.
- Thresholds are at the top of `ci/health_check.py`; the query is
  `ci/health_check.sql`. Both are read-only.

### What each finding means

| # | Finding | Likely cause | What to do |
|---|---|---|---|
| 1 | `database unreachable` | staging auto-paused; a password reset the pooler hasn't picked up yet | staging: resume it in the dashboard (90-day window). Otherwise see `docs/dev/STAGING.md` → Troubleshooting |
| 1 | `<NAME> is malformed` | a mis-pasted secret | re-set it from its `.local/` file (`docs/dev/STAGING.md`); the value is never printed |
| 2 | clusters: HTTP ≠ 200 or no clusters | `get_pins_in_view` broke (BUG-005 looked like this), or anon grants changed | run the manual query below in the dashboard; look at the last migration |
| 3 | prod has no imported pins | a mass delete, or someone ran the rollback | check `pin_deletions` and `import_runs` |
| 4 | imported pins deleted | users can't delete them (012), so: an admin delete, a leaked service key, or an RLS regression | `pin_deletions.deleted_by` for rows whose `original_created_by` is the system user says who |
| 5 | more than 50 deletions in 24 h | a scripted mass delete | `pin_deletions.deleted_by`; Postgres logs show `P0001` if the rate limit fired |
| 6 | statutory pins no longer NO_GUN | an edit made between 012 and 013, a 013 regression, a service-role write (importer bug or leaked key), or a dashboard edit | restore them (below), then find out how it happened |
| 7 | more than 50 user edits of imported pins in 24 h | vandalism or a buggy client | look at those pins' names and `last_modified` |
| 8 | more than 100 orphaned imported pins | a source dropped records in the last import | review the import report before the next apply |
| 9 | stale citations | a `data/state_laws/states.yaml` cell's `last_verified_date` is over a year old | re-verify the law, bump the date, re-import |
| — | a job *ended before reporting* | the script crashed or timed out | open the run log (tool output there is redacted) |

### Restore a flipped statutory pin

Run in the **prod dashboard SQL editor** once per pin id from the issue. The
dashboard runs as `postgres`, which 013's lock doesn't apply to. The tag
comes from the pin's source (`data/state_laws/states.yaml`). The finding
clears because the status is NO_GUN again. Afterwards the pin is
`user_modified` (a dashboard edit counts as a user edit), so imports leave
it alone. If no user had edited it (a service-role flip), hand it back to
the importer with
`UPDATE pins SET user_modified = false WHERE id = '<pin id>';`
(013 lets an update that only resets that flag stick).

```sql
UPDATE pins
SET status = 2,
    restriction_tag = (CASE source
      WHEN 'gsa'            THEN 'FEDERAL_PROPERTY'
      WHEN 'hifld_military' THEN 'FEDERAL_PROPERTY'
      WHEN 'faa'            THEN 'AIRPORT_SECURE'
      WHEN 'hifld_courts'   THEN 'STATE_LOCAL_GOVT'
      WHEN 'nces'           THEN 'SCHOOL_K12'
      WHEN 'ipeds'          THEN 'COLLEGE_UNIVERSITY'
    END)::restriction_tag_type
WHERE id = '<pin id>'
  AND created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
  AND confidence = 'high'
  AND source IN ('gsa', 'hifld_military', 'faa',
                 'hifld_courts', 'nces', 'ipeds')
RETURNING id, name, source, status, restriction_tag;
```

If it returns no row, the pin isn't a statutory imported pin: stop and look
at it by hand.

---

## Manual query (ad hoc)

For a look outside the daily run. The pilot's 7-day gate (Stage B / B5)
closed on 2026-09-26.

- **System user** (owns every imported pin): `81775f8b-1a6a-47d6-b793-e9ab7e38634e`
- **Prod project ref:** `gqbxloaqamokbolcvesg`
- Run all SQL in the **prod dashboard SQL editor** (read-only; no MCP repoint needed).

One read-only statement. The SQL editor only renders the last statement's
result, so the four checks are combined into a single result set (the `chk`
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

## Rollback

- **Rollback** (bad data / instability / any go-back decision), once in the prod
  dashboard SQL editor — removes ONLY importer-written pins (real user pins have
  a different `created_by` and are never matched):

  ```sql
  DELETE FROM pins WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e';
  ```

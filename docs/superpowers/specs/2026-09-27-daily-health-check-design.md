# Daily health check — design

**Date:** 2026-09-27 · **Status:** approved design, pending spec review
**Replaces:** the manual runbook `docs/importer/PROD_HEALTH_CHECK.md` (kept for ad-hoc use)
**Supersedes:** the `pin-health-check` Edge Function in
`2026-05-10-pre-populate-pins-design.md` §6 Observability (never built)

## Goal

A daily automated check of prod and staging that stays silent when things are
fine, opens a GitHub issue when they aren't, and keeps the free-tier staging
project from auto-pausing (it paused 2026-09-07 → 09-14; a weekly job wasn't
enough activity).

## Decisions (owner, 2026-09-27)

| Decision | Choice | Why |
|---|---|---|
| Where it runs | GitHub Actions scheduled workflow | CI already holds the DB secrets and has the redaction/URL-check helpers from the DB pipeline; nothing to deploy to Supabase (edge functions aren't deployed by CI and have drifted before) |
| Alert channel | GitHub issue (one open issue, commented on repeat) + red run | Same pattern as `brevo-keepalive.yml` / `weekly-scans.yml`; GitHub emails the owner; no Brevo key in CI |
| Imported-pin deletes | Tripwire (alert on any) | Users can't delete imported pins (012), so any delete means admin error, a leaked key, or a policy regression |
| Statutory flips | Tripwire (alert on any) | 013 keeps users from changing status on `confidence = 'high'` imported pins, so a user-modified statutory pin that isn't red means a bypass, a regression, a flip made between 012 and 013, or a deliberate admin edit in the dashboard (admin edits also set `user_modified`) |
| State | Stateless | Every signal is a 24 h window or a current count read from the DB; no snapshot table or artifacts |

## Architecture

`.github/workflows/health-check.yml`

- Triggers: `schedule: '0 11 * * *'` (11:00 UTC, 07:00 ET) and
  `workflow_dispatch` with one boolean input, `simulate_failure` (default
  false), which adds a synthetic finding to exercise the alert path.
- Top-level `permissions: contents: read`; `concurrency: health-check`.

| Job | Environment | Secrets / variables | Checks |
|---|---|---|---|
| `staging` | none | `STAGING_DB_URL` (secret); `STAGING_SUPABASE_URL`, `STAGING_SUPABASE_ANON_KEY` (repo **variables**; the anon key ships in every app build, so it isn't secret) | reachability, clusters |
| `prod` | `production-plan` (master-only branch policy, no approval; the same environment the migration dry-run uses; never `production`) | `PROD_DB_URL` (environment secret); `SUPABASE_URL`, `SUPABASE_ANON_KEY` (existing repo secrets) | all checks |
| `alert` | none | `GITHUB_TOKEN` with `issues: write` (this job only) | runs `if: always()` after both; acts only if either failed |

Each environment job checks out the repo and runs one entrypoint:
`python3 ci/health_check.py --env staging|prod`.

## Checks

Signals come from one read-only SQL query (`ci/health_check.sql`) plus one
REST call. "Imported" = `created_by = kSystemUserId`
(`81775f8b-1a6a-47d6-b793-e9ab7e38634e`).

| # | Signal | Source | Env | Alert when |
|---|---|---|---|---|
| 1 | Database reachable | psql connect + query | both | connection or query fails |
| 2 | Clusters load for a signed-out user | `POST /rest/v1/rpc/get_pins_in_view` with the anon key, TX box (25.0, −107.0)–(37.0, −93.0), zoom 5 | both | HTTP ≠ 200, or 0 rows with `kind = 'cluster'` |
| 3 | Imported pins total | `pins` | prod | = 0 |
| 4 | Imported pins deleted, last 24 h | `pin_deletions.original_created_by` | prod | > 0 |
| 5 | All pin deletions, last 24 h | `pin_deletions.deleted_at` | prod | > 50 |
| 6 | Statutory pins flipped | imported, `confidence = 'high'`, `user_modified`, `status <> 2` | prod | > 0 (finding lists up to 20 ids + names) |
| 7 | User edits of imported pins, last 24 h | imported, `user_modified`, `last_modified` in window | prod | > 50 |
| 8 | Orphaned imported pins | `source_orphaned_at IS NOT NULL` | prod | > 100 |
| 9 | Stale citations | imported, `legal_citation_verified_date < current_date − 12 months` | prod | > 0 (first possible 2027-05-31) |

Digest only (never alerts), written to the job summary every run:
imported pins by source/status, user pins total, total user-corrected
imported pins (the data-quality signal 0.9.0 should grow), reports filed on
imported pins in the last 7 days (0 until 0.9.0 enables them), and each
signal above with its value and threshold. Staging's digest shows its counts
without judging them: staging data is wiped and re-imported during testing.

Thresholds are constants at the top of `ci/health_check.py`.

## Components

- **`ci/health_check.sql`** — one `SELECT json_build_object(...)` returning
  every metric above. Read-only: the session runs with
  `default_transaction_read_only = on` and a `statement_timeout`. No
  data-modifying statements.
- **`ci/health_check.py`** (stdlib only, like the other `ci/` scripts):
  - `problems()` from `ci/check_db_url.py` validates the DB URL first
    (never prints it).
  - runs `psql` via `subprocess` (connect timeout, `ON_ERROR_STOP`), parses
    the JSON line.
  - calls the REST endpoint with `urllib`, counts cluster rows.
  - `evaluate(env, metrics, rest) -> list[Finding]` — pure function, all the
    threshold logic.
  - `render_digest(env, metrics, rest, findings) -> str` — pure; markdown.
  - writes the digest to `$GITHUB_STEP_SUMMARY`, the findings (one line
    each) to `$GITHUB_OUTPUT` as `findings`, and exits 1 if there are any.
  - every captured stderr/stdout passes through `redact()` from
    `ci/redact.py` before it's printed or written.
- **`alert` job** (`actions/github-script`): reads
  `needs.staging.outputs.findings` / `needs.prod.outputs.findings` and the
  job results; finds the open issue labeled `health-check` (`issues.listForRepo`,
  `labels: health-check`, `state: open`). If one exists it comments;
  otherwise it creates "Daily health check failing" with that label. The
  body lists findings per environment and links the run. A job that failed
  without writing findings is reported as "failed before reporting; see run".
  The owner closes the issue after fixing the cause.

## Error handling

| Failure | Result |
|---|---|
| Malformed DB URL | finding "`<NAME>` is malformed: <problems>" (no part of the URL) |
| DB unreachable / timeout | finding "database unreachable" + redacted error excerpt; for staging it adds "staging may be paused: resume it in the dashboard (90-day window)" |
| REST call fails | finding with the HTTP status (no response body, which could echo headers) |
| Unexpected exception | redacted traceback, exit 1, reported by `alert` as "failed before reporting" |
| `alert` job itself fails | the run is red; GitHub's failed-scheduled-run email is the backstop |

## Security

- `PROD_DB_URL` is used only in the `production-plan` environment, whose
  branch policy allows only `master`; a dispatch from another branch can't
  read it (its `prod` job fails, and `alert` would report that, so dispatch
  from `master`). The workflow never names `production`.
- Read-only DB session; `statement_timeout` bounds the query.
- Only `alert` can write issues; environment jobs are `contents: read`.
- Issue and summary contain counts, pin ids and pin names (public map
  data), never URLs or keys; all tool output is redacted.

## Testing

- **`ci/tests/test_health_check.py`** — `evaluate()` for each rule at its
  threshold and one past it; staging applies only rules 1–2; digest
  contains the counts; malformed-URL and unreachable paths produce findings
  without leaking the URL; REST parsing counts only `cluster` rows;
  `simulate_failure` adds exactly one finding.
- **`ci/tests/test_health_check_workflow.py`** — schedule + dispatch
  triggers; `prod` uses `production-plan`; no job uses `production`;
  top-level permissions are `contents: read`; only `alert` has
  `issues: write`; `alert` runs `if: always()`; the SQL file contains no
  INSERT/UPDATE/DELETE/TRUNCATE/ALTER/DROP/CREATE/GRANT.
- These run in the PR via `db-migrations.yml`'s `workflow-tests` job
  (it triggers on `ci/**`).
- **Live:** before merge, run `ci/health_check.sql` against staging via MCP
  and check the JSON. After merge: one normal dispatch (expect green, both
  digests), one with `simulate_failure` (expect a `health-check` issue, then
  a comment on a second run); close the test issue.

## Rollout

1. PR: workflow, `ci/health_check.{py,sql}`, tests, docs.
2. Before merge: set repo variables `STAGING_SUPABASE_URL` and
   `STAGING_SUPABASE_ANON_KEY` (Claude can set them with `gh variable set`
   from the staging project's publishable key).
3. Merge, then the live checks above.
4. Watch the first scheduled run. If rule 6 fires, it lists statutory pins
   flipped before 013; the runbook gets the SQL to restore them.

## Docs

- `docs/importer/PROD_HEALTH_CHECK.md` — "Automated daily" section at the
  top (what runs, where the digest is, how to read an alert issue); the
  manual query stays for ad-hoc checks; add the restore-a-flipped-pin SQL.
- `CLAUDE.md` CI/CD workflow list — add `health-check.yml`.
- `docs/dev/STAGING.md` — the daily job keeps staging awake.

## Out of scope

- Email via Brevo; Supabase Edge Function / `pg_cron`.
- Per-source day-over-day snapshots (the tripwires cover the cases users can
  cause; admin mass-deletes still land in `pin_deletions` → rule 4).
- Postgres log scanning (delete-rate-limit `P0001`, RLS denials) and
  advisor checks: both need the Management API token; revisit if needed.
- Importer failed-run email (spec §6 importer observability).

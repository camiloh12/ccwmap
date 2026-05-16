# Staging Supabase

CCW Map runs a permanent free-tier Supabase project (`ccwmap-staging`) that
mirrors the prod schema. New migrations apply here first via the
`.github/workflows/supabase-migration-validate.yml` workflow before they
ever touch prod. The same `kSystemUserId` UUID is provisioned in both
projects so app code never branches on environment.

## Coordinates

| | Project ref | Project URL |
|---|---|---|
| **Prod**    | (see Supabase dashboard) | (see Supabase dashboard) |
| **Staging** | `miihmfhnsfmwgrvgayns` | `https://miihmfhnsfmwgrvgayns.supabase.co` |

System user UUID is in `lib/core/system_constants.dart` as `kSystemUserId`.
Same value in both projects' `auth.users`. Password stored only in 1Password
(never used at runtime — the importer authenticates via service-role key).

## Applying migrations

- **Staging** — a new `supabase/migrations/NNN_*.sql` triggers
  `.github/workflows/supabase-migration-validate.yml` on the PR. The
  workflow applies via `psql` and reports pass/fail. The DB connection
  string lives in the `STAGING_DB_URL` GitHub Actions secret.
- **Prod** — apply manually via the Supabase MCP `apply_migration` tool
  (or the dashboard SQL editor) after the PR merges. We will automate the
  prod apply in a later phase once we have more confidence in the
  PR-validate workflow.

The PR-validate workflow re-applies every migration in the PR on each
push. This is safe because all migrations under `supabase/migrations/` use
idempotent patterns (`IF NOT EXISTS`, `OR REPLACE`, `DROP ... IF EXISTS`
before `CREATE`). Future migrations MUST follow that convention — the
workflow will otherwise fail on the second push.

Note: `psql -f` does NOT register the migration in
`supabase_migrations.schema_migrations`. The lenient migration-count drift
check in the workflow accommodates that; a stricter check arrives in a
later phase.

## Bootstrap (one-time)

A fresh staging environment is bootstrapped from `000_baseline.sql`
(captured prod state before the migrations directory was in git) followed
by 004-007 and the current head migration. The full concatenated bundle
can be regenerated locally with:

```bash
cat supabase/migrations/000_baseline.sql \
    supabase/migrations/004_user_agreements.sql \
    supabase/migrations/005_pin_reports.sql \
    supabase/migrations/006_blocked_users.sql \
    supabase/migrations/007_pin_name_length.sql \
    supabase/migrations/008_provenance_and_view_rpc.sql \
  > .local/staging_bootstrap.sql
```

Paste the result into the staging dashboard's SQL Editor. Verify with:

```sql
SELECT
  (SELECT count(*) FROM pg_extension WHERE extname='postgis') AS postgis_installed,
  (SELECT count(*) FROM pg_type WHERE typname='restriction_tag_type') AS enum_exists,
  (SELECT count(*) FROM information_schema.columns WHERE table_schema='public' AND table_name='pins') AS pins_column_count,
  (SELECT count(*) FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('pins','user_agreements','pin_reports','blocked_users','pin_deletions','import_runs','recent_deletes')) AS expected_tables_present,
  (SELECT count(*) FROM pg_trigger WHERE tgrelid='public.pins'::regclass AND NOT tgisinternal) AS pin_trigger_count,
  (SELECT count(*) FROM pg_proc WHERE proname='get_pins_in_view') AS rpc_exists,
  (SELECT count(*) FROM pg_policy WHERE polrelid='public.pins'::regclass AND polname='deny_system_user_writes') AS deny_policy_exists;
```

Expected (post-008): postgis=1, enum=1, pins_column_count=25, tables=7,
trigger_count=4, rpc=1, deny_policy=1.

If the SQL Editor truncates a long paste (it has hiccupped on `import_runs`
once before — symptom: `expected_tables_present = 6`), re-run just the
table definition for whichever piece is missing.

## GitHub Actions secrets

| Secret | Purpose | Required for |
|---|---|---|
| `STAGING_DB_URL` | Full Postgres connection string for staging. Format: `postgresql://postgres:<DB_PASSWORD>@db.miihmfhnsfmwgrvgayns.supabase.co:5432/postgres?sslmode=require` | `supabase-migration-validate.yml` |
| `PROD_DB_URL`    | Optional; enables migration-count drift check between staging and prod. | Same workflow (skipped if unset) |

Database passwords come from the Supabase dashboard → Project Settings →
Database. Keep them only in 1Password.

## Keeping staging alive

Free-tier projects pause after 7 days of inactivity. The daily
`pin-health-check` Edge Function planned for a later phase will ping
staging as a side effect. Until that ships, run any MCP query against
staging once a week to keep it warm (a `SELECT 1` is enough).

## Refreshing staging data

Pin count today: ~199 in prod, 0 in staging. When staging drifts
unhelpfully from prod, dump prod via Studio (Database → Backups → Logical
backup) and restore into staging. Not automated for v1.

## Storage limit

Free tier: 500 MB. We're well under at pilot scale (~50k pins). Revisit
before national rollout (~400k+ pins) — may need to upgrade staging to Pro.

## The non-negotiable rule

The importer's `apply` mode never targets prod from a developer's local
machine. Prod applies only via the manual GitHub Actions workflow
(arriving in a later phase), and ideally only after the same import has
run cleanly against staging.

## System user

Provisioned in both prod and staging with id matching `kSystemUserId`
(see `lib/core/system_constants.dart`). Email:
`system+ccwmap@kyberneticlabs.com`. Password in 1Password; not used at
runtime.

## Migration history

| Migration | Applied to staging | Applied to prod | Notes |
|---|---|---|---|
| 000_baseline                     | 2026-05-16 | n/a (pre-existing)       | Reconstruction of pre-004 prod state |
| 004_user_agreements              | 2026-05-16 | (per Supabase migrations table) | |
| 005_pin_reports                  | 2026-05-16 | (per Supabase migrations table) | |
| 006_blocked_users                | 2026-05-16 | (per Supabase migrations table) | |
| 007_pin_name_length              | 2026-05-16 | (per Supabase migrations table) | |
| 008_provenance_and_view_rpc      | 2026-05-16 | _pending_                       | Phase 0 of pre-populate-pins; no app-visible changes |

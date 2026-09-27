# Staging Supabase

CCW Map runs a permanent free-tier Supabase project (`ccwmap-staging`) that
mirrors the prod schema. New migrations apply here first via the
`.github/workflows/db-migrations.yml` pipeline (on every PR) before they
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

Migrations reach staging and prod **only** through GitHub Actions, using the
pinned Supabase CLI (`supabase db push`). Design:
`docs/superpowers/specs/2026-09-26-db-migrations-pipeline-design.md`.

| When | Workflow → job | Target |
|---|---|---|
| PR touching `supabase/migrations/**`, `ci/**`, `db-migrations.yml` or `db-repair.yml` | `db-migrations.yml` → `workflow-tests` → `staging-pr` | staging (re-applies the PR's own new migrations on every push) |
| Merge to `master` touching `supabase/migrations/**`, or **Run workflow** | `db-migrations.yml` → `staging` → `plan` → `apply` | staging, then prod after **owner approval** |
| Manual | `db-repair.yml` | the history table only (`list` / `applied` / `reverted`); never runs SQL. The prod target waits for owner approval too, even for `list`. |

**Approving a prod deploy.** The run pauses at `apply`. Open the run and read
the `plan` job's summary ("Pending for prod"). Approve only if every listed
migration is safe for the app version users currently run (rule 5 below).
Reject to hold it: it stays pending, reappears in the next plan, and **Run
workflow** on `db-migrations.yml` deploys it later. `apply` re-checks that
prod's pending list still equals the approved one and refuses otherwise.

**Reading a run from the terminal.** While a run waits for approval,
`gh run view --log` returns nothing. Read a finished job's log with
`gh api repos/camiloh12/ccwmap/actions/jobs/<job-id>/logs` (job ids:
`gh run view <run-id> --json jobs`). The Supabase CLI doesn't print a
migration's `RAISE NOTICE` output, so confirm what a migration did with a
query, not from its notices.

**What's applied where:**
- `supabase_migrations.schema_migrations` in each database (dashboard →
  Database → Migrations);
- the `production` environment's deployment log on GitHub (commit, run,
  approver);
- every run's summary (`supabase migration list`).

### Rules

1. Never apply repo migrations by hand or via MCP `apply_migration`: MCP
   records timestamp versions that break the CLI's history. After an
   emergency hand-fix in the dashboard, do both of these:
   - commit the same SQL as a new migration file;
   - record its version as applied on prod with `db-repair`
     (`applied <version>`).

   A history row with no file makes every deploy fail with "Remote migration
   versions not found". A file with no row makes the next deploy run the SQL
   again, which is harmless only if it's idempotent.
2. Never edit an applied migration's SQL; fix forward with a new migration.
3. Keep migrations idempotent (`IF NOT EXISTS`, `CREATE OR REPLACE`,
   `DROP … IF EXISTS` before `CREATE`). The PR loop re-applies them on every push.
4. No transaction-unsafe statements (`CREATE INDEX CONCURRENTLY`, `VACUUM`).
   Each migration runs in one transaction.
5. A migration the currently deployed app can't handle is **rejected at the
   approval gate** until the new app version is adopted.

### Troubleshooting

- **"Remote migration versions not found in local migrations directory"**:
  the database has a migration the checkout lacks.
  - On a PR: merge `master` into the branch.
  - Most often it's **another open PR's** migration: staging is shared, and
    every PR's `staging-pr` applies its own new migrations there. Merge (or
    close) that PR first, or clear its version on staging with `db-repair`
    (`staging` / `reverted` / `<version>`); its next push re-applies it.
  - Otherwise it's an abandoned PR's migration left on staging. Remove it with
    `db-repair` (`staging` / `reverted` / `<version>`), and undo its schema by
    hand if needed.
- **Staging unreachable**: the free-tier project probably auto-paused (the
  dashboard shows *Paused*); resume it. Prod deploys wait on staging. The CLI
  jobs connect through the pooler host, which stays resolvable, so they fail at
  the connection instead; `Name or service not known` shows up in the importer
  and MCP, which use the project's own `<ref>.supabase.co` host.
- **`FATAL: password authentication failed … (SQLSTATE 28P01)`**: the log shows
  the host and user it tried (never the password). If those are right, the
  password is wrong, or it was **just reset**: the shared pooler (Supavisor)
  caches credentials and can keep rejecting a new, correct password for a while
  ([Supabase doc](https://supabase.com/docs/guides/troubleshooting/supavisor-error-password-authentication-failed-after-password-rotation)).
  - Wait about 10 minutes, then retry at most 3 times. Don't reset again: each
    reset restarts the wait, and repeated failures trip the pooler's circuit
    breaker.
  - The direct host can't be used to test the password: it is IPv6-only, and
    neither GitHub runners nor a typical home connection have IPv6.
  - After any reset, re-set the secret from the file: `STAGING_DB_URL`, or
    `PROD_DB_URL` in **both** environments.
- **A failed `apply`**: don't use "Re-run failed jobs". It re-uses the old
  run's approved list and refuses if anything changed. Use **Run workflow** on
  `db-migrations.yml` for a fresh plan and approval. The same applies when two
  deploy runs overlap and `apply` refuses because the pending list changed.
- **A master run shows `cancelled`**: GitHub keeps one *pending* job per
  concurrency group, so a newer deploy run superseded it. The newer run applies
  everything pending; if there is none, use **Run workflow**.
- **Don't leave an `apply` waiting for approval indefinitely**: approve or
  reject it. And don't run `db-repair` while a deploy is in flight; they aren't
  serialized.

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
  (SELECT count(*) FROM pg_policy WHERE polrelid='public.pins'::regclass AND polname IN ('deny_system_user_insert','deny_system_user_update','deny_system_user_delete')) AS deny_policies;
```

Expected (post-008): postgis=1, enum=1, pins_column_count=25, tables=7,
trigger_count=4, rpc=1, deny_policies=3.

If the SQL Editor truncates a long paste (it has hiccupped on `import_runs`
once before — symptom: `expected_tables_present = 6`), re-run just the
table definition for whichever piece is missing.

## GitHub Actions secrets

| Secret | Purpose | Required for |
|---|---|---|
| `STAGING_DB_URL` | **Repo** secret. Postgres connection string via the **Session mode pooler** (port 5432, NOT the direct-connect host), password percent-encoded. Format: `postgresql://postgres.miihmfhnsfmwgrvgayns:<DB_PASSWORD>@aws-<n>-<region>.pooler.supabase.com:5432/postgres`. Copy the exact host from the dashboard's **Connect** modal; the `aws-<n>` cluster differs between projects. | `db-migrations.yml` (`staging-pr`, `staging`), `db-repair.yml` (`repair-staging`) |
| `PROD_DB_URL` | **Environment** secret, set in **both** `production-plan` and `production` (both limited to `master`; `production` requires owner approval). Same pooler format with user `postgres.gqbxloaqamokbolcvesg`; prod's host is `aws-1-us-east-1.pooler.supabase.com`. Never a repo secret. | `db-migrations.yml` (`plan`, `apply`), `db-repair.yml` (`repair-prod`) |

**Set DB URL secrets from a file, never by retyping them.** A mis-pasted value (for
example a trailing space) makes the Supabase CLI echo the whole URL in its error, and
GitHub masks only the exact stored string, so it was published in PR #56's log. Put
the URL on one line in a git-ignored file and run, for example,
`gh secret set STAGING_DB_URL < .local/staging_db_url`, or for prod
`gh secret set PROD_DB_URL --env production < .local/prod_db_url` (repeat with
`--env production-plan`). Every DB job's first step (`ci/check_db_url.py`) rejects a
malformed URL without printing it, and all CLI output goes through `ci/redact.py`.

**IMPORTANT: do not use the direct connection** (`db.<ref>.supabase.co:5432`)
— it resolves to IPv6 only and GitHub Actions `ubuntu-latest` runners have
no IPv6 egress, so every workflow run will fail with `Network is unreachable`.
The session-mode pooler is dual-stack and works from CI. Get the exact
string from the Supabase dashboard's **Connect** modal or
Project Settings → Database → Connection pooling, picking **Session mode**
(transaction mode breaks some session-level DDL we may need in future
migrations).

Database passwords come from the Supabase dashboard → Project Settings →
Database. Keep them only in your password manager. Choosing **letters and
digits only** avoids percent-encoding mistakes. Nothing in the repo besides
these two secrets uses a DB password (the app uses the anon key, the importer
the service-role key), so a reset only means re-setting the secrets. Expect
the pooler to lag behind a reset; see Troubleshooting.

## Keeping staging alive

Free-tier projects pause when idle. A weekly ping is **not** enough: staging
paused between 2026-09-07 and 2026-09-14 despite the Monday
`importer-dry-run.yml`. The daily `pin-health-check` Edge Function planned for
a later phase will ping staging as a side effect. Until that ships, touch
staging every few days: any MCP query (`SELECT 1`), or a `db-repair`
`staging` / `list` run. A paused free project can be resumed from the
dashboard for 90 days; after that, only its backup can be downloaded.

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

> **Frozen 2026-09-26 at the pipeline cutover.** The authoritative record is now
> `supabase_migrations.schema_migrations` in each database (`supabase migration
> list`, or dashboard → Database → Migrations). This table is kept as history.

**Prod history conversion (2026-09-26).** Before the cutover, prod recorded
the migrations applied through MCP under timestamp versions, and 000 was
never recorded:

| Prod version | Repo migration |
|---|---|
| `20251023010755` | `update_last_modified` search-path hardening, folded into `000` |
| `20260424170807`, `…170813`, `…170820`, `…170823` | `004`–`007` |
| `20260705144447`, `20260705144509` | `008`, `009` |
| `20260706194421` | `010` |

`db-repair` reverted those 8 rows (run 36283480907) and recorded
`000 004 005 006 007 008 009 010` as applied (run 36283785399). The first
pipeline deploy then applied `011` (a no-op on prod, whose `location` was
already geography) and `012` (BUG-006) in run 36283922332. Both databases now
record `000`, `004`–`012`.

| Migration | Applied to staging | Applied to prod | Notes |
|---|---|---|---|
| 000_baseline                     | 2026-05-16 | n/a (pre-existing)       | Reconstruction of pre-004 prod state |
| 004_user_agreements              | 2026-05-16 | (per Supabase migrations table) | |
| 005_pin_reports                  | 2026-05-16 | (per Supabase migrations table) | |
| 006_blocked_users                | 2026-05-16 | (per Supabase migrations table) | |
| 007_pin_name_length              | 2026-05-16 | (per Supabase migrations table) | |
| 008_provenance_and_view_rpc      | 2026-05-16 | applied — confirmed live 2026-06-26 | Phase 0 of pre-populate-pins. The column-level UPDATE grant in §8 requires the `SupabasePinDto.toJsonForUpdate()` change (commit 3d45680) to be live in users' app builds — applying earlier would break pin editing for every existing user; gated on a tagged release (≥ v0.5.1), now satisfied (v0.6.0 in prod). Confirmed present in prod via the v0.7.0 caveat-UI test (provenance columns + partial index live). The `schema_migrations` row may be unregistered — optional MCP backfill in `docs/importer/PROD_APPLY.md` §B0.2. |
| 009_pins_source_unique_index     | 2026-05-16 | 2026-07-05 (MCP)         | Non-partial `UNIQUE (source, source_external_id)` index the importer's `ON CONFLICT` upsert needs (008's index is partial, which Postgres cannot infer as the conflict arbiter). Additive and app-independent — the shipped app never inserts a non-null `source_external_id`. Apply to prod via MCP (or prod SQL editor) per `docs/importer/PROD_APPLY.md` §B0.2, immediately before the Phase 7 Stage B import. |

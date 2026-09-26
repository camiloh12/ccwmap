# DB Migrations Pipeline — Design

**Date:** 2026-09-26
**Status:** Approved in conversation (flow/security, history cleanup/failure handling, testing/rollout). Awaiting written-spec review.
**Owner:** Camilo Hurtado

## Purpose

Deploy Supabase SQL migrations to staging and prod through GitHub Actions. Today they reach prod by one of two paths:
- the owner pastes them into the prod dashboard SQL editor, or
- Claude re-points the Supabase MCP server at prod (a Claude Code restart) and runs `apply_migration`.

Both keep prod database access on a laptop or in an agent session, both depend on remembering to do it, and neither leaves a reliable record of what prod has applied.

### Goals

1. **Secure:** no laptop and no Claude session needs prod database credentials. The prod credential is reachable only by workflow code already merged to `master`, and every prod change needs the owner's explicit approval in GitHub.
2. **Convenient:** merging a PR that contains a migration starts the deploy. The owner's only step is one Approve click after reading exactly what will be applied.
3. **Tracked:** one authoritative record per environment of which migrations have been applied, when, from which commit and run, and who approved them.

### Non-goals

- **Edge Function deploys.** They also aren't deployed by CI today (prod ran a stale `send-moderation-email` until 2026-09-24), but they are a separate follow-up.
- **Rollback / down migrations.** Migrations stay forward-only; mistakes are fixed forward with a new migration.
- **Automatically cleaning up staging drift from abandoned PRs.** The CLI turns it into a hard, visible failure (see Failure handling); fixing it stays a manual `db-repair`.
- **Changing how migrations are written.** The `NNN_name.sql` numbering and the idempotent-by-convention rule stay as they are.

## Decisions (owner, 2026-09-26)

| Decision | Choice |
|---|---|
| Trigger | **Merge + approve.** Merging to `master` starts the deploy, which pauses for the owner's approval. A manual "Run workflow" deploys anything still pending. |
| Tool | **Supabase CLI** (`supabase db push`), pinned version. Fall back to a custom `psql` runner only if the initial staging test shows the CLI can't work with this repo. |
| Staging | Moves onto the same CLI and history table, so every staging apply rehearses the prod run. |

## Current state

- **Existing workflow.** `.github/workflows/supabase-migration-validate.yml` runs on PRs that touch `supabase/migrations/**`. It applies each *added* file to staging with `psql` (not recorded in any history). Its prod drift check has never run, because `PROD_DB_URL` doesn't exist and the step skips itself.
- **Secrets.** `STAGING_DB_URL` exists as a repo secret (session pooler). There is no prod database URL secret. The GitHub environments are `github-pages` only.
- **Recorded history is inconsistent** (`supabase_migrations.schema_migrations`):
  - **Prod:** 000–007 were applied through the dashboard and never recorded. 008, 009 and 010 are recorded under MCP-generated timestamp versions (e.g. `20260705144447`). 011 was probably never run on prod; it is a guarded no-op there.
  - **Staging:** 000–009 were applied by bootstrap or `psql` and never recorded. 010, 011 and 012 are recorded under MCP timestamp versions.
- **Networking.** GitHub-hosted runners can't reach Supabase's direct DB host (IPv6-only). CI must use the **session-mode pooler**: port 5432, user `postgres.<project_ref>`.
- **Timing rule** (memory `feedback_schema_after_app_release`): a migration that the currently deployed app can't handle must not reach prod until the new app version is released and adopted. The approval gate is where the owner applies this rule.

## Design

### Workflow `db-migrations.yml` (replaces `supabase-migration-validate.yml`)

**Triggers:**
- `pull_request` → `master`, paths: `supabase/migrations/**`, `.github/workflows/db-migrations.yml`, `.github/workflows/db-repair.yml`, `ci/**`.
- `push` → `master`, paths: `supabase/migrations/**`.
- `workflow_dispatch` (no inputs) → runs the same jobs as a push to master (the catch-up deploy).

Workflow-level `permissions: contents: read`. The Supabase CLI is installed with `supabase/setup-cli@v1` at a **pinned version**, chosen during the staging test and recorded in `CLAUDE.md` alongside the Flutter pin.

**Jobs:**

| Job | Runs on | Environment | Needs | Does |
|---|---|---|---|---|
| `workflow-tests` | PR | — | — | Runs `ci/tests/` (workflow structure tests). |
| `staging-pr` | PR | — | `workflow-tests` | For each migration **added by this PR** (`git diff --diff-filter=A origin/master...HEAD`), clears its history row if present (`migration repair --status reverted <v>`). Then `supabase db push --include-all`. Summary: `migration list`. Re-applying the PR's own migrations keeps today's "edit the migration, push again" loop working; this depends on the existing idempotency convention. |
| `staging` | push / dispatch | — | — | `supabase db push --include-all` against staging, so staging always matches `master`. Summary: `migration list`. |
| `plan` | push / dispatch | `production-plan` | `staging` | `supabase db push --include-all --dry-run` against prod. Writes the pending list to the summary ("Pending for prod: …"). Sets output `pending=true/false`. |
| `apply` | push / dispatch, `if: needs.plan.outputs.pending == 'true'` | `production` (**requires owner approval**) | `staging`, `plan` | `supabase db push --include-all` against prod. Summary: `migration list`. |

**Concurrency:**
- Staging jobs share group `db-staging`; prod jobs share `db-prod`.
- `cancel-in-progress: false` for both: an in-flight apply is never cancelled, and later runs queue.

**Why `plan` runs before approval.** Every run applies *everything* pending. If the owner once rejected a breaking migration, the next unrelated merge would carry it along. When the run pauses at `apply`, the `plan` summary on the same run page shows exactly what will be applied, so approving is a deliberate yes to that list. When nothing is pending (for example, a merge that only fixed a comment in an already-applied migration), `apply` is skipped and no approval is requested.

**Where each job's DB URL comes from:**
- `staging-pr` and `staging` read `secrets.STAGING_DB_URL` (repo secret).
- `plan` and `apply` read `secrets.PROD_DB_URL`, which exists **only** as an environment secret.
- No PR-triggered job ever references `PROD_DB_URL`.

### Security model

- **Two environments hold `PROD_DB_URL`** (session-pooler URL: `postgres.gqbxloaqamokbolcvesg@<region>.pooler.supabase.com:5432`):
  - `production-plan`: no reviewers.
  - `production`: required reviewer = owner; "prevent self-review" off (solo developer).
- **Master only.** Both environments have a deployment-branch policy of `master` only. PR branches, including a PR that edits a workflow, can never obtain the prod credential. This matters because the repo is **public**. (Pull requests from forks don't receive secrets either.)
- **No prod credentials outside GitHub.** The owner enters the `PROD_DB_URL` value directly in GitHub; it never passes through Claude.
- **Supabase MCP stays bound to staging.** Claude needs no prod access, and prod changes happen only through the owner's approval.
- **Break-glass:** the owner's dashboard SQL editor stays available for emergencies. After using it, record what was done with `db-repair` (below) so the history table matches reality.

### Workflow `db-repair.yml` (manual)

`workflow_dispatch` inputs:
- `target`: `staging` | `prod`
- `action`: `list` | `applied` | `reverted`
- `versions`: space-separated; required for `applied` / `reverted`

It runs `supabase migration list` or `supabase migration repair --status <action> <versions>`, followed by a `migration list` written to the summary.
- `target: prod` runs in environment `production`, so every prod repair, including `list`, needs the owner's approval.
- `target: staging` uses `STAGING_DB_URL`.

This workflow does the one-time history cleanup and remains the tool for recording emergency hand-fixes. `repair` edits only the history table; it never runs migration SQL.

### Audit trail

- **Prod database:** `supabase_migrations.schema_migrations` is authoritative per environment. The dashboard's Migrations page reads it.
- **GitHub deployment log:** the `production` environment records each deployment's commit, run, approver and time.
- **Run summaries:** every job's summary shows `migration list` (repo vs database).

## One-time history cleanup

1. **Staging** (Claude, during the staging test, via the local CLI against staging only):
   1. `list`.
   2. `reverted` the MCP timestamp versions for 010, 011 and 012.
   3. `applied` `000 004 005 006 007 008 009 010 011 012`.
   4. `list` again. `db push --dry-run` must report nothing pending.
2. **Prod** (after the pipeline merges; each step through `db-repair` with owner approval):
   1. `list`.
   2. `reverted` whatever timestamp versions it shows (expected: 008, 009, 010).
   3. `applied` `000 004 005 006 007 008 009 010`.
   4. `list` again.
3. **First real deploy.** Press "Run workflow" (#55 is already merged; see Rollout step 0). `plan` must show exactly `011, 012`; the owner approves. 011 is a guarded no-op on prod, which makes it a safe end-to-end check of the pipeline immediately before 012 (the BUG-006 fix). Afterwards, run the BUG-006 check query in the prod SQL editor (expected: `locked_cols_updatable=0 user.update_sys=1 user_modified=true user.delete_sys=0 system.update=0`).

## Failure handling

| Situation | Behavior / response |
|---|---|
| A migration's SQL fails | The CLI applies each migration in its own transaction. The failing one rolls back and isn't recorded; earlier ones in the same run stay applied and recorded. The job fails and GitHub notifies the owner. Fix forward with a **new** migration in a PR; never edit an applied migration. |
| Connection or authentication failure | Nothing is applied. Fix the secret or pooler URL and re-run. |
| Approval rejected, or it expires (GitHub fails a waiting job after 30 days) | Nothing is applied. The migration stays pending, reappears in the next `plan`, and "Run workflow" deploys it when ready. |
| Concurrent runs | They queue per environment group; an apply is never cancelled. |
| Staging unreachable or paused | `plan` and `apply` depend on `staging`, so prod waits. Break-glass: dashboard SQL editor, then `db-repair`. (A separate follow-up, the automated daily health check, pings staging daily to prevent pauses.) |
| A statement that can't run inside a transaction (`CREATE INDEX CONCURRENTLY`, `VACUUM`) | Not supported; documented as a convention. |
| The database has recorded a migration the repo doesn't contain | The CLI refuses to push ("Remote migration versions not found in local migrations directory"). This happens in two cases. (a) A PR branch is behind `master` while staging already has a newer migration; fix by merging `master` into the branch. (b) An abandoned PR's migration is still recorded on staging; this blocks every later staging push, and therefore prod, until it's removed with `db-repair` `reverted` on staging (undo its schema by hand if needed). That's loud rather than silent drift, which is intentional. |

## Conventions (documented in `CLAUDE.md` + `docs/dev/STAGING.md`)

1. Migrations reach staging and prod **only** through `db-migrations.yml`. MCP `apply_migration` is not used for repo migrations on either environment, because it records timestamp versions that break the CLI's history.
2. Never edit an applied migration's SQL. Comment-only edits are tolerated: the CLI doesn't checksum, and nothing re-runs an applied version.
3. Keep migrations idempotent (`IF NOT EXISTS`, `CREATE OR REPLACE`, `DROP … IF EXISTS` before `CREATE`). The PR loop re-applies them.
4. No transaction-unsafe statements.
5. A migration that breaks the currently deployed app is **rejected at the approval gate** until the new app version is adopted. The approver checks the `plan` list against this rule.

## Testing

1. **Staging test** (first implementation step; staging only). Run the pinned CLI locally (`npx supabase@<pinned>`) with the staging pooler URL in a local environment variable that is never committed. Confirm:
   - `NNN_name.sql` files parse as versions;
   - whether `supabase/config.toml` is required (commit a minimal one if so);
   - `repair` and `db push --dry-run --include-all` behave as documented.

   Then do the staging history cleanup. This runs after Rollout step 0, with `master` (now containing 012) merged into this branch. **Exit criterion:** `migration list` shows local == remote for 000–012, and `db push --dry-run` reports nothing pending. If the CLI can't work with the repo, stop and bring the fallback (custom `psql` runner) back to the owner.
2. **Workflow structure tests** in `ci/tests/test_db_migrations_workflow.py` (pytest + PyYAML; `uv run --with pytest --with pyyaml pytest ci/tests -q`). They assert:
   - `PROD_DB_URL` appears only in jobs whose `environment` is `production-plan` or `production`;
   - no PR-triggered job references `PROD_DB_URL`;
   - `apply` needs `plan` and `staging` and is gated on `plan`'s `pending` output;
   - prod concurrency never cancels;
   - the CLI version is pinned (not `latest`);
   - `db-repair.yml` routes `target: prod` through environment `production`.

   The same tests run in the `workflow-tests` job, and `.claude/pr-preflight.sh` runs them when `.github/workflows/db-*.yml` or `ci/**` change.
3. **Self-exercise.** The pipeline's own PR triggers `staging-pr` (the path filter includes the workflow file). With staging already cleaned up, the job must succeed and report nothing pending.

## Rollout

0. **Merge PR #55 first** (BUG-006; green). Staging already has 012 applied, and the CLI refuses to push to a database that has recorded a migration the repo lacks. So 012's file must be on `master` before the staging cleanup marks it applied, or the pipeline PR's own `staging-pr` job would fail. #55's merge runs the old `supabase-migration-validate.yml` for the last time (an idempotent `psql` re-apply to staging). Prod does not get 012 until step 6.
1. Staging test + staging history cleanup (Claude, staging only).
2. Implement both workflows, the structure tests, the preflight hook-in, docs; open a PR (the `staging-pr` job exercises staging).
3. **Owner, one-time GitHub setup.** Claude creates the environments via `gh api` with owner consent: `production-plan` (master-only) and `production` (master-only, owner as required reviewer). The owner adds the `PROD_DB_URL` environment secret to both.
4. Merge the pipeline PR. It deletes `supabase-migration-validate.yml`.
5. Prod history cleanup via `db-repair` (owner approves each run). Until this is done, any prod `plan` fails safely: the CLI refuses a history it doesn't recognize, and nothing is applied.
6. First real deploy: "Run workflow" → `011, 012` (see "One-time history cleanup" step 3).

## Docs to update

- `docs/dev/STAGING.md`: rewrite "Applying migrations" (pipeline, `db-repair`, conventions); fix the stale bootstrap check that still names `deny_system_user_writes`.
- `CLAUDE.md`: a "DB migrations pipeline" subsection under CI/CD & Build Flags; the pinned Supabase CLI version; conventions 1–5.
- `docs/dev/GIT_FLOW.md`: a pointer to the DB deploy step.
- `docs/dev/DEPLOY.md`: check it for migration-apply instructions and update any it has.
- Memory: the rule "no MCP `apply_migration` for repo migrations", and the pipeline's existence.

## Risks

| Risk | Mitigation |
|---|---|
| CLI behavior changes between versions | Pinned version; upgrades are a deliberate PR (same policy as the Flutter pin). |
| CLI rejects the repo layout (`NNN_` versions, missing `config.toml`) | The staging test resolves this before any workflow code; the fallback is the custom runner. |
| A mistake in the history cleanup | `repair` touches only the history table; `list` before and after; prod repairs are approval-gated; `db push --dry-run` must match expectations before any real apply. |
| Detecting "pending" from dry-run output is brittle | Structure tests plus the self-exercise run. If parsing proves fragile, compare `migration list` output instead. |
| Approval fatigue | `apply` only asks for approval when `plan` finds something pending. |
| A paused staging blocks prod | The break-glass path is documented. The health-check follow-up keeps staging awake. |

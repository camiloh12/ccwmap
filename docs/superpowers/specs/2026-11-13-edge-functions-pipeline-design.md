# Edge Functions deploy pipeline: design

**Status:** approved by the owner, 2026-11-14.
**Related:** `docs/superpowers/specs/2026-09-26-db-migrations-pipeline-design.md`
(its non-goals list Edge Function deploys as "a separate follow-up"; this is
that follow-up).

## Why

The DB pipeline moved migrations behind GitHub Actions and an approval gate.
Edge Functions never were: `send-moderation-email` and `delete-account` reach
staging and prod only by hand (CLI or MCP). That has already caused real
drift: prod ran an old `send-moderation-email` for weeks, so the monthly Brevo
keepalive failed with a 405 that was misread as a Brevo problem. 0.9.0 needs
the new `send-moderation-email` on prod, and the owner's rule is that every
prod change goes through a pipeline.

## Goals

1. Edge Function code reaches staging and prod only through GitHub Actions.
   Prod waits for the owner's approval in the existing `production`
   environment.
2. It behaves like `db-migrations.yml`:
   - **PR:** deploys the PR's code to staging.
   - **Merge to master:** deploys to staging, then to prod after approval.
   - **Run workflow:** redeploys master the same way.
3. No credential that can write to prod is readable by PR code or by any job
   that hasn't been approved.

## Non-goals

- **Function secrets** (`BREVO_API_KEY` and the like) and **database
  webhooks** stay managed in the dashboard. The pipeline never reads or sets
  them.
- **Drift detection.** Nothing alerts when what's deployed differs from the
  repo. That's a possible later follow-up.
- **Deleting functions.** `--prune` is never used.
- **Local development** of functions.

## Anti-goals (failure even if it "works")

- A deploy silently changes a function's settings. The worst case is turning
  JWT verification off, or on, under the moderation webhook.
- A token shows up in a public Actions log.
- A token that can reach prod sits where PR code can read it.

## Decided

- **Workflow:** `.github/workflows/edge-functions.yml`.
  - Same CLI pin as the DB workflows (`SUPABASE_CLI_VERSION: '2.118.0'`), and
    the same SHA-pinned `supabase/setup-cli`.
  - Deploys with `supabase functions deploy <name> --project-ref <ref>
    --use-api`. `--use-api` bundles on Supabase's side, so there's no Docker.
    It's in 2.118.0 (checked with `--help`).
- **Triggers:**
  - `pull_request` touching `supabase/functions/**`, the workflow file, or
    `ci/**` runs the structure tests, then deploys the PR's code to staging.
  - `push` to master touching `supabase/functions/**` deploys to staging,
    then to prod.
  - `workflow_dispatch` does the same as a push.
- **What gets deployed:** every directory under `supabase/functions/` that has
  an `index.ts` (today `send-moderation-email` and `delete-account`), on
  every run. Redeploying unchanged code is harmless. On its first staging run
  it also creates `delete-account`, which staging has never had.
- **JWT verification.** Both functions run with it on today: confirmed for
  staging's `send-moderation-email` through the API, and per the SP-3 deploy
  notes for `delete-account`.
  - The pipeline deploys with it on: no `--no-verify-jwt`, and no
    `supabase/config.toml`, which could change how the DB workflows' CLI
    calls behave.
  - Before deploying, each job reads the target's current function list and
    stops if any existing function has verification off. A deploy can never
    flip that setting without a person deciding to.
- **Credentials: two scoped personal access tokens.** Scoped tokens have been
  generally available since 2026-10-06 (Supabase changelog), and their prefix
  is `sbp_fc`. Classic full-access tokens now show a "Legacy" badge. Each
  token expires after at most one year, so a yearly rotation goes in
  `docs/dev/DEPLOY.md`.

  | Secret | Scope | Where it lives |
  |---|---|---|
  | `STAGING_SUPABASE_ACCESS_TOKEN` | staging only, Edge Functions read-write | repo secret (PR jobs may read it, like `STAGING_DB_URL`) |
  | `PROD_SUPABASE_ACCESS_TOKEN` | prod only, Edge Functions read-write | `production` environment secret only |

  - Neither token gets the Edge Function Secrets permission.
  - A token for the wrong project fails the pre-deploy read with a 403,
    before anything is written.
- **Fallback if the account can't create scoped tokens yet:**
  - Use one classic token, stored only in `production`.
  - PRs don't deploy to staging.
  - The merge run deploys staging and then prod inside the single approved
    job, staging first, and stops if staging fails.
- **Token hygiene:**
  - Tokens appear only in the env of the steps that call the CLI or the API,
    never at job level.
  - A shape check fails fast without printing the token.
  - `ci/redact.py` learns to mask `sbp_…` strings, and every CLI output goes
    through it. Nothing relies on GitHub's masking (see PR #56).
- **Prod job:**
  - Before approval, the staging job's run summary lists the functions and
    the commit about to go to prod.
  - After the deploy, a smoke check calls `send-moderation-email/health` with
    the existing prod `SUPABASE_URL` / `SUPABASE_ANON_KEY` secrets, which are
    the ones the keepalive uses. A non-200 fails the run.
- **Concurrency:** one group per target, with `cancel-in-progress: false`.
- **Tests:** structure tests in `ci/tests`, in the style of
  `test_db_migrations_workflow.py`. They check that:
  - the CLI pin equals the DB workflows' pin, and setup-cli is SHA-pinned;
  - the prod token appears only in the `production` job;
  - no `${{` appears inside `run:`;
  - there's no `--prune` and no `--no-verify-jwt`;
  - every function directory gets deployed;
  - `redact.py` masks `sbp_` tokens.
- **Docs to update:**
  - `docs/dev/DEPLOY.md` and `docs/dev/MODERATION.md`: replace the manual
    deploy steps.
  - `CLAUDE.md`: workflow list, Edge Functions section, pipeline section.
  - `docs/dev/STAGING.md`.

## First run (unblocks 0.9.0)

1. Merge the pipeline PR. It changes no function, so the push trigger doesn't
   fire.
2. Run the workflow from master. Staging is redeployed, with
   `send-moderation-email` unchanged and `delete-account` new.
3. Approve prod. Prod gets the 0.9.0 `send-moderation-email` and the repo's
   `delete-account`, and `/health` must return 200.
4. Then cut `release/v0.9.0`.

## Left to the builder

- **Does CLI 2.118.0 accept scoped `sbp_fc` tokens?** Prove it on staging
  first. If the CLI rejects them, stop and ask the owner: bumping the pin is
  its own deliberate PR, as the CLAUDE.md rules require. Supabase CLI v3
  (2026-11-04) changed its defaults for hosted projects, so stay on v2.
- **`supabase link`.** Don't use it. Deploy with `--project-ref` only.
  `link` needs extra read permissions (Project Settings, API Keys, API Key
  Secrets).
- **The exact token permissions.** If the deploy needs one more read
  permission than Edge Functions read-write, add the smallest one and write
  it down.
- **The staging smoke check.** For example a staging anon-key secret, or
  skip it.

## Owner prerequisites

- Create the token(s) in Dashboard → Account → Access Tokens, save each to a
  git-ignored file under `.local/`, and set the secrets from those files
  (`gh secret set … < .local/<name>`). Never retype them.

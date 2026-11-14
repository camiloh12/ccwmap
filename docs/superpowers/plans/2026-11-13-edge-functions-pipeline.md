# Edge Functions Deploy Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Edge Functions reach staging and prod only through a GitHub
Actions workflow. Prod deploys wait for the owner's approval.

**Architecture:**
- **The workflow:** `edge-functions.yml`, which mirrors `db-migrations.yml`.
  - **PR:** deploys the PR's code to staging.
  - **Merge or Run workflow:** deploys to staging, then to prod in the
    approval-gated `production` environment.
- **The preflight script:** `ci/functions_preflight.py` (stdlib only) runs
  before each deploy. It:
  - checks the token's shape;
  - finds the functions to deploy;
  - reads the target's deployed functions through the Management API;
  - refuses if any of them has JWT verification off;
  - writes the function list and a run summary.
- **The deploy:** the pinned CLI with `--use-api`, with every output line
  going through `ci/redact.py`. Redact learns to mask access tokens.

**Tech Stack:** GitHub Actions; Supabase CLI 2.118.0 (`supabase/setup-cli`,
pinned by SHA); Python 3 stdlib; pytest and PyYAML for the `ci/tests`
structure tests.

**Spec:** `docs/superpowers/specs/2026-11-13-edge-functions-pipeline-design.md`

## Global Constraints

- **Branch:** `feature/edge-functions-pipeline`, cut from `origin/master`.
  It's a single PR.
- **Project refs:** staging `miihmfhnsfmwgrvgayns`, prod
  `gqbxloaqamokbolcvesg`.
- **Secrets** (they already exist):
  - `STAGING_SUPABASE_ACCESS_TOKEN` is a repo secret.
  - `PROD_SUPABASE_ACCESS_TOKEN` is a secret of the `production` environment
    only.
  - Both are scoped tokens (`sbp_fc…`) with Edge Functions read-write on one
    project.
  - The existing repo secret `SUPABASE_ANON_KEY` is prod's anon key.
- **CLI:** `SUPABASE_CLI_VERSION: '2.118.0'` and the same
  `supabase/setup-cli@<sha>` pin as `db-migrations.yml`. No CLI v3.
- **Deploy command:** `supabase functions deploy <name> --project-ref <ref>
  --use-api`.
  - Never `--prune`, `--no-verify-jwt` or `supabase link`.
  - No `supabase/config.toml`.
- **Secrets handling:**
  - Never print a token.
  - Never put `${{ … }}` inside a `run:` block. Values reach scripts through
    step `env:` only.
  - Tokens go only in the env of steps that run the preflight or the CLI,
    never at job level.
- **Out of scope:** function secrets and database webhooks stay in the
  dashboard. The pipeline never reads or sets them.
- **Checks to keep green:**
  - `uv run --no-project --with pytest --with pyyaml pytest ci/tests | tail -1`
    passes. The baseline is 180 on master; confirm it before you start.
  - No app or importer code changes.
- **Commit trailers.** Every commit message ends with exactly:
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_015kWv7bjy4M1h8uYXiTST23
  ```
  Subagents have rewritten this trailer before, so check every commit.
- **Pasteable commands** for the owner stay at 70 characters or fewer per
  line.

## Plan refinements (deliberate departures from the spec)

1. **The JWT check covers only the functions about to be deployed.** The
   spec said "any existing function". A function that exists on the project
   but not in the repo is never touched by a deploy, so its setting can't
   flip.
2. **No staging smoke check** (the spec left this to the builder). There's
   no staging anon-key secret. A green staging deploy plus the owner's
   checks on staging are enough. Prod has the `/health` smoke check.
3. **Classic tokens are refused.** The preflight rejects any token without
   the `sbp_fc` prefix, which enforces the spec's "no account-wide token in
   CI". The spec's classic-token fallback is dropped: scoped tokens are
   generally available and both are already set.

## Review Focus

1. **CLI 2.118.0 rejects the scoped token, or needs more permission than
   Edge Functions read-write.** The PR's own `staging-pr` run is the first
   real test. Stop and report the redacted error to the owner. Scopes are
   fixed at creation, so the owner would create a replacement token.
   Covered by Task 5, step 2.
2. **A deploy fails partway** (the first function is deployed, the second
   fails). The step must stop red at the first failure, not carry on and
   report success. Covered by
   `test_deploy_loop_stops_at_the_first_failure` (Task 3).
3. **The prod `/health` call fails because of Brevo, not the deploy.** The
   error must say so, so nobody redeploys or rolls back by mistake. Covered
   by `test_smoke_check_names_brevo_on_failure` (Task 3).
4. **A non-function folder under `supabase/functions/`** (for example
   `_shared/`, or a folder with no `index.ts`) must never be deployed.
   Covered by `test_local_functions_skips_shared_and_incomplete_dirs`
   (Task 2).
5. **A wrong-project or missing token** must fail before any write, with a
   message that names the fix and never shows the token. Covered by
   `test_list_deployed_403_names_target_not_token` and
   `test_main_refuses_classic_token_before_any_http` (Task 2).

---

### Task 1: Redact masks access tokens

**Files:**
- Modify: `ci/redact.py`
- Test: `ci/tests/test_redact.py`

**Interfaces:**
- Produces: `redact(text: str, db_url: str | None, access_token: str | None
  = None) -> str`.
  - `main()` also reads `SUPABASE_ACCESS_TOKEN` from the environment.
  - Any `sbp_[A-Za-z0-9_]+` is replaced with `<access-token>`.
  - Existing callers that pass two arguments keep working.

- [ ] **Step 1: Write the failing tests** in `ci/tests/test_redact.py`:
  - `test_any_access_token_is_redacted_without_knowing_it`:
    `redact("Using token sbp_fc0123abcd_XYZ for deploy", None) ==
    "Using token <access-token> for deploy"`.
  - `test_exact_access_token_is_redacted_even_if_malformed`: with
    `access_token=" sbp_fc!!odd "`, the output contains neither `sbp_fc!!odd`
    nor `!!odd`.
  - `test_filter_mode_reads_access_token_from_env`: run `python ci/redact.py`
    as a subprocess with `SUPABASE_ACCESS_TOKEN=tok-not-sbp-shaped` in its
    env, feed it `"x tok-not-sbp-shaped y\n"`, and expect `"x *** y\n"`. Use
    the pattern of the existing `test_filter_mode_reads_db_url_from_env`.
  - `test_ordinary_output_is_untouched` still passes, and add a
    function-deploy line to it: `"Deployed Functions on project
    miihmfhnsfmwgrvgayns: send-moderation-email\n"` is unchanged.

- [ ] **Step 2: Run the tests** to see them fail.
  Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_redact.py -q`
  Expected: the three new tests FAIL.

- [ ] **Step 3: Implement.**
  - Replace the exact token's variants (raw and stripped, at least
    `_MIN_SECRET_LEN` long) with `***`, as is done for `db_url`.
  - Then apply the `sbp_` regex.
  - Update the module docstring.

- [ ] **Step 4: Run the full CI suite.**
  Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests | tail -1`
  Expected: all pass.

- [ ] **Step 5: Commit.**
  ```bash
  git add ci/redact.py ci/tests/test_redact.py
  git commit -m "feat(ci): redact Supabase access tokens"
  ```

### Task 2: Functions preflight script

**Files:**
- Create: `ci/functions_preflight.py`
- Test: `ci/tests/test_functions_preflight.py`

**Interfaces:**
- Produces (all in `ci/functions_preflight.py`):
  - `PROJECT_REFS = {"staging": "miihmfhnsfmwgrvgayns", "prod":
    "gqbxloaqamokbolcvesg"}`.
  - `class PreflightError(Exception)`.
  - `token_problems(token: str) -> list[str]`. It returns readable problems
    and never includes any part of the token:
    - `"is empty"`;
    - `"contains whitespace (a newline from pasting?)"`;
    - `"is not a scoped token (expected the sbp_fc prefix; classic
      full-access tokens are refused)"`;
    - `"has unexpected characters"` for anything outside `[A-Za-z0-9_]`.
  - `local_functions(functions_dir: Path) -> list[str]`: sorted names of the
    folders that contain an `index.ts`, skipping names that start with `_`.
  - `list_deployed(target: str, token: str, get=None) -> list[dict]`.
    - It GETs `https://api.supabase.com/v1/projects/{ref}/functions` with
      `Authorization: Bearer <token>` and `User-Agent: ccwmap-ci`.
    - `get(url, headers) -> tuple[int, bytes]` defaults to the module-level
      `_http_get(url: str, headers: dict[str, str]) -> tuple[int, bytes]`,
      a urllib helper like `ci/resolve_pin_report.py::_http_post` that
      returns `(e.code, e.read())` on an `HTTPError`.
    - A non-200 response raises `PreflightError(f"cannot list {target}
      functions (HTTP {status}): the token must be scoped to the {target}
      project with Edge Functions read-write")`. The response body is never
      included.
  - `jwt_off(deployed: list[dict], names: list[str]) -> list[str]`: the
    sorted slugs in `names` that are deployed with `verify_jwt` false.
  - `render_summary(target: str, names: list[str], deployed: list[dict],
    sha: str) -> str`. It renders markdown:
    - a heading `### Edge Functions → {target}`;
    - a table `| Function | Deployed now | After this run |`, where "Deployed
      now" is `v{version}` or `not deployed` and "After this run" is the
      commit `sha[:7]`.
  - `main(argv: list[str] | None = None) -> int`.
    - `argv[0]` is the target. It reads `SUPABASE_ACCESS_TOKEN` and
      `GITHUB_SHA` from the environment.
    - It writes `functions=<names joined by spaces>` to the file named by
      `$GITHUB_OUTPUT` and appends the summary to `$GITHUB_STEP_SUMMARY`,
      each when that variable is set.
    - Every problem prints `::error::{label} {problem}`. It returns 0 or 1.
    - `ROOT = Path(__file__).resolve().parents[1]`, and the functions folder
      is `ROOT / "supabase" / "functions"`.

- [ ] **Step 1: Write the failing tests** in
  `ci/tests/test_functions_preflight.py`. Use `import functions_preflight as
  fp` (conftest already puts `ci/` on the path) and a fake `get` that
  records calls.
  - `test_token_problems_accepts_a_scoped_token`:
    `fp.token_problems("sbp_fc" + "a" * 38) == []`.
  - `test_token_problems_refuses_classic_and_malformed_tokens`:
    - `"sbp_" + "a" * 40` gives the "not a scoped token" problem;
    - `""` gives `["is empty"]`;
    - `"sbp_fcabc\n"` includes the whitespace problem;
    - `"sbp_fc-a"` includes the characters problem;
    - the token text never appears in any message.
  - `test_local_functions_skips_shared_and_incomplete_dirs`: in `tmp_path`,
    create `b-fn/index.ts`, `a-fn/index.ts`, `_shared/index.ts` and
    `no-entry/deno.json`. The result is `["a-fn", "b-fn"]`.
  - `test_list_deployed_calls_the_target_project`: the fake returns
    `(200, b'[{"slug":"x","version":3,"verify_jwt":true}]')`. The URL ends
    with `/v1/projects/miihmfhnsfmwgrvgayns/functions`, the header is
    `Bearer sbp_fcTOKEN`, and the parsed list comes back.
  - `test_list_deployed_403_names_target_not_token`: the fake returns
    `(403, b'{"message":"forbidden sbp_fcTOKEN"}')`. It raises
    `PreflightError`, the message contains `"prod"` and `"HTTP 403"`, and it
    contains no `"sbp_fc"`.
  - `test_jwt_off_only_checks_functions_about_to_deploy`: deployed `[{a,
    jwt false}, {b, jwt true}, {c, jwt false}]` with names `["a", "b"]`
    gives `["a"]`.
  - `test_render_summary_marks_new_functions`: names `["a", "b"]`, deployed
    `[{a, version 7}]`, sha `"abcdef1234"`. The table has a row
    `| a | v7 | abcdef1 |` and a row `| b | not deployed | abcdef1 |`.
  - `test_main_writes_functions_output_and_summary`: monkeypatch the env
    (token, `GITHUB_SHA`, `GITHUB_OUTPUT` and `GITHUB_STEP_SUMMARY` pointing
    at tmp files), `fp.ROOT` (pointing at a tmp tree with two functions) and
    `fp._http_get` (the fake, 200). `main(["staging"]) == 0`, the output
    file contains `functions=a-fn b-fn`, and the summary file contains
    `### Edge Functions → staging` but not the token.
  - `test_main_refuses_classic_token_before_any_http`: a classic token gives
    `main(["prod"]) == 1`, the fake was never called, and the stdout from
    `capsys` contains `::error::` but not the token.
  - `test_main_refuses_when_jwt_is_off`: the fake says `a-fn` is deployed
    with `verify_jwt` false. `main` returns 1 and stdout names `a-fn`.
  - `test_main_rejects_unknown_target`: `main(["dev"]) == 1`.

- [ ] **Step 2: Run the tests** to see them fail.
  Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_functions_preflight.py -q`
  Expected: FAIL with `ModuleNotFoundError: functions_preflight`.

- [ ] **Step 3: Implement** `ci/functions_preflight.py` to the Interfaces
  above.
  - Give it a module docstring with its usage line, `SUPABASE_ACCESS_TOKEN=…
    python3 ci/functions_preflight.py staging`, and its purpose.
  - Use the stdlib only.

- [ ] **Step 4: Run the full CI suite.**
  Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests | tail -1`
  Expected: all pass.

- [ ] **Step 5: Commit.**
  ```bash
  git add ci/functions_preflight.py ci/tests/test_functions_preflight.py
  git commit -m "feat(ci): preflight checks for Edge Function deploys"
  ```

### Task 3: The edge-functions workflow

**Files:**
- Create: `.github/workflows/edge-functions.yml`
- Test: `ci/tests/test_edge_functions_workflow.py`

**Interfaces:**
- Consumes:
  - `python3 ci/functions_preflight.py <staging|prod>`, with
    `SUPABASE_ACCESS_TOKEN` in the step env. It sets the step output
    `functions` (Task 2), and `PROJECT_REFS` holds the refs.
  - `ci/redact.py`, which reads `SUPABASE_ACCESS_TOKEN` (Task 1).
- Produces: the workflow `name: Edge Functions`, with jobs `workflow-tests`,
  `staging-pr`, `staging` and `prod`.

**The workflow's shape:**
- **Top level:**
  - Triggers:
    - `pull_request` to `master`, with paths `supabase/functions/**`,
      `.github/workflows/edge-functions.yml` and `ci/**`;
    - `push` to `master`, with paths `supabase/functions/**`;
    - `workflow_dispatch`.
  - `permissions: {contents: read}`.
  - `defaults.run.shell: bash`.
  - `env.SUPABASE_CLI_VERSION: '2.118.0'`.
  - A header comment like `db-migrations.yml`'s: what runs when, where each
    token lives, and the spec path.
- **`workflow-tests`** (PR only): checkout, setup-uv, then run `ci/tests`, as
  in `db-migrations.yml`.
- **`staging-pr`** (PR only):
  - `needs: workflow-tests`; concurrency group `functions-staging`.
  - Steps: checkout, setup-cli (the SHA pin, `version: ${{
    env.SUPABASE_CLI_VERSION }}`), Preflight (`id: preflight`), Deploy.
  - Both the Preflight and the Deploy step get `SUPABASE_ACCESS_TOKEN: ${{
    secrets.STAGING_SUPABASE_ACCESS_TOKEN }}`. The Deploy step also gets
    `PROJECT_REF: miihmfhnsfmwgrvgayns` and `FUNCTIONS: ${{
    steps.preflight.outputs.functions }}`.
  - Deploy runs:
    ```bash
    set -euo pipefail
    for fn in $FUNCTIONS; do
      supabase functions deploy "$fn" --project-ref "$PROJECT_REF" --use-api 2>&1 | python3 ci/redact.py
    done
    ```
- **`staging`** (not on PRs): the same steps as `staging-pr`, with
  concurrency group `functions-staging-deploy`.
- **`prod`** (not on PRs):
  - `needs: staging`, `environment: production`, concurrency group
    `functions-prod-deploy`.
  - The same steps, with `PROD_SUPABASE_ACCESS_TOKEN` and `PROJECT_REF:
    gqbxloaqamokbolcvesg`, then a **Smoke check** step.
  - The smoke check's env is `HEALTH_URL:
    https://gqbxloaqamokbolcvesg.supabase.co/functions/v1/send-moderation-email/health`
    and `ANON_KEY: ${{ secrets.SUPABASE_ANON_KEY }}`.
  - It tries up to 3 times, 10 s apart, with `curl` and `--max-time 30`, and
    succeeds on HTTP 200.
  - On a final failure it prints the status and the body (as
    `brevo-keepalive.yml` does), then `::error::send-moderation-email
    deployed, but /health returned <code>. A 401 from Brevo means the
    BREVO_API_KEY function secret, not this deploy: see
    brevo-keepalive.yml.`, and exits 1.
- **All concurrency groups** use `cancel-in-progress: false`.

- [ ] **Step 1: Write the failing tests** in
  `ci/tests/test_edge_functions_workflow.py`, in the style of
  `test_db_migrations_workflow.py` (reuse its `_on`, `_text` and `_runs`
  helper patterns locally).
  - `test_triggers`: the PR paths, the push paths (`== ["supabase/functions/**"]`)
    and `workflow_dispatch` are as above.
  - `test_permissions_read_only` and `test_shell_uses_pipefail` (defaults ==
    `{"run": {"shell": "bash"}}`).
  - `test_pr_jobs_never_touch_prod`: the PR-only jobs are exactly
    `{"workflow-tests", "staging-pr"}`, neither has an `environment`, and
    neither mentions `PROD_SUPABASE_ACCESS_TOKEN` or `gqbxloaqamokbolcvesg`.
  - `test_deploy_jobs_never_run_on_pull_request`: `staging` and `prod` both
    have `if` containing `github.event_name != 'pull_request'`.
  - `test_prod_token_only_in_the_gated_prod_job`: every job that mentions
    `PROD_SUPABASE_ACCESS_TOKEN` is `prod`, which has `environment:
    production` and `needs: staging`. `prod` never mentions
    `STAGING_SUPABASE_ACCESS_TOKEN`.
  - `test_tokens_only_on_preflight_and_deploy_steps`: no job-level env
    mentions a token. A step has `SUPABASE_ACCESS_TOKEN` in its env exactly
    when its `run` contains `ci/functions_preflight.py` or `supabase
    functions deploy`.
  - `test_preflight_runs_before_deploy`: in each of `staging-pr`, `staging`
    and `prod`, the step with `id: preflight` comes before the deploy step,
    and the deploy step's `FUNCTIONS` env is `${{
    steps.preflight.outputs.functions }}`.
  - `test_project_refs_match_preflight`: each job's `PROJECT_REF` equals
    `functions_preflight.PROJECT_REFS` for its target, and the preflight
    argument matches (`staging` for both staging jobs, `prod` for prod).
  - `test_deploy_command_is_safe`: every line with `supabase functions
    deploy` contains `--use-api`, `--project-ref "$PROJECT_REF"` and `|
    python3 ci/redact.py`. Nowhere in the workflow text does `--prune`,
    `--no-verify-jwt` or `supabase link` appear, and
    `supabase/config.toml` doesn't exist. A config file could change how
    the CLI behaves in the DB workflows too.
  - `test_deploy_loop_stops_at_the_first_failure`: each deploy step's `run`
    starts with `set -euo pipefail`, and the job uses the bash default
    (pipefail), so a failed deploy piped through redact still fails the
    step.
  - `test_no_expressions_inside_run`: no step's `run` contains `${{`.
  - `test_cli_pin_matches_db_migrations`: `SUPABASE_CLI_VERSION` and every
    setup-cli `uses:` string equal `db-migrations.yml`'s, and each `with:
    version` is `${{ env.SUPABASE_CLI_VERSION }}`.
  - `test_concurrency_never_cancels_and_is_own`: the groups are
    `functions-staging`, `functions-staging-deploy` and
    `functions-prod-deploy`, each with `cancel-in-progress: False`. No job
    in `db-migrations.yml` or `db-repair.yml` uses these groups.
  - `test_smoke_check_after_prod_deploy`: the last step of `prod` has
    `HEALTH_URL` containing `gqbxloaqamokbolcvesg` and
    `/send-moderation-email/health`, has no `SUPABASE_ACCESS_TOKEN`, and
    gets `ANON_KEY` from `secrets.SUPABASE_ANON_KEY`.
  - `test_smoke_check_names_brevo_on_failure`: the smoke step's `run`
    contains `BREVO_API_KEY` and `brevo-keepalive.yml` in its `::error::`
    line, and retries (it contains a loop with `sleep 10`).

- [ ] **Step 2: Run the tests** to see them fail.
  Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests/test_edge_functions_workflow.py -q`
  Expected: FAIL with `FileNotFoundError` for `edge-functions.yml`.

- [ ] **Step 3: Write `.github/workflows/edge-functions.yml`** to the shape
  above.

- [ ] **Step 4: Run the full CI suite.**
  Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests | tail -1`
  Expected: all pass.

- [ ] **Step 5: Commit.**
  ```bash
  git add .github/workflows/edge-functions.yml \
          ci/tests/test_edge_functions_workflow.py
  git commit -m "feat(ci): Edge Functions deploy workflow"
  ```

### Task 4: Docs

**Files:**
- Modify: `docs/dev/DEPLOY.md`, `docs/dev/MODERATION.md`,
  `docs/dev/STAGING.md`, `CLAUDE.md`,
  `docs/superpowers/specs/2026-11-13-edge-functions-pipeline-design.md`
  (set Status to "approved 2026-11-14").

- [ ] **Step 1: `DEPLOY.md`.** Replace the manual `supabase functions deploy`
  steps with an "Edge Functions" section. It covers:
  - **What triggers a deploy:** a PR deploys to staging; a merge or Run
    workflow deploys staging, then prod after approval.
  - **What the run summary shows.**
  - **What the smoke check means.**
  - **Yearly token rotation:**
    1. Create a scoped token: one project, Edge Functions read-write, one
       year.
    2. Save it with the clipboard commands below.
    3. Load it with `gh secret set … < .local/…`.
    4. Delete the old token in the dashboard.
  - **Break-glass:** a hand deploy is for emergencies only. Merge the same
    code right after, so the next pipeline run matches.

  The clipboard commands, with each line 70 characters or fewer:
  ```
  Get-Clipboard | Set-Content -NoNewline -Encoding ascii `
    .local\prod_supabase_access_token
  Set-Clipboard -Value $null
  ```

- [ ] **Step 2: `MODERATION.md`.** Replace the "Deploying the Edge Function
  by hand" block with one paragraph that points to the workflow and to
  `DEPLOY.md`.

- [ ] **Step 3: `STAGING.md`.** Add a short "Edge Functions" note: PRs that
  touch `supabase/functions/**` deploy to staging through `edge-functions.yml`.

- [ ] **Step 4: `CLAUDE.md`.**
  - **Workflow list:** add the `edge-functions.yml` bullet to the "CI/CD &
    Build Flags" list.
  - **Edge Functions section:** say that deploys go through
    `edge-functions.yml` (scoped tokens, prod gated), not by hand.
  - **Status line:** in the v0.9.0 sentence, replace "Edge Function deploy
    is manual" with the workflow.
  - **Test count:** set the CI structure test count to what the suite prints
    now.

- [ ] **Step 5: Run the CI suite and a link sanity check.**
  Run: `uv run --no-project --with pytest --with pyyaml pytest ci/tests | tail -1`
  Expected: all pass.
  Run: `grep -rn "functions deploy" docs/dev CLAUDE.md`
  Expected: only the break-glass example in `DEPLOY.md`.

- [ ] **Step 6: Commit.**
  ```bash
  git add docs CLAUDE.md
  git commit -m "docs: Edge Functions deploy through edge-functions.yml"
  ```

### Task 5: Prove it on staging, then the first prod deploy (controller and owner)

Each step acts on a shared system.

- [ ] **Step 1: Push the branch and open a PR to `master`.** The PR touches
  `ci/**` and the workflow, so `staging-pr` runs. It deploys the repo's
  functions to staging with the scoped token: the first real test.
- [ ] **Step 2: Check the run.**
  - **If it's green:** the CLI accepted the `sbp_fc` token and the
    permissions are enough. Through the staging MCP `list_edge_functions`,
    confirm `send-moderation-email` has a new version and `delete-account`
    now exists, both with `verify_jwt: true`.
  - **If it's red:** read the redacted log and stop. Report to the owner:
    1. a token-format rejection means bumping the CLI pin, which is its own
       PR;
    2. a 403 on deploy means a missing permission, so name the smallest
       extra one, and the owner creates a replacement token.
- [ ] **Step 3: Owner merges.** The merge touches no function, so the push
  trigger doesn't fire.
- [ ] **Step 4: Owner runs the workflow.** Actions → Edge Functions → Run
  workflow on `master`.
  - `staging` deploys. Its summary lists the functions and the commit, which
    is what the owner approves.
  - `prod` waits for approval.
  - After approval, prod's own summary shows the versions it replaced
    (expected: `send-moderation-email` v7, `delete-account` v3). The smoke
    check must pass with HTTP 200.
- [ ] **Step 5: Verify prod.** Run a read-only check with
  `.local/prod_supabase_access_token`, using Python urllib as in the token
  check of 2026-11-14 and never printing the token. Both functions should
  have new versions with `verify_jwt` true.
- [ ] **Step 6: Record it.** Put the run id and the new versions in the PR,
  in `CLAUDE.md` if needed, and in memory. Then 0.9.0 continues with
  `release/v0.9.0`.

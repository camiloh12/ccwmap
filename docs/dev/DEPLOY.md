# Deploying Supabase Edge Functions

Edge Functions (`supabase/functions/*`) reach staging and prod **only**
through the `edge-functions.yml` GitHub Actions workflow, the same way
migrations go through `db-migrations.yml`. Never deploy one by hand, except
in the break-glass case below. Design:
`docs/superpowers/specs/2026-11-13-edge-functions-pipeline-design.md`.

## How a deploy runs

| When | Workflow → jobs | Target |
|---|---|---|
| PR touching `supabase/functions/**`, `ci/**` or `edge-functions.yml` | `workflow-tests` → `staging-pr` | staging (the PR's code) |
| Merge to `master` touching `supabase/functions/**`, or **Run workflow** | `staging` → `prod` | staging, then prod after **owner approval** in `production` |

Each deploy job runs three steps:

1. **Preflight** (`ci/functions_preflight.py`). It:
   - refuses any token that isn't a scoped token (`sbp_fc…`);
   - lists the project's deployed functions, so a token for the wrong project
     fails here with a 403, before anything is written;
   - refuses if a function it's about to deploy has JWT verification off.
     The workflow deploys with verification on, so that case is yours to
     decide by hand.

   Its run summary shows each function's current version and the commit
   going out.
2. **Deploy.** The pinned CLI (2.118.0, `--use-api`, so Supabase bundles it
   and there's no Docker) deploys every folder under `supabase/functions/`
   that has an `index.ts`. All output goes through `ci/redact.py`.
3. **Smoke check (prod only).** It calls `send-moderation-email/health` with
   the anon key, and needs a 200 within 3 tries. A Brevo `401` there points
   at the `BREVO_API_KEY` function secret, not at the deploy.

**Approving prod.** The run pauses at `Deploy to prod`. Read the `Deploy to
staging` job's summary (the functions and the commit), then approve the
`production` environment. Rejecting leaves prod unchanged; **Run workflow**
deploys it later.

Function secrets (below) and the database webhooks are **not** managed by the
workflow. They stay in the dashboard.

## Access tokens

| Secret | Scope | Where it lives |
|---|---|---|
| `STAGING_SUPABASE_ACCESS_TOKEN` | staging project only, Edge Functions read-write | repo secret |
| `PROD_SUPABASE_ACCESS_TOKEN` | prod project only, Edge Functions read-write | `production` environment secret only |

Both are scoped personal access tokens, and they expire after at most a year.
The expiry date is on https://supabase.com/dashboard/account/tokens. To
rotate one before it expires:

1. Generate a new token on that page:
   - name: `github-actions-functions-<staging|prod>`;
   - expiry: 1 year;
   - scope: that one project;
   - permissions: **Edge Functions → Read-write** only. Leave Edge Function
     Secrets off.

   The review screen must list nothing else.
2. Click copy, then save it from PowerShell at the repo root, without pasting
   it anywhere:
   ```
   Get-Clipboard | Set-Content -NoNewline -Encoding ascii `
     .local\prod_supabase_access_token
   Set-Clipboard -Value $null
   ```
3. Load it into GitHub from the file (Git Bash):
   ```
   gh secret set PROD_SUPABASE_ACCESS_TOKEN --env production \
     < .local/prod_supabase_access_token
   ```
   For staging, the secret is a repo secret (no `--env`):
   `gh secret set STAGING_SUPABASE_ACCESS_TOKEN` with input from
   `.local/staging_supabase_access_token`.
4. Run the workflow to prove the new token works, then delete the old token
   on the tokens page.

## Break-glass: deploying by hand

Use this only when prod is broken and the workflow can't run. Afterwards,
merge exactly the deployed code to `master` straight away, so the next
pipeline run deploys what's already live.

```
npx supabase@2.118.0 login
npx supabase@2.118.0 functions deploy send-moderation-email \
  --project-ref gqbxloaqamokbolcvesg --use-api
```

## Function secrets (one-time, by hand)

Set these per project in the dashboard (Edge Functions → Secrets), or with the
CLI after `supabase login` and `supabase link --project-ref <project-ref>`:

```bash
supabase secrets set BREVO_API_KEY=<api-key>
supabase secrets set MOD_FROM=moderation@kyberneticlabs.com
supabase secrets set MOD_FROM_NAME="CCW Map Moderation"
supabase secrets set MOD_TO=camilo@kyberneticlabs.com
```

The sender address (`MOD_FROM`) must be on a domain verified in Brevo.
`@kyberneticlabs.com` is already verified.

The invocation URL is
`https://<project-ref>.supabase.co/functions/v1/<function-name>`.

## Moderation email health check

`send-moderation-email` exposes a `/health` sub-path that verifies
`BREVO_API_KEY` still authenticates against Brevo's read-only `/v3/account`
endpoint. No email is sent and no credits are consumed.

```bash
curl -H "Authorization: Bearer <anon-key>" \
  "https://<project-ref>.supabase.co/functions/v1/send-moderation-email/health"
# → {"ok":true,"check":"brevo-account","status":200,...}

# Add ?send=1 to also send a real heartbeat email — this exercises the whole
# path (key + verified sender + credits), not just authentication.
```

`.github/workflows/brevo-keepalive.yml` calls this on the 1st of each month.
That is not only monitoring: **Brevo deactivates API keys after 3 months with
no API calls**, and moderation traffic is naturally near-zero, so a healthy key
looks abandoned. The monthly call resets that clock. On failure the workflow
goes red and opens a deduped `security`-labelled issue.

Do not silence or delete that workflow without replacing the keep-alive. The
original `ccwmap-mod` key was deactivated exactly this way, and the failure was
invisible: reports and blocks kept writing to the database, the webhook kept
firing, and the function kept 500ing on a `401` while no email reached anyone.

### Rotating the Brevo key

1. Brevo → SMTP & API → API Keys → generate a new key.
2. `supabase link --project-ref <prod-ref>` (the function is deployed to prod only).
3. `supabase secrets set BREVO_API_KEY=<new-key>`
4. Actions → **Edge Functions** → Run workflow on `master`, and approve prod.
   The redeploy forces a cold boot so the new secret is picked up, and the
   prod smoke check calls `/health` for you. The boot log line reports the
   key length.
5. Hit `/health` (above) and confirm `200`, then delete the old key in Brevo.
6. After an outage, check `pin_reports` and `blocked_users` for rows created
   while the key was dead — those alerts were never delivered.

The key is a Brevo **REST API key** (`xkeysib-…`), used only by this function.
It is unrelated to Supabase Auth's signup/password-reset email, which goes
through GoTrue's SMTP settings. Keep it out of the app's root `.env`, which is a
bundled Flutter asset (`pubspec.yaml` → `assets: - .env`).

## Migrations

Migrations under `supabase/migrations/*.sql` are deployed by the
`db-migrations.yml` GitHub Actions pipeline: staging on every PR, prod after
merge once the owner approves the `apply` job. Never apply them by hand. See
`docs/dev/STAGING.md` → "Applying migrations".

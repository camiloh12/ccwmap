# Deploying Supabase Edge Functions

Manual deploy process. Auto-deploy via GitHub Actions is a future enhancement.

## Prerequisites

- Supabase CLI installed: `npm i -g supabase` (or `brew install supabase/tap/supabase`).
- Logged in: `supabase login`.
- Linked: `supabase link --project-ref <project-ref>`.

## First-time setup (secrets)

```bash
supabase secrets set BREVO_API_KEY=<api-key>
supabase secrets set MOD_FROM=moderation@kyberneticlabs.com
supabase secrets set MOD_FROM_NAME="CCW Map Moderation"
supabase secrets set MOD_TO=camilo@kyberneticlabs.com
```

The sender address (`MOD_FROM`) must be on a domain verified in Brevo.
`@kyberneticlabs.com` is already verified.

## Deploy a function

```bash
supabase functions deploy send-moderation-email
supabase functions deploy delete-account
```

Confirm deployment in Studio → Edge Functions. The invocation URL is
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
4. `supabase functions deploy send-moderation-email` — forces a cold boot so the
   new secret is picked up. The boot log line reports the key length.
5. Hit `/health` (above) and confirm `200`, then delete the old key in Brevo.
6. After an outage, check `pin_reports` and `blocked_users` for rows created
   while the key was dead — those alerts were never delivered.

The key is a Brevo **REST API key** (`xkeysib-…`), used only by this function.
It is unrelated to Supabase Auth's signup/password-reset email, which goes
through GoTrue's SMTP settings. Keep it out of the app's root `.env`, which is a
bundled Flutter asset (`pubspec.yaml` → `assets: - .env`).

## Migrations

Migrations under `supabase/migrations/*.sql` are applied manually in SQL
editor for v0.4.0 (or via `supabase db push` if the project is linked).
Always apply in numeric order. Verify via the table / constraint checks
in the plan for each migration.

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
supabase functions deploy delete-account     # once SP-3 lands
```

Confirm deployment in Studio → Edge Functions. The invocation URL is
`https://<project-ref>.supabase.co/functions/v1/<function-name>`.

## Migrations

Migrations under `supabase/migrations/*.sql` are applied manually in SQL
editor for v0.4.0 (or via `supabase db push` if the project is linked).
Always apply in numeric order. Verify via the table / constraint checks
in the plan for each migration.

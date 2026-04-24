# iOS App Store Rejection Response — Design Spec

## Context

Apple rejected the production submission of CCW Map on three guidelines:

- **5.1.1(v)** — requires account registration for non-account features (map browsing).
- **5.1.1(v)** — no in-app account deletion path.
- **1.2** — user-generated content without required precautions (EULA, report, block, 24h moderation SLA).

All three must be fixed in one release. Apple re-reviews the whole submission on resubmit, so shipping partial fixes burns review cycles unnecessarily. Target release: `v0.4.0` from branch `feature/ios-rejection`.

## Decomposition

The three rejections are nearly-independent subsystems sharing one widget (the Settings screen). Each is its own sub-project with its own implementation plan:

| Sub-project | Scope | Est. effort |
|---|---|---|
| **SP-1** | Anonymous map access (client-only routing change) | 1–2 days |
| **SP-2** | UGC precautions (EULA, report, block, name constraints, moderation plumbing) | 3–4 days |
| **SP-3** | Account deletion (Edge Function, schema migration, Settings screen) | 2–3 days |

**Build order:** SP-1 → SP-2 → SP-3. SP-1 first because it's smallest and unblocks visual testing of the others against production-shaped UX. SP-2 before SP-3 because the Resend/webhook/Edge-Function infrastructure from SP-2 establishes patterns SP-3 reuses.

**Ship together in one `release/v0.4.0`.**

---

## Cross-cutting decisions

All agreed during brainstorm (2026-04-24):

| Decision | Choice |
|---|---|
| Support / contact email | `camilo@kyberneticlabs.com` for all public-facing uses (EULA, ban-appeal text, App Store Connect support URL, moderation webhook destination) — **not** the personal gmail. |
| Rejection 1.2 approach | Fix all four required precautions. No appeal. The app has a real UGC surface (free-text pin `name` field visible to all users), so "no UGC" argument is factually false. |
| Name-field constraints | Length cap (60 chars) + minimal custom profanity filter (~30-word deny-list, case-insensitive substring match). Obvious bypasses tolerated — the report mechanism is the real defense. |
| Blocking semantics | Block-by-pin. Button reads "Block creator of this pin." Pin creator identity is never surfaced in UI. Client-side filter hides blocked users' pins from the blocker's view. |
| Pin disposition on account delete | Keep pins, null `created_by` (`ON DELETE SET NULL`). Precedent: Reddit / Stack Overflow / Wikipedia preserve content under "[deleted]." Cascade-delete would actively harm the map's crowd-sourced accuracy. |
| EULA hosting | Full terms at `https://camiloh12.github.io/ccwmap/terms` (GitHub Pages; same site already hosts the auth callback). App opens the URL in an external browser. No offline in-app copy. |
| EULA acceptance scope | Three surfaces: passive first-launch modal for everyone (device-local flag), required checkbox at signup, retroactive blocking modal for existing authenticated users on first launch of the new version. |
| Moderation inbox | Supabase Database Webhook → `send-moderation-email` Edge Function → Resend API → `camilo@kyberneticlabs.com`. Moderator acts manually in Supabase Studio (delete pin via Table Editor, ban user via Auth → Users → Ban). No in-app admin UI and no `ban-user` Edge Function at launch. |
| Ban mechanics | Permanent (`banned_until = 'infinity'`). No ban-notification email. Only the offending pin is deleted at ban time — other pins by that user are kept. Up-to-1-hour residual write capability on a live session is tolerated. |
| Re-registration prevention | Out of scope. Unsolvable without KYC / phone verification / device fingerprinting. Apple does not require it. |

---

## SP-1 — Anonymous map access

### Goal

Any user can view the map and all pins without an account. Creation, editing, and deletion require authentication. Supabase RLS already permits anonymous reads — this is purely a client-side change.

### Routing change

- `AuthGate` (`lib/main.dart:121-190`) collapses. No more branching on `authViewModel.isAuthenticated` at the root. `MaterialApp.home` becomes `MapScreen` directly.
- Deep-link handling (currently inside `AuthGate`) moves to a thin wrapper (or stays in `main.dart`) whose only job is to subscribe to `AppLinks.getInitialLink()` and `uriLinkStream` and forward events to `AuthViewModel`. No longer coupled to auth-gated navigation.
- `LoginScreen` stops being the root. It becomes a route pushed on demand from the new `SignInPromptSheet`.

### MapScreen auth awareness

- App bar: `Consumer<AuthViewModel>` shows a **sign-in icon** (trailing) for guests. Authenticated users see no new icon in SP-1 (the gear icon for the Settings screen is introduced in SP-3).
- Compass FAB, debug-bug icon, and map behavior unchanged for both states.
- Tap handlers that assume auth — `_onFeatureTapped`, the POI/create path from `_detectPoiAtPoint`, and the edit/delete path on existing-pin taps — branch on `authViewModel.isAuthenticated`:
  - Authenticated: current flow unchanged.
  - Guest + tap-to-create or tap-on-POI: open `SignInPromptSheet`.
  - Guest + tap on existing pin: open `PinDialog` in read-only mode (see below).

### `SignInPromptSheet` (new widget)

Location: `lib/presentation/widgets/sign_in_prompt_sheet.dart`.

- Rendered via `showModalBottomSheet`.
- Title: "Sign in to add pins" (or "Sign in to edit" — caller passes context string).
- Body: "Create an account or sign in to contribute to the community map."
- Buttons: **Sign In**, **Create Account**, **Cancel**.
- Both action buttons `Navigator.push` the existing unmodified `LoginScreen`. The screen already exposes both sign-in and create-account affordances; no mode parameter needed.
- After auth succeeds on `LoginScreen`, user pops back to map. Preserve-intent (resuming the aborted action) is explicitly out of scope — email-confirmation async flow makes "continue where you left off" unreliable.

### `PinDialog` read-only mode

Add `isReadOnly` flag to the existing `PinDialog` (`lib/presentation/widgets/pin_dialog.dart`). When `isReadOnly`:

- All form fields disabled (`enabled: false`).
- Confirm/Delete buttons replaced with a single primary button **"Sign in to edit"** (opens `SignInPromptSheet`) plus **Close**.
- Title still shows the POI name — guest sees the pin's data.

Reusing `PinDialog` (rather than a new widget) keeps rendering and layout consistent and means future field additions only touch one place.

### Files touched

- `lib/main.dart` — collapse `AuthGate`, route to `MapScreen`.
- `lib/presentation/screens/map_screen.dart` — app-bar trailing icon, tap-handler branches.
- `lib/presentation/widgets/pin_dialog.dart` — `isReadOnly` mode.
- `lib/presentation/widgets/sign_in_prompt_sheet.dart` — new.
- Test files — update any that assume auth-gated root routing; add new guest-flow widget tests.

### Tests (SP-1)

- Widget test: guest sees map with pins rendered; tap-to-create opens `SignInPromptSheet`; tapping existing pin opens `PinDialog(isReadOnly: true)` with "Sign in to edit".
- Widget test (regression): authenticated user's create/edit/delete flow unchanged.

---

## SP-2 — UGC precautions

### A. EULA infrastructure

**Hosting.** Full terms at `https://camiloh12.github.io/ccwmap/terms`. App opens in external browser. Content: concise ToU with a "no tolerance for objectionable content or abusive behavior" clause, `camilo@kyberneticlabs.com` contact, effective date = release date of v0.4.0.

**Three acceptance surfaces:**

1. **First-launch passive modal** — shown once per install to everyone (guest or authenticated). `shared_preferences` flag `eula_acknowledged_v1`. Modal: "By using CCW Map, you agree to the Terms of Use and Community Guidelines." Buttons: **Got it** (sets flag, dismisses), **Read full terms** (opens external URL). Dismissible.

2. **Required checkbox at signup** — `LoginScreen`'s signup form gets an unchecked checkbox: "I agree to the Terms of Use and Community Guidelines and understand that objectionable content and abusive behavior are not tolerated." Submit disabled until checked. On successful signup, insert row into `user_agreements`.

3. **Retroactive blocking modal for authenticated users** — on app start after auth resolves, if current user has no row in `user_agreements` for the current version, show a non-dismissible full-screen modal with the same text. Buttons: **I Agree** (insert row, dismiss) or **Sign Out** (only exit). Covers existing TestFlight accounts.

**Schema (migration 004):**

```sql
CREATE TABLE user_agreements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  agreement_version INTEGER NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, agreement_version)
);
ALTER TABLE user_agreements ENABLE ROW LEVEL SECURITY;
CREATE POLICY "user_agreements_own_insert" ON user_agreements
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "user_agreements_own_select" ON user_agreements
  FOR SELECT USING (auth.uid() = user_id);
```

Current agreement version = `1`. If terms change materially later, bump to 2 and existing users re-accept via the retroactive modal.

### B. Name-field constraints

- **Length cap:** 60 chars. Client-side: `TextFormField(maxLength: 60)` + validator in `PinDialog`. Server-side: `CHECK (char_length(name) <= 60)` on `pins.name` (migration 007). Verify the current `pins.name` schema before writing the migration.
- **Profanity filter:** custom minimal implementation in `lib/core/profanity_filter.dart`. `const List<String>` of ~30 common slurs / obvious profanity. Case-insensitive substring match (`input.toLowerCase().contains(word)`). Rejected at submit time with "Please choose a different name." Obviously bypassable with l33t-speak / spacing — that's acceptable; the report mechanism is the real defense.
- No third-party profanity package. Existing pub.dev options are either bloated or have the same bypass limitations.

### C. Report pin and block user

**`pin_reports` table (migration 005):**

```sql
CREATE TABLE pin_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pin_id UUID NOT NULL REFERENCES pins(id) ON DELETE CASCADE,
  reporter_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  reason TEXT NOT NULL CHECK (reason IN ('INACCURATE','OFFENSIVE','SPAM','OTHER')),
  note TEXT CHECK (char_length(note) <= 500),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE pin_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pin_reports_auth_insert" ON pin_reports
  FOR INSERT WITH CHECK (auth.role() = 'authenticated');
-- No SELECT policy — only service role reads (via Studio / webhook payload).
```

**`blocked_users` table (migration 006):**

```sql
CREATE TABLE blocked_users (
  blocker_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);
ALTER TABLE blocked_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "blocked_users_own_all" ON blocked_users
  FOR ALL USING (auth.uid() = blocker_id)
  WITH CHECK (auth.uid() = blocker_id);
```

**UI:** two new buttons appear in `PinDialog` when the viewer is authenticated and the pin is not their own (`pin.createdBy != currentUser.id && pin.createdBy != null`):

- **Report pin** → sub-dialog (`ReportPinDialog`, new widget): reason radio picker + optional note TextField (max 500 chars) + Submit / Cancel. On submit: insert into `pin_reports`, show snackbar "Report submitted. Thanks for helping keep the map accurate."
- **Block creator** → confirmation dialog: "Block this user? You won't see any of their pins anymore." On confirm: insert into `blocked_users`, snackbar "User blocked," pin is removed from the map immediately via the stream filter update.

**Client-side blocklist filtering:**

- New `BlocklistService` (or method on a repository). Loads the current user's blocklist from Supabase on sign-in: `SELECT blocked_id FROM blocked_users WHERE blocker_id = auth.uid()`. Cached in memory as `Set<String>`.
- `MapViewModel` applies the filter in its pin stream transformation: `pins.where((p) => !blocklist.contains(p.createdBy))`.
- Refreshed on sign-in and after any block/unblock. No Drift persistence in v1 — offline-before-first-sign-in is the only gap and it's small.

### D. Moderation plumbing

- **Supabase Database Webhook 1:** `INSERT INTO pin_reports` → POST to `send-moderation-email` Edge Function.
- **Supabase Database Webhook 2:** `INSERT INTO blocked_users` → POST to same function with a different event-type flag in the payload.
- **`send-moderation-email` Edge Function** (`supabase/functions/send-moderation-email/index.ts`): Deno runtime. Parses webhook payload, formats plain-text email (pin id, coordinates, name, status, reporter/blocker id, reason, note, timestamp, direct link to the pin row in Supabase Studio), sends via Resend API. Reads `RESEND_API_KEY` from `Deno.env`. From: `moderation@kyberneticlabs.com` (or Resend sandbox default if custom domain isn't ready); To: `camilo@kyberneticlabs.com`.
- **No `ban-user` Edge Function at launch.** Moderator acts manually in Supabase Studio: delete pin via Table Editor (takes ~5 seconds), ban user via Auth → Users → Ban button. Total ~30 seconds per incident. If report volume grows materially, wrap in an Edge Function later.

### `docs/MODERATION.md`

Operational playbook:
- What signals each email type indicates.
- Review rubric (clearly-offensive vs. borderline vs. dismissible).
- Action procedure (pin delete first for immediate removal; ban second).
- SLA: 24 hours from email receipt.
- Absence/backup (mobile access to Supabase Studio; any co-maintainer contact points — currently none, solo project).

### Files touched (SP-2)

- `supabase/migrations/004_user_agreements.sql`, `005_pin_reports.sql`, `006_blocked_users.sql`, `007_pin_name_length.sql` — new (introduces `supabase/migrations/` directory).
- `supabase/functions/send-moderation-email/index.ts` — new.
- `lib/core/profanity_filter.dart` — new.
- `lib/data/datasources/supabase_remote_data_source.dart` — add methods: `submitPinReport`, `blockUser`, `unblockUser`, `fetchBlocklist`, `recordAgreementAcceptance`, `hasAcceptedAgreement`.
- `lib/domain/repositories/moderation_repository.dart` — new.
- `lib/domain/repositories/agreements_repository.dart` — new.
- `lib/data/repositories/` — implementations for both.
- `lib/data/services/blocklist_service.dart` — new (in-memory cache + refresh logic).
- `lib/presentation/widgets/pin_dialog.dart` — add Report + Block buttons (conditional on auth + non-self + non-anonymous creator).
- `lib/presentation/widgets/report_pin_dialog.dart` — new.
- `lib/presentation/widgets/eula_modal.dart` — new (handles both passive first-launch and retroactive blocking variants via mode parameter).
- `lib/presentation/screens/login_screen.dart` — add required EULA checkbox to signup form.
- `lib/presentation/viewmodels/map_viewmodel.dart` — apply blocklist filter in pin stream transformation.
- `lib/presentation/viewmodels/auth_viewmodel.dart` — trigger blocklist refresh on auth state change; host retroactive EULA check.
- `docs/MODERATION.md` — new.
- `docs/GITHUB_PAGES_TERMS.md` or update existing — note the `/terms` page needs to be added to the GitHub Pages site (outside this repo's tree — lives in the `gh-pages`/pages branch or a separate repo).

### Tests (SP-2)

- Unit: `ProfanityFilter` (wordlist coverage, case handling, empty/null, edge cases — aim 100%).
- Unit: `BlocklistService` (load, filter, update-on-block, update-on-unblock).
- Unit: `AgreementsRepository` (has-accepted query, insert).
- Widget: signup checkbox gating (submit disabled until checked).
- Widget: first-launch EULA modal (dismiss → flag set → doesn't reappear).
- Widget: retroactive EULA modal (blocks interaction until accepted or signed-out).
- Widget: `PinDialog` shows Report+Block only for other users' pins; hidden for own pins and for pins with `createdBy == null`.
- Widget: `ReportPinDialog` reason picker + submit path.

---

## SP-3 — Account deletion

### Goal

User can permanently delete their account from inside the app. Their pins persist with `created_by = NULL`.

### Schema migration

None required. Verified via Supabase MCP on 2026-04-24: `public.pins.created_by` is already `uuid`, nullable, with FK `pins_created_by_fkey` → `auth.users(id)` `ON DELETE SET NULL`. Row distribution at check time: 73 UUID-valued rows, 37 NULL, no `'anonymous'` literals (the column is UUID — couldn't hold the string). The CLAUDE.md BUG-002 reference to `'anonymous'` reflects a past client-side convention that was already normalized to NULL in the DB. SP-3 relies on the existing FK cascade and needs no DDL.

### `delete-account` Edge Function

Location: `supabase/functions/delete-account/index.ts`.

- Input: authenticated JWT in `Authorization` header. No body params.
- Steps:
  1. Extract `user_id` from JWT (using Supabase's auth helpers).
  2. Create admin client with `SUPABASE_SERVICE_ROLE_KEY`.
  3. Call `supabase.auth.admin.deleteUser(user_id)`.
  4. Return 200 on success; 401/500 with error body on failure.
- No admin role check. Callers authenticate as themselves and can only delete themselves.
- Cascades handled by FKs: `user_agreements` deleted (CASCADE), `blocked_users` rows deleted (CASCADE both directions), `pin_reports.reporter_id` set NULL, `pins.created_by` set NULL.

### Domain + data layer

- `AuthRepository.deleteAccount()` — add to interface (`lib/domain/repositories/auth_repository.dart`).
- `SupabaseAuthRepository.deleteAccount()` — implements via `_supabase.functions.invoke('delete-account')`; on success, drain local sync queue, call `signOut()`, clear `flutter_secure_storage`.
- `AuthViewModel.deleteAccount()` — wrap with loading/error state plumbing matching existing `signOut()` pattern.

### Settings screen

Location: `lib/presentation/screens/settings_screen.dart` (new).

- Reachable via a **gear icon** in `MapScreen`'s app bar, visible only when authenticated (guests see only the sign-in icon from SP-1).
- Contents:
  - Signed-in email (readonly label).
  - **Sign Out** button (closes the gap — there's no UI for sign-out today).
  - **Delete Account** button (destructive, red).

### Delete-account UX flow

1. Tap **Delete Account** → first dialog: "This permanently deletes your account. Your pins will remain on the map as community contributions." Buttons: **Cancel** / **Continue**.
2. Continue → second dialog: "Type DELETE to confirm." TextField + **Delete** button disabled until content matches `DELETE` exactly (case-sensitive).
3. On submit: loading spinner → `AuthViewModel.deleteAccount()` → on success, pop back to `MapScreen` (now in guest state, map still visible), show snackbar "Account deleted."
4. Local sync queue drained *before* the Edge Function call so pending writes don't 401 after deletion.
5. On failure: surface error via snackbar; user can retry or cancel. Common failure: network offline (the function call needs connectivity, no offline-queueing here).

### Ban error path

Updated in `AuthViewModel._formatAuthError`: when Supabase returns a "banned" auth exception on sign-in, map to:

> "This account has been suspended for violating the community guidelines. For appeals, email camilo@kyberneticlabs.com."

### Files touched (SP-3)

- `supabase/functions/delete-account/index.ts` — new.
- `lib/domain/repositories/auth_repository.dart` — add `deleteAccount()`.
- `lib/data/repositories/supabase_auth_repository.dart` — implement.
- `lib/presentation/viewmodels/auth_viewmodel.dart` — wire delete + ban error mapping.
- `lib/presentation/screens/settings_screen.dart` — new.
- `lib/presentation/screens/map_screen.dart` — add gear icon (authenticated users only).

### Tests (SP-3)

- Unit: `AuthViewModel.deleteAccount()` — success, network error, already-signed-out error.
- Unit: `AuthViewModel._formatAuthError` — "banned" error message maps to the "Account suspended" copy with the support email.
- Widget: Settings screen renders signed-in email.
- Widget: delete-confirmation gating (Delete button disabled until text matches `DELETE`).
- Widget: post-delete navigation state (user returns to guest map).

---

## Supabase schema summary

Migrations introduced by this work (new `supabase/migrations/` directory):

- **004** — `user_agreements` table.
- **005** — `pin_reports` table.
- **006** — `blocked_users` table.
- **007** — `pins.name` length CHECK constraint.

SP-3's `ON DELETE SET NULL` cascade on `pins.created_by` is already present in the live schema (verified 2026-04-24 via Supabase MCP); no migration 008 needed. Backfilling the current schema as migrations 001–003 is nice-to-have but out of scope for this work.

## Edge Functions

New `supabase/functions/` directory:

- **`send-moderation-email`** (SP-2) — webhook target, Resend-backed.
- **`delete-account`** (SP-3) — user-invoked, admin API caller.

### Deployment

Manual via `supabase functions deploy <name>` for v0.4.0. Document in `docs/DEPLOY.md` (new). Auto-deploy via GitHub Actions is a future enhancement.

### Secrets

- **`RESEND_API_KEY`** — stored in Supabase secret store (`supabase secrets set RESEND_API_KEY=...`). Read by `send-moderation-email` via `Deno.env.get`.
- **`SUPABASE_SERVICE_ROLE_KEY`** — implicitly available inside Edge Functions as `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')`.
- Nothing new in GitHub Actions secrets for v0.4.0.
- Gitleaks in `.github/workflows/pr-checks.yml` backstops accidental commits of key-shaped strings.
- Local-dev `supabase/.env` (for `supabase functions serve`) gitignored.

---

## Testing strategy summary

### Unit tests (no network)

- `ProfanityFilter` — wordlist coverage, case handling, empty/null, edge cases. Aim 100%.
- `BlocklistService` — load, filter, update-on-block/unblock.
- `AgreementsRepository` — has-accepted-v1 query, insert.
- `AuthViewModel.deleteAccount()` — success, network error, auth-already-expired error paths.
- Pin model changes — `created_by` nullable handling.

### Widget tests

- SP-1: guest flows (tap-to-create → prompt sheet; tap-existing-pin → read-only dialog); authenticated regression.
- SP-2: signup checkbox gating; first-launch EULA; retroactive EULA blocking; `PinDialog` conditional Report+Block rendering; `ReportPinDialog` reason picker.
- SP-3: Settings screen; type-DELETE confirmation gating; post-delete navigation.

### Regression guard

All 109 existing tests continue to pass without modification, except auth-routing-assumption tests which are expected to update.

### Manual tests on physical iOS device

Required for Apple resubmission. Three screen recordings (see App Store Resubmission below).

---

## App Store resubmission plan

### Version

Ship as `v0.4.0` (minor bump — new features). Branch from `master` per `docs/GIT_FLOW.md` (`release/v0.4.0`).

### Screen recordings (captured on physical iOS device)

1. **`guest-browse.mov`** — cold-start → map visible as guest → tap empty area → `SignInPromptSheet` appears → sign in → add a pin successfully. Covers Rejection 1.
2. **`ugc-moderation.mov`** — first-launch EULA modal → signup with EULA checkbox → tap an existing pin → Report sub-dialog (pick reason, add note, submit) → success snackbar → Block creator → confirm → pin disappears from map. Covers Rejection 1.2.
3. **`account-deletion.mov`** — sign in → open Settings (gear icon) → tap Delete Account → first confirm → type `DELETE` → tap Delete → loading → back to guest map → confirm user is signed out and cannot sign back in with same credentials. Covers Rejection 2.

### App Review Notes text (paste into App Store Connect on submission)

```
Re: Guideline 5.1.1(v) (non-account features require registration):
Map browsing is now fully unauthenticated. Account creation is only
required to add, edit, or delete pins. See screen recording
"guest-browse.mov."

Re: Guideline 5.1.1(v) (account deletion):
Account deletion is available in Settings -> Delete Account.
Flow demonstrated in "account-deletion.mov." All user account data
(auth.users row, user_agreements, blocked_users) is permanently
deleted on confirmation. User-contributed pins remain on the map as
anonymous community contributions (created_by is nulled), consistent
with standard practice for crowd-sourced data.

Re: Guideline 1.2 (user-generated content):
EULA acceptance is required at account creation and enforced
retroactively for existing accounts (see "ugc-moderation.mov").
Users can report any pin via the pin detail dialog; reports reach
the developer within seconds via a database webhook ->
send-moderation-email Edge Function -> Resend. Users can block any
pin's creator, which immediately hides all pins by that user.
Developer SLA for report review and action is 24 hours per
docs/MODERATION.md.

Demo account: <email> / <password>
```

---

## Out of scope (explicit)

Deliberately not in v0.4.0:

- Preserve-intent auth flow (resume aborted action after sign-in). Unreliable across email-confirmation async.
- `ban-user` Edge Function. Manual Studio action is adequate for launch volume.
- In-app admin moderation UI. Same.
- Auto-unban / time-limited bans.
- Ban-notification email to the banned user. Not required by Apple; avoids building outbound-email infrastructure to end users.
- In-app appeal form.
- Prevention of re-registration after ban. Out of reach without KYC.
- Backfilling migrations 001–003 of the existing schema.
- Drift-local persistence of the blocklist. Pure in-memory is sufficient for v1.
- Supabase custom email domain. Resend sandbox addresses are fine until custom domain is wired up.
- Auto-deploy of Edge Functions via GitHub Actions.

---

## Open items to resolve during implementation

- Draft ToU text for the GitHub Pages `/terms` page. Keep short and clear; link to `camilo@kyberneticlabs.com` for questions.
- Decide Resend From-address: sandbox default vs custom `moderation@kyberneticlabs.com` (requires DNS setup). Can start with sandbox and migrate later.
- Confirm `auth.users.banned_until = 'infinity'` is the correct Supabase idiom (vs. a far-future timestamp). Practical check before the ban runbook is published.
- Create a pre-confirmed demo account in Supabase with sample pin data (one own pin, one other-user pin) before resubmission. Credentials fill the `<email> / <password>` placeholder in App Review Notes. Note the account is retained across resubmissions until Apple confirms acceptance.

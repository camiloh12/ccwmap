# Moderation Playbook

SLA: **24 hours** from email receipt to pin-action + ban decision.

## Email signals

Two subject-line prefixes drive triage:

| Subject | Signal |
|---|---|
| `[CCW Map] Pin reported — <REASON>` | A user submitted a report via `ReportPinDialog`. |
| `[CCW Map] User blocked` | A user blocked another user. Not a report — but repeated blocks against the same `blocked_id` are a signal to review that user's pins manually. |

## Review rubric

- **OFFENSIVE / SPAM:** delete the pin immediately. If it's the user's first offense AND the content isn't a slur, leave the account alone. Otherwise ban.
- **INACCURATE:** verify against ground truth (MapTiler base map, public signage photos, news). If clearly wrong, delete. If uncertain, mark mentally for follow-up.
- **OTHER + note:** read the note; decide case-by-case.

## Action procedure

1. **Open Supabase Studio → Table Editor → `pins`**; filter by `id = <from email>`; delete the row.
2. **If banning:** Studio → Authentication → Users → search for `<user_id>` → "Ban user" → set duration to "Permanent" (or the `banned_until = 'infinity'` idiom once confirmed by Supabase support).
3. If the pin was referenced by multiple reports, check `pin_reports` for any additional notes before deciding.

## What ban does

- The next auth refresh (up to ~1 hour) will fail with the "banned" auth exception. The app maps that to "This account has been suspended for violating the community guidelines. For appeals, email camilo@kyberneticlabs.com." (SP-3 Task TBD.)
- Ban does **not** delete the user's other pins. The single offending pin is deleted manually in step 1; other pins remain so the map keeps the information. Delete additional pins only if they are similarly violating.

## Absence / backup

Solo project — no backup moderator. Supabase Studio works on mobile, so even travel is not a blocker for 24h SLA. If absence > 24h is expected, pause the moderation webhooks in Studio (this prevents a pile-up; emails still arrive once re-enabled).

## Appeals

Appeal address published in-app and on the GitHub Pages terms page: `camilo@kyberneticlabs.com`. No formal appeal form; decisions are handled by email.

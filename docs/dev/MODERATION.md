# Moderation Playbook

SLA: **24 hours** from email receipt to pin-action + ban decision.

## Email signals

Two subject-line prefixes drive triage:

| Subject | Signal |
|---|---|
| `[CCW Map] Pin reported — <REASON>` | A user submitted a report via `ReportPinDialog`. |
| `[CCW Map] Imported pin reported: <reason> (<source>)` | A report on an imported pin. See "Reports on imported pins" below. |
| `[CCW Map] User blocked` | A user blocked another user. Not a report — but repeated blocks against the same `blocked_id` are a signal to review that user's pins manually. |

## Review rubric

- **OFFENSIVE / SPAM:** delete the pin immediately. If it's the user's first offense AND the content isn't a slur, leave the account alone. Otherwise ban.
- **INACCURATE:** verify against ground truth (MapTiler base map, public signage photos, news). If clearly wrong, delete. If uncertain, mark mentally for follow-up.
- **OTHER + note:** read the note; decide case-by-case.

## Action procedure

1. **Open Supabase Studio → Table Editor → `pins`**; filter by `id = <from email>`; delete the row.
2. **If banning:** Studio → Authentication → Users → search for `<user_id>` → "Ban user" → set duration to "Permanent" (or the `banned_until = 'infinity'` idiom once confirmed by Supabase support).
3. If the pin was referenced by multiple reports, check `pin_reports` for any additional notes before deciding.

## Reports on imported pins

Pre-populated (imported) pins have no author, so a report on one is a
data correction, not a moderation case. Users can report them from the
pin dialog (0.9.0 and later). The reasons are Closed, Wrong location,
Not a *category*, Duplicate and Other. The server allows one open report
per pin per account and 10 reports per account per 24 hours.

### What the email contains

Subject: `[CCW Map] Imported pin reported: <reason> (<source>)`. The body
has the pin snapshot (name, dataset, record id, tag, confidence,
citation), a map link at the pin, the reporter's note and id (the email
is private), and a **Resolve pin report** block with the values to paste:
the report id, the three actions, and the current coordinates as a
starting point for a move.

### Resolving a report

1. GitHub, Actions, **Resolve pin report**, **Run workflow**. Run it from
   `master` for `prod`; `prod` from other branches is refused.
2. Fill in `target` (`prod` for real reports), `report_id`, `action`,
   and for a move `latitude` and `longitude` (inside the continental US).
3. `confirm` must be exactly `I-KNOW-THIS-WRITES-TO-PROD` (staging:
   `I-KNOW-THIS-WRITES-TO-STAGING`).

The actions:

- **remove:** deletes the pin, adds its source record to the do-not-import
  list (one row; at import time, same-dataset neighbours within 100 m
  with a similar name are matched against it) so the next import does
  not bring it back, and closes **every** open
  report on the pin as `removed`. If an import already removed the pin,
  the outcome and the list entry are still recorded. The list never
  blocks a record that already has a pin.
- **move:** sets the new coordinates and marks the pin user-corrected, so
  imports leave it alone from then on. Its confidence and citation also
  stop refreshing. Closes the named report plus other open reports on
  that pin with the same reason as `moved`.
- **dismiss:** leaves the pin alone and closes the named report plus
  other open reports on that pin with the same reason as `dismissed`.

Reports on user-created pins are refused; handle those with the
procedure above. An already-resolved report is refused too.

### What the run log shows

The summary shows the report id, the action, the pin's name and source,
the final coordinates, how many reports were closed and whether the pin
was deleted. It never shows the note or the reporter.

### Deleting a do-not-import entry by hand

If a removal was a mistake, delete the entry in the Studio SQL editor:

```sql
DELETE FROM import_suppressions
WHERE source = '<source>'
  AND source_external_id = '<record id>';
```

The removed pin does not come back by itself. The next import re-inserts
the record as a new pin (the dry-run report's `Suppressed (do-not-import
list)` row shows how many candidates the list is holding back).

### The 7-day open-report finding

The daily health check (rule 10) opens an alert when a report on an
imported pin has been open more than 7 days. Resolve or dismiss it. The
digest also shows removals made via reports, the open-report count and
the oldest open report. Removals made through the workflow do not trip
rules 4 and 5. See `docs/importer/PROD_HEALTH_CHECK.md`.

### Deploying the Edge Function by hand

Nothing in CI deploys Edge Functions. After changing
`send-moderation-email`, deploy it yourself:

```
supabase functions deploy send-moderation-email \
  --project-ref <ref>
```

## What ban does

- The next auth refresh (up to ~1 hour) will fail with the "banned" auth exception. The app maps that to "This account has been suspended for violating the community guidelines. For appeals, email camilo@kyberneticlabs.com." (SP-3 Task TBD.)
- Ban does **not** delete the user's other pins. The single offending pin is deleted manually in step 1; other pins remain so the map keeps the information. Delete additional pins only if they are similarly violating.

## Absence / backup

Solo project — no backup moderator. Supabase Studio works on mobile, so even travel is not a blocker for 24h SLA. If absence > 24h is expected, pause the moderation webhooks in Studio (this prevents a pile-up; emails still arrive once re-enabled).

## Appeals

Appeal address published in-app and on the GitHub Pages terms page: `camilo@kyberneticlabs.com`. No formal appeal form; decisions are handled by email.

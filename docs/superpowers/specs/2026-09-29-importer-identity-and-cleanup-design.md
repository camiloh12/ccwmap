# Importer identity and cleanup — design

**Date:** 2026-09-29 · **Status:** draft for owner review
**Context:** step 1 of the national-import readiness plan (importer fixes
before Phase 8). Follows the pilot close-out coordinate audit (2026-09-27),
whose three importer findings this spec addresses, plus four more found
while designing the fixes.
**Parent specs:** `2026-05-10-pre-populate-pins-design.md` (§4 pipeline, §6
orphans), `2026-06-02-phase4-federal-floor-design.md` (GSA, MIRTA, dedup).

## Goal

Make the importer safe to run nationally: every source record becomes at
most one pin with a stable identity, pins land inside the place they mark,
records the source no longer lists leave the map, and no pin cites a law
that doesn't apply to it. The changes are verified on staging with the pilot
states (TX/FL/PA). Prod is re-applied later, in a separate owner-approved run.

## Findings (measured 2026-09-28 against the cached source files)

| # | Finding | Evidence | Impact |
|---|---|---|---|
| 1 | **MIRTA sites without an SDSID collapse into one pin.** `_external_id` falls back to `MIRTALOCATIONSIDPK`, which is a single space on every feature, so 202 of 825 features share the id `' '` (3 more share the all-zero UUID). Within-source dedup keeps the first. | 25 of 102 pilot features affected | 23 pilot installations never became pins (Fort Indiantown Gap, Camp Mabry, Camp Swift, Ellington Field, …); ~200 nationally |
| 2 | **FRPP property ids are unique only within an agency and bureau.** `Real Property Unique Identifier` repeats across agencies (4,243 ids nationally) and, within Interior, across bureaus (30 more). Reporting agency code + bureau code + property id is unique across all 113,015 buildings, with no blank codes. | pilot: 279 colliding groups | 293 pilot buildings dropped; ~4.8k nationally. A national run could also attach a pilot pin's id to another state's building |
| 3 | **MIRTA centroids fall outside the base.** 77 of 825 area-weighted centroids lie outside every part of a multi-part base (pilot audit: Jacksonville IAP 22.6 km, JBSA 3.0 km). MIRTA's point layer (layer 0, "DoD Sites – Point") has a DoD-placed point per site: 730 match a boundary by state + name, 725 of those lie on the base, and they fix 69 of the 77. The largest part alone is not a good substitute: for JBSA it is Camp Bullis, not Lackland. | audit + national scan | 1 of 10 audited military pins failed |
| 4 | **FRPP `Asset Status = Disposed` is imported.** 892 buildings nationally (103 pilot) are no longer federal property but still get red pins. MIRTA has the same concept: 11 sites have `SITEOPERATIONALSTATUS = 'clsd'`. | FRPP / MIRTA fields | red pins with no legal basis |
| 5 | **The `US / STATE_LOCAL_GOVT` cell cites 18 USC 930 for state courthouses.** HIFLD Courthouses has only 4 federal-looking names out of 3,713 (3 in territories); federal courthouses already come from GSA. In any state without its own cell, the fallback would label county and state courthouses with the federal statute. | name scan | wrong citation on ~3.2k courthouses nationally |
| 6 | **Orphan detection never fires.** `run_pipeline` fetches existing pins with `select_pins_by_keys(source, <this run's ids>)`, so a pin whose record vanished is never fetched and `diff.orphans` is always empty. | code read | dropped records stay on the map forever |
| 7 | **An automated GSA coordinate cross-check is low-yield.** Only 4,356 of 9,733 pilot buildings have a street address, and the Census geocoder matched 60% of those. Most >1 km disagreements are campus addresses where FRPP's coordinate is right (178 Johnson Space Center buildings share one address). A narrow rule (address not shared, exact match, >1 km) moves 13 pilot pins and misses both audit failures (Harrisburg has no street address; Alpine's match isn't exact). Distance from the FRPP city is worse: 11k buildings nationally sit >25 km from their city, mostly park buildings with a headquarters mailing city. | Census batch geocode of the pilot rows; 2024 Census Gazetteer | not built (decision below) |

## Decisions (owner, 2026-09-28)

| Decision | Choice | Why |
|---|---|---|
| Pins whose source id changes | **Re-key in place** | Pin UUIDs and any user corrections made since 012 survive; no mass delete-and-reinsert in prod |
| Pins whose source record disappeared | **Delete on apply, opt-in** (`--delete-orphans`), with a safety cap, never deleting a user-corrected pin | Disposed buildings and closed sites should leave the map; a truncated download must not wipe a layer; no migration needed |
| GSA coordinate cross-check | **Not built** | Finding 7; outliers are left to the 0.9.0 "Report a problem" flow |
| Military pin position | DoD site point when it's on the base, else a point inside the largest part | Finding 3 |
| Military pins per installation | **One** (per-part pins deferred) | YAGNI; the site point already puts JBSA at Lackland |
| US courts cell | **Delete it** | Finding 5; courthouses wait for their own state's cell |

## Design

### 1. Military source (`importer/importer/sources/hifld_military.py`)

**Identity.** A feature's key is its `SDSID` when that is a real GUID (not
blank, not all zeros). Otherwise the key is `"{STATE}:{SITENAME}"`, with the
state upper-cased and the site name upper-cased and whitespace-collapsed
(e.g. `TX:NG CAMP MABRY`). Features that share a key are the same
installation split across records (JB McGuire-Dix-Lakehurst, MCRD San Diego,
NG Camp Fogarty, NG MTA Limestone Hills): their geometries are merged
(`unary_union`) into one candidate.

**Position.** `fetch()` also downloads MIRTA layer 0 (site points) to a
second cache file, from a new `sources.hifld_military.points_url` config key
(`…/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=geojson`).
A boundary is matched to its site point by `SDSID` when both have a real
one, else by state + site name. The pin goes on the site point when the
point lies within ~50 m of the (merged) boundary; otherwise on the
`representative_point()` of the largest part, which is always inside it.
`coord_quality` stays `BUILDING_POLYGON`. A missing points file is an error
(like a missing boundary file), not a silent fallback.

**Filter.** Features with `SITEOPERATIONALSTATUS == 'clsd'` are skipped
(skip count `closed`). Caretaker (`care`), excess (`excs`) and semi-active
(`semi`) sites stay: DoD still holds them.

**Legacy identity.** When a feature's new key differs from what the old
`_external_id` returned (`' '`, the all-zero UUID), the candidate carries
the old id and the old area-weighted centroid (see §4). For merged
features, the legacy values come from the first feature in file order,
which is what the old code kept.

### 2. GSA source (`importer/importer/sources/gsa.py`)

**Identity.** `source_external_id = "{Reporting Agency Code}-{Reporting
Bureau Code}-{Real Property Unique Identifier}"` (e.g. `13-14-14000592`).
The two code columns join `_NEEDED_COLS`; a row missing either is skipped
(`missing_external_id`), though none are blank today.

**Filter.** Rows with `Asset Status == 'Disposed'` are skipped (skip count
`disposed`). Other statuses stay: "Determination to Dispose", "Report of
Excess", "Surplus" and "Cannot Currently be Disposed" are all still federal.

**Legacy identity.** Every candidate carries the old id (the bare property
id) and its own coordinate as the legacy point. Coordinates don't change in
this spec, so the legacy point is the pin's current position.

No coordinate cross-check (decision above).

### 3. State-law table (`data/state_laws/states.yaml`)

Delete the `state: US / category: STATE_LOCAL_GOVT` cell. TX, FL and PA keep
their own court cells, so nothing changes in the pilot. In other states,
`hifld_courts` candidates drop at `apply_state_law` and appear in the
report's "needs research" list until the state gets its own cell. A new
structural test asserts that no `US` cell's `source_filter` contains
`hifld_courts`. `data/state_laws/README.md` and `docs/importer/OMISSIONS.md`
note why courthouses have no federal fallback.

### 4. Legacy identity on `Candidate` (`importer/importer/candidate.py`)

`Candidate` gains two optional fields, set only by sources whose id scheme
changed and only when the old id differs from the new one:

- `legacy_external_id: str | None = None`
- `legacy_point: tuple[float, float] | None = None` — (lat, lng) the old
  code would have written for this record.

They are identity hints for the diff stage and are never written to the
database.

### 5. Diff: re-key (`importer/importer/stages/diff.py`, `pipeline.py`)

The existing-pin lookup for a source fetches the pins whose
`source_external_id` is any of the run's new ids **or** legacy ids.

Matching runs in two passes over the source's surviving candidates:

1. **New id.** A candidate whose new id matches an existing pin is an
   update, or a skip if the pin is `user_modified` (today's behavior). That
   pin is claimed.
2. **Legacy id.** For each remaining candidate with a legacy id, look at the
   unclaimed existing pins carrying that legacy id and take the one nearest
   the candidate's `legacy_point`. If it is within **50 m**, the candidate is
   a **re-key** of that pin, which is then claimed. Colliding GSA ids resolve
   this way: several buildings share one old id, and position says which one
   the pin belonged to. If the nearest pin is farther than 50 m, the
   candidate is an insert and the counter `rekey_too_far` goes up; the old
   pin then falls out as an orphan, so it is reported rather than silently
   merged.
3. Everything else is an insert.

Candidates are processed in a stable order (source iteration order) so the
result is deterministic. A second run finds every re-keyed pin by its new
id in pass 1, so re-keying is idempotent.

`DiffResult` gains `rekeys: list[Rekey]`, where a `Rekey` holds the pin
UUID, the old id, the new id, whether the pin is `user_modified`, and the
classified candidate. `DiffStats` gains `rekeys` and `rekey_too_far`.

### 6. Orphan detection (`pipeline.py`, `supabase_client.py`)

A new `SupabaseClient.select_system_pins(source)` pages through every pin
with that `source` and `created_by = <system user>` (Range header, 1,000 per
page), returning `ExistingPinRow`s. The pipeline keeps the ones whose
coordinates fall in the run's states, using the same `StateLocator` the
sources use (pins have no state column). With no state filter, all of them
are in scope. Orphans are the in-scope pins that pass 1 and pass 2 didn't
claim.

This also turns pins that lost to a higher-priority source in dedup into
orphans. That is intended: the winning pin stays on the map.

### 7. Apply (`importer/importer/stages/apply.py`)

Order per source:

1. **Re-keys.** `PATCH /pins?id=eq.<uuid>` setting `source_external_id` to
   the new id and clearing `source_orphaned_at`. A service-role write never
   sets `user_modified` (013's `set_user_modified` skips `service_role`).
2. **Upsert** inserts, updates, and the re-keys of pins that are *not*
   `user_modified` (their content refreshes like any update). A
   user-corrected re-keyed pin gets only step 1: its edits stay.
3. **Orphans.**
   - Default: mark `source_orphaned_at = now()` (today's `mark_orphans`,
     which now actually receives orphans).
   - With `--delete-orphans`: `DELETE /pins?id=in.(…)&user_modified=eq.false&created_by=eq.<system>`
     for the orphans; user-corrected orphans are marked instead and listed
     as "kept, user-corrected". The existing `record_pin_deletion` trigger
     writes the tombstones; the delete rate limit already skips
     `service_role` (008 §6c).

**Safety cap.** Before any source writes anything, the pipeline computes
every source's diff and checks each one: if a source's orphan deletions
would exceed `max(50, 5% of its in-scope pins)`, the run stops with an error
and writes nothing. The dry-run evaluates the same cap and reports a breach
as an error, so it's visible before an apply. `--orphan-delete-cap N`
overrides the limit for a local run; the workflow doesn't expose it (a prod
breach means stop and investigate, then a PR if the deletion is intended).
This moves Phase C from "diff then apply, per source" to "diff all sources,
check caps, then apply all".

### 8. CLI and workflow

- `importer.cli`: new flags `--delete-orphans` (apply mode only; rejected
  with `--dry-run`, which instead reports what a delete would do) and
  `--orphan-delete-cap N`.
- `.github/workflows/importer-apply.yml`: new boolean input
  `delete_orphans` (default `false`) that adds `--delete-orphans`.
- `import_runs.orphans_marked` keeps its meaning (orphans marked, not
  deleted). No schema change.

### 9. Health check (`ci/health_check.sql`, `ci/health_check.py`)

Rules 4 ("imported pins deleted, last 24 h", tripwire `> 0`) and 5 ("all pin
deletions, last 24 h", `> 50`) would fire the day after any orphan-deleting
apply. Both now exclude deletions made during an importer apply run:
`NOT EXISTS (SELECT 1 FROM import_runs r WHERE r.mode = 'apply' AND
d.deleted_at BETWEEN r.started_at AND r.completed_at)`. A run that crashed
before recording `completed_at` doesn't qualify, so its deletions still
alert. A new informational metric, `importer_deleted_24h`, shows those
deletions in the digest without a rule. The ci tests that keep
`METRIC_KEYS` and the SQL in sync cover the new key.

### 10. Reports

Per source, the markdown and JSON reports add: `Re-key: N` (plus `re-key
too far: N` when non-zero), orphans split into `deleted` / `kept,
user-corrected` / `marked`, a cap line when a cap is breached, and the new
skip counts (`disposed`, `closed`).

## Testing (TDD)

- **Military:** SDSID key; blank and all-zero SDSID → state + name key;
  features sharing a key merge; the site point is used when on the base;
  the fallback point is inside the largest part when the site point is
  missing or off the base; `clsd` skipped; legacy fields set only when the
  id changed. New fixture `hifld_military_points_sample.geojson`; the
  boundary fixture gains blank-SDSID, all-zero, duplicate, multi-part and
  closed cases.
- **GSA:** composite key; Disposed skipped; legacy id is the bare property
  id and legacy point the row's coordinate. `gsa_frpp_sample.xlsx` gains
  the agency code, bureau code and status columns and colliding-id rows.
- **State laws:** no `US` cell claims `hifld_courts`; a TX courthouse still
  resolves to the TX cell; a courthouse in a state with no cell drops and
  is reported.
- **Diff:** single legacy match → re-key; colliding legacy ids → nearest pin;
  >50 m → insert + orphan + `rekey_too_far`; user-corrected re-key keeps its
  content; a new-id match wins over a legacy match; a second run is
  update-only.
- **Orphans / apply:** scope by state; default marks; `--delete-orphans`
  deletes and keeps user-corrected pins; the cap stops the run before any
  write; the dry-run reports a breach; `--delete-orphans` with `--dry-run`
  is rejected.
- **Supabase client:** `patch_external_id`, `delete_pins`,
  `select_system_pins` paging, using the existing mocked-HTTP pattern.
- **Health check:** importer-window deletions are excluded from rules 4 and
  5 and counted in `importer_deleted_24h`; a deletion outside any run, or
  during a run without `completed_at`, still trips rule 4.
- Full importer suite (`cd importer && pytest`) and `ci/tests` stay green.

## Staging verification (pilot TX/FL/PA)

1. Resume staging if paused. Snapshot every system pin's `id, source,
   source_external_id, latitude, longitude` via MCP.
2. Dry-run. Expected, roughly: GSA ≈ 4.2k re-keys and ≈ +290 inserts (less
   dedup); military ≈ +23 inserts and 1–2 re-keys; orphans ≈ 100 (mostly
   Disposed) plus dedup-displaced pins; no cap breach; `rekey_too_far` = 0.
   Investigate any large deviation before applying.
3. Spot-check the dry-run positions: JBSA at Lackland, Jacksonville IAP on
   its base, and Fort Indiantown Gap, Camp Mabry and Ellington Field
   present.
4. Apply to staging through `importer-apply.yml` (target staging) with
   `delete_orphans` checked.
5. Dry-run again: 0 inserts, 0 re-keys, 0 orphans.
6. SQL on staging: no duplicate `(source, source_external_id)`; every
   re-keyed pin kept its UUID (diff against the snapshot); counts by source;
   a GSA pin sample shows the new id format.
7. Run the health check workflow manually: staging green, and the importer
   deletions appear only in `importer_deleted_24h`.

## Docs

`importer/README.md` (re-key, orphan deletion, the cap and flags);
`docs/importer/SOURCES.md` (MIRTA site points and the merged-feature rule,
FRPP composite key, Disposed/closed filters); `docs/importer/STAGING_REAPPLY.md`
and `docs/importer/PROD_APPLY.md` (the `delete_orphans` checkbox, reading the
re-key and orphan lines); `docs/importer/PROD_HEALTH_CHECK.md` (rules 4/5
exclusion); `data/state_laws/README.md` and `docs/importer/OMISSIONS.md`
(no federal courthouse fallback); CLAUDE.md status.

## Out of scope (follow-ups)

- **Re-applying prod.** A separate owner-approved workflow run, most likely
  bundled with Phase 8a. For the pilot states it adds ≈ 290 buildings and
  ≈ 23 bases and removes the Disposed pins.
- **Courthouse state cells** for the other 45 continental states (research
  task; owner has not started it yet).
- **GSA legal scope** (family housing, restrooms, barracks, …): owner and
  lawyer decision. FRPP's `Number of Federal Employees` may help: of the
  9,733 non-Disposed pilot buildings it is 1+ on 1,589, zero on 2,097 and
  blank on 6,047.
- **One pin per significant base part** (31 installations nationally have a
  ≥1 km² part more than 5 km from the largest).
- **Degenerate GSA labels** such as `TEXAS-0` (≈70 USDA offices in TX).
- **`select_user_pins` paging**: still capped at 1,000 rows; fine at today's
  user-pin count, needed before user pins outgrow it.

## Risks

- **A wrong re-key attaches a pin to the wrong record.** Mitigated by the
  50 m legacy-point check and the `rekey_too_far` counter; verified on
  staging against the pre-apply snapshot.
- **Mass deletion.** Mitigated by opt-in, the per-source cap, keeping
  user-corrected pins, and the dry-run preview.
- **MIRTA point layer drift.** A renamed site or changed SDSID means no site
  point; the pin falls back to a point inside the largest part, never
  outside the base.

# Phase 3 — State-Law Table Seeding Design

**Date:** 2026-05-31
**Status:** Draft — pending implementation plan via writing-plans
**Parent spec:** [`2026-05-10-pre-populate-pins-design.md`](2026-05-10-pre-populate-pins-design.md) §8, Phase 3

## Background

Phase 3 of the pre-populate-pins project fills the maintained state-law lookup
table at `data/state_laws/states.yaml` with the legal-classification cells the
importer uses to assign each pre-populated pin a status, restriction tag,
confidence, citation, and verified date. Phases 0–2 (schema, viewport sync,
importer skeleton) shipped in v0.6.0. As of now the table contains exactly one
cell — the Phase 2 federal-courthouse fallback `(US, STATE_LOCAL_GOVT)`.

The parent spec budgeted Phase 3 as "33 cells = TX + FL + PA × 10 categories +
3 federal-uniform `US` cells." Four brainstorming decisions (below) reshape that
naive count into a smaller written table backed by a documented omission list,
while keeping the research scope intact.

These cells become legal assertions on pins in a firearms app. Per the parent
spec's risk register, pre-asserting `NO_GUN` where carry is actually legal is
the highest-impact error mode (e.g. a Texas public university under campus
carry). Correctness is the dominant constraint of this phase.

## Decisions (from brainstorming)

1. **Research workflow:** I draft each cell (training knowledge + web-verified
   current statute), present per-cell; the user is the final legal authority and
   signs off before anything commits.
2. **`PRIVATE_PROPERTY`:** omitted entirely. No pilot source emits it; the only
   path (OSM `access:firearms=no`) lands in Phase 6. Matches the parent spec's
   Scope deferral.
3. **Category coverage:** all 9 remaining categories researched now (spec intent
   — legal research done once), not just the Phase 4–5 categories.
4. **No-prohibition combos:** omit the cell (importer drops the candidate, no pin
   created) rather than writing an `UNCERTAIN` row. Keeps the map asserting only
   real restrictions; avoids flooding it with low-value yellow pins.

## Reframing the "33 cells"

Research scope is unchanged: all 9 categories × 3 states (27 combos) + the
federal floor are examined and web-verified. The *written* artifact is much
smaller because three structural reductions apply:

| Reduction | Justification |
|---|---|
| `PRIVATE_PROPERTY` dropped (−3 rows) | Decision 2; no pilot source emits it. |
| `FEDERAL_PROPERTY` + `AIRPORT_SECURE` live only as `US` cells, not duplicated per state (−6 rows) | Genuinely federal-uniform; parent spec §1: "Federal-uniform rows use `state: US`." Per-state duplication is pure maintenance burden. |
| No-prohibition combos omitted, not written as `UNCERTAIN` | Decision 4. |

**Net: 12 written cells + 12 documented omissions.** The omissions are
researched conclusions, not gaps.

### Consequence: dry-run report noise

`apply_state_law` records every missing `(state, category)` in the dry-run
report's "needs research" list. Intentional omissions will appear there on every
run. For the pilot we accept this noise and maintain a separate
`docs/importer/OMISSIONS.md` documenting each intentional omission with the
citation that *no* categorical prohibition exists. A report enhancement to
cross-reference and suppress documented omissions is a deferred follow-up
(importer-engine code, out of Phase 3 scope).

## Cell inventory

Citations below are draft determinations from training knowledge. Each is
web-verified against current statute during implementation and signed off by the
user per cell. **WRITE** = gets a YAML row. **OMIT** = documented in
`OMISSIONS.md`, no row, candidate dropped.

### Federal-uniform `US` cells (3 written)

| Category | Status | Conf. | Draft citation | `source_filter` |
|---|---|---|---|---|
| `FEDERAL_PROPERTY` | NO_GUN | high | 18 USC §930(a) | `[gsa, hifld_military]` |
| `AIRPORT_SECURE` | NO_GUN | high | 49 USC §46505; 49 CFR §1540 (sterile/secured area) | `[faa]` |
| `STATE_LOCAL_GOVT` | NO_GUN | high | 18 USC §930(a) (federal courthouse fallback) | `[hifld_courts]` *(exists — keep)* |

### Per-state cells

| State | Category | Decision | Status | Conf. | Draft citation / reason |
|---|---|---|---|---|---|
| TX | `STATE_LOCAL_GOVT` | WRITE | NO_GUN | high | TX Penal Code §46.03(a)(3) (courthouses/court offices) |
| TX | `SCHOOL_K12` | WRITE | NO_GUN | high | TX Penal Code §46.03(a)(1) |
| TX | `BAR_ALCOHOL` | WRITE | NO_GUN | medium | §46.03(a)(7)/§46.035(b)(1) (51% premises + TABC sign) |
| TX | `COLLEGE_UNIVERSITY` | OMIT | — | — | Campus carry — Gov't Code §411.2031/SB 11. LTC carry *allowed* at public campuses. **Must not mark NO_GUN.** |
| TX | `HEALTHCARE` | OMIT | — | — | No categorical hospital prohibition; posting-dependent |
| TX | `PLACE_OF_WORSHIP` | OMIT | — | — | Post-2019 (SB 535) carry allowed unless posted |
| TX | `SPORTS_ENTERTAINMENT` | OMIT *(judgment)* | — | — | §46.03(a)(5)/§46.035(b)(2) restrict racetracks + school/pro sporting *events*; OSM venue tags can't reliably isolate those. Conservative omit. |
| FL | `STATE_LOCAL_GOVT` | WRITE | NO_GUN | high | Fla. Stat. §790.06(12)(a) (courthouse) |
| FL | `SCHOOL_K12` | WRITE | NO_GUN | high | Fla. Stat. §790.115(2)(a) |
| FL | `COLLEGE_UNIVERSITY` | WRITE | NO_GUN | high | Fla. Stat. §790.06(12)(a)(13) (no FL campus carry) |
| FL | `BAR_ALCOHOL` | WRITE | NO_GUN | medium | §790.06(12)(a)(12) (portion primarily for alcohol) |
| FL | `HEALTHCARE` | OMIT | — | — | No categorical prohibition |
| FL | `PLACE_OF_WORSHIP` | OMIT | — | — | Allowed unless posted / on school property |
| FL | `SPORTS_ENTERTAINMENT` | OMIT *(judgment)* | — | — | §790.06(12)(a) restricts athletic *events*, not all venues — same OSM problem |
| PA | `STATE_LOCAL_GOVT` | WRITE | NO_GUN | high | 18 Pa.C.S. §913 (court facility) |
| PA | `SCHOOL_K12` | WRITE | NO_GUN | high *(maybe medium)* | 18 Pa.C.S. §912 — "lawful purpose" defense; confidence is a review item |
| PA | `COLLEGE_UNIVERSITY` | OMIT | — | — | No state categorical prohibition; institution-policy dependent |
| PA | `BAR_ALCOHOL` | OMIT | — | — | No categorical bar prohibition for license holders |
| PA | `HEALTHCARE` | OMIT | — | — | No categorical prohibition |
| PA | `PLACE_OF_WORSHIP` | OMIT | — | — | No prohibition |
| PA | `SPORTS_ENTERTAINMENT` | OMIT | — | — | No clear categorical venue prohibition |

**Tally: 12 written (3 `US` + TX 3 + FL 4 + PA 2), 12 documented omissions.**
`FEDERAL_PROPERTY`/`AIRPORT_SECURE` per-state are covered by the `US` cells, not
omitted and not duplicated.

### Flagged judgment calls (settled during cell-by-cell review)

1. **`SPORTS_ENTERTAINMENT` (TX/FL):** statutes restrict sporting *events*, but
   the OSM source tags *venues*. Omit for pilot to avoid over-asserting; could be
   overridden to `NO_GUN low` with a strong condition.
2. **`HEALTHCARE` omitted in all three states** → the `hifld_hospitals` source
   produces zero pins in the pilot. Legally correct; the source stays dormant
   until a state with a real hospital prohibition is added.
3. **PA `SCHOOL_K12` confidence** — high vs medium given the §912 lawful-purpose
   defense.

## `source_filter` and the lookup drop-edge

`StateLawTable.lookup()` matches `(state, category)` first, then falls back to
`(US, category)`. `apply_state_law` then drops the candidate if the matched
cell's `source_filter` excludes the candidate's source — it does **not** fall
through to the `US` cell. This is a sharp edge: a state row that matches the
category but filters out the source silently drops candidates.

Mitigation in this design: written cells carry `source_filter` only where it
reflects the genuine emitting source(s), and every pilot source that emits a
given category is included in that category's filter. The source-filter test
(below) guards the drop-edge against regression.

## Tests (`importer/tests/test_state_laws.py`)

- **Rewrite the existing canary:** `test_production_states_yaml_parses` currently
  asserts `lookup("TX", STATE_LOCAL_GOVT).state == "US"` (Phase 2 fallback).
  Adding the TX `STATE_LOCAL_GOVT` row makes that resolve to `"TX"`. Rewrite to
  assert the new behavior — it is the canary proving the table changed.
- **Pilot-resolution test:** for each of the 12 written combos, `lookup()`
  returns a cell with the expected `state`, `default_status`, and `confidence`.
- **Campus-carry guard test:** `lookup("TX", COLLEGE_UNIVERSITY)` and
  `lookup("PA", COLLEGE_UNIVERSITY)` both return `None`. Codifies the worst-case
  error from the risk register.
- **Omission test:** every combo listed in `OMISSIONS.md` resolves to `None`
  (parametrized).
- **Source-filter test:** a `gsa` candidate resolves `FEDERAL_PROPERTY`; an `osm`
  candidate does not (drop-edge stays correct).
- Pydantic validates enum/status/date types at load — no separate schema test.

## Deliverables

1. `data/state_laws/states.yaml` — 12 cells (1 existing kept, 11 added).
2. `docs/importer/OMISSIONS.md` — 12 documented "no prohibition" combos with
   reasoning and the citation that no categorical prohibition exists.
3. `importer/tests/test_state_laws.py` — rewritten production assertions + new
   structural/guard tests.
4. Status updates: parent spec §8 (Phase 3 → complete), `CLAUDE.md` status line,
   memory `project_pre_populate_roadmap.md` (Phase 3 done → Phase 4 next).

## Out of scope (Phase 3)

- No importer engine changes (report-noise suppression for omissions is a
  deferred follow-up).
- No app-side or Supabase migration changes.
- No actual import run — Phase 3 only fills the table; Phase 4 consumes it.

## Success criteria

- All 12 written cells present with `last_verified_date: 2026-05-31`, web-verified
  citations, and user sign-off per cell.
- `OMISSIONS.md` documents all 12 intentional omissions with reasoning.
- `lookup()` resolves all 12 pilot combos correctly and returns `None` for the
  campus-carry guard combos and all documented omissions.
- `importer/tests/` passes; the rewritten production canary reflects the new table.

# Phase 3 — State-Law Table Seeding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Seed `data/state_laws/states.yaml` with the 12 web-verified, user-approved legal-classification cells for TX + FL + PA + federal-uniform `US`, document the 12 intentional omissions, and lock the table's structural contract with tests.

**Architecture:** The importer's `StateLawTable.lookup()` joins `(state, category)` with fallback to `(US, category)`; `apply_state_law` drops candidates whose matched cell's `source_filter` excludes their source. We write only cells with a real categorical statutory prohibition (12), omit no-prohibition combos (12, documented), and consolidate federal-uniform categories (`FEDERAL_PROPERTY`, `AIRPORT_SECURE`, federal-courthouse `STATE_LOCAL_GOVT`) into `US` cells rather than per-state duplicates. Tests assert structural design decisions (resolution, campus-carry guard, omissions, source-filter drop-edge) — not exact citation text, which is human-verified.

**Tech Stack:** Python 3.12, pydantic v2, PyYAML, pytest. Importer venv at `importer/.venv`.

**Design reference:** `docs/superpowers/specs/2026-05-31-phase3-state-law-seeding-design.md`

---

## Conventions for every test run

All commands run from the **`importer/`** directory using its venv:

```powershell
cd importer
.venv\Scripts\python -m pytest tests/test_state_laws.py -v
```

(Return to repo root for `git` commands.)

---

## Task 1: Legal research & per-cell sign-off (human-in-the-loop)

**Files:** none yet — this task produces the *approved cell values* used in Task 2.

This task is legal research, not code. It cannot be TDD'd. Its output is a confirmed value for each of the 12 written cells (status, confidence, citation, conditions) and confirmation of the 12 omissions. The drafts below are the starting point; web-verification may correct a section number, split a citation, or adjust a confidence.

- [ ] **Step 1: Web-verify each citation against current statute.**

For each written cell, search for the current statute text and confirm the section number and that it still prohibits carry for the stated venue class. Sources of record:
- TX: Texas Penal Code §46.03 / §46.035 (statutes.capitol.texas.gov)
- FL: Florida Statutes §790.06, §790.115 (leg.state.fl.us)
- PA: 18 Pa.C.S. §912, §913 (legis.state.pa.us)
- Federal: 18 USC §930, 49 USC §46505, 49 CFR §1540 (uscode.house.gov / ecfr.gov)

Record any deviation from the draft citation below.

- [ ] **Step 2: Present each cell to the user for sign-off.**

Present the 12 cells (in the batches: `US` federal, TX, FL, PA) with verified citation + status + confidence + conditions. The user is the final legal authority. Capture corrections. Specifically resolve the three flagged judgment calls from the spec:
1. `SPORTS_ENTERTAINMENT` TX/FL — confirm **omit** (vs `NO_GUN low`).
2. `HEALTHCARE` all three — confirm **omit** (acknowledging `hifld_hospitals` yields no pilot pins).
3. PA `SCHOOL_K12` — confirm **high** vs **medium** confidence. (Tests in Task 2 do not pin this value, so either is fine.)

- [ ] **Step 3: Record the approved values.**

Write the approved values into a scratch note (or directly update the draft YAML in Task 2 Step 3). No commit in this task — nothing is in a file yet.

---

## Task 2: Encode the table and lock it with tests

**Files:**
- Test: `importer/tests/test_state_laws.py` (rewrite the production canary, add 4 new tests)
- Modify: `data/state_laws/states.yaml` (refresh the 1 existing `US` cell, add 11 cells)

- [ ] **Step 1: Rewrite the test file's production-table tests (RED).**

Open `importer/tests/test_state_laws.py`. **Keep** the `tmp_path`-based fixture tests (`test_load_state_laws_parses_all_rows`, `test_lookup_returns_state_specific_first`, `test_lookup_falls_back_to_us_when_no_state_row`, `test_lookup_returns_none_when_no_row_anywhere`) — they test the loader against a synthetic fixture and stay valid. **Delete** the existing `test_production_states_yaml_parses` (it asserts the old Phase-2 fallback and will be replaced). Then append the following:

```python
from importer.candidate import Candidate, CoordQuality
from importer.stages.apply_state_law import ApplyStateLawStats, apply_state_law

PROD_TABLE = Path(__file__).parent.parent.parent / "data" / "state_laws" / "states.yaml"


# (candidate_state, category, expected_cell_state) for the 12 written cells.
# Federal-uniform categories resolve to the US cell via fallback.
WRITTEN_RESOLUTIONS = [
    ("TX", RestrictionTag.FEDERAL_PROPERTY, "US"),
    ("FL", RestrictionTag.FEDERAL_PROPERTY, "US"),
    ("PA", RestrictionTag.FEDERAL_PROPERTY, "US"),
    ("TX", RestrictionTag.AIRPORT_SECURE, "US"),
    ("FL", RestrictionTag.AIRPORT_SECURE, "US"),
    ("PA", RestrictionTag.AIRPORT_SECURE, "US"),
    ("TX", RestrictionTag.STATE_LOCAL_GOVT, "TX"),
    ("FL", RestrictionTag.STATE_LOCAL_GOVT, "FL"),
    ("PA", RestrictionTag.STATE_LOCAL_GOVT, "PA"),
    ("TX", RestrictionTag.SCHOOL_K12, "TX"),
    ("FL", RestrictionTag.SCHOOL_K12, "FL"),
    ("PA", RestrictionTag.SCHOOL_K12, "PA"),
    ("TX", RestrictionTag.BAR_ALCOHOL, "TX"),
    ("FL", RestrictionTag.BAR_ALCOHOL, "FL"),
    ("FL", RestrictionTag.COLLEGE_UNIVERSITY, "FL"),
]

# Intentional omissions (no row anywhere -> lookup returns None). 12 combos.
OMISSIONS = [
    ("TX", RestrictionTag.COLLEGE_UNIVERSITY),
    ("TX", RestrictionTag.HEALTHCARE),
    ("TX", RestrictionTag.PLACE_OF_WORSHIP),
    ("TX", RestrictionTag.SPORTS_ENTERTAINMENT),
    ("FL", RestrictionTag.HEALTHCARE),
    ("FL", RestrictionTag.PLACE_OF_WORSHIP),
    ("FL", RestrictionTag.SPORTS_ENTERTAINMENT),
    ("PA", RestrictionTag.COLLEGE_UNIVERSITY),
    ("PA", RestrictionTag.BAR_ALCOHOL),
    ("PA", RestrictionTag.HEALTHCARE),
    ("PA", RestrictionTag.PLACE_OF_WORSHIP),
    ("PA", RestrictionTag.SPORTS_ENTERTAINMENT),
]


@pytest.mark.parametrize("cand_state, category, expected_state", WRITTEN_RESOLUTIONS)
def test_written_cells_resolve_to_no_gun(cand_state, category, expected_state):
    table = load_state_laws(PROD_TABLE)
    cell = table.lookup(cand_state, category)
    assert cell is not None, f"{cand_state}/{category.name} must resolve to a cell"
    assert cell.state == expected_state
    assert cell.default_status == "NO_GUN"
    assert cell.citation  # non-empty
    assert cell.last_verified_date is not None


def test_bar_cells_are_medium_confidence():
    table = load_state_laws(PROD_TABLE)
    for st in ("TX", "FL"):
        cell = table.lookup(st, RestrictionTag.BAR_ALCOHOL)
        assert cell is not None and cell.state == st
        assert cell.confidence == "medium"


@pytest.mark.parametrize("state", ["TX", "PA"])
def test_campus_carry_is_not_pre_asserted(state):
    # TX (SB11 campus carry) and PA (institution-policy) must NOT pre-assert NO_GUN
    # at colleges. A row here would be the worst-case error in the risk register.
    table = load_state_laws(PROD_TABLE)
    assert table.lookup(state, RestrictionTag.COLLEGE_UNIVERSITY) is None


@pytest.mark.parametrize("state, category", OMISSIONS)
def test_documented_omissions_have_no_cell(state, category):
    table = load_state_laws(PROD_TABLE)
    assert table.lookup(state, category) is None


def _candidate(source: str, state: str, category: RestrictionTag) -> Candidate:
    return Candidate(
        source=source,
        source_external_id=f"{source}-{state}-{category.name}",
        source_dataset_version="v1",
        name="X",
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.PRECISE,
        category=category,
        state=state,
    )


def test_source_filter_drop_edge_holds():
    # FEDERAL_PROPERTY US cell is source_filter=[gsa, hifld_military].
    # A gsa candidate is classified; an osm candidate is dropped (not classified).
    table = load_state_laws(PROD_TABLE)

    stats_ok = ApplyStateLawStats()
    classified = list(
        apply_state_law([_candidate("gsa", "TX", RestrictionTag.FEDERAL_PROPERTY)],
                        table=table, stats=stats_ok)
    )
    assert len(classified) == 1
    assert stats_ok.classified == 1

    stats_drop = ApplyStateLawStats()
    dropped = list(
        apply_state_law([_candidate("osm", "TX", RestrictionTag.FEDERAL_PROPERTY)],
                        table=table, stats=stats_drop)
    )
    assert dropped == []
    assert stats_drop.dropped_no_cell == 1
```

- [ ] **Step 2: Run the tests to verify they fail (RED).**

```powershell
cd importer
.venv\Scripts\python -m pytest tests/test_state_laws.py -v
```

Expected: the new `test_written_cells_resolve_to_no_gun`, `test_bar_cells_are_medium_confidence`, and `test_source_filter_drop_edge_holds` FAIL (table currently has only the `US` `STATE_LOCAL_GOVT` cell, so TX/FL/PA and `FEDERAL_PROPERTY` lookups return `None`). `test_campus_carry_is_not_pre_asserted` and `test_documented_omissions_have_no_cell` will already PASS (no rows exist for those combos) — that is correct; they are regression guards.

- [ ] **Step 3: Write the table content (GREEN).**

Replace the entire contents of `data/state_laws/states.yaml` with the following. Use the values approved in Task 1 — adjust any citation/condition/confidence the user corrected. The existing `US` `STATE_LOCAL_GOVT` cell is refreshed (new `last_verified_date`, updated notes/conditions).

```yaml
# Maintained state-law lookup table for the CCW Map pre-populate-pins importer.
# Schema: see ../../docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md §1.
# Phase 3 seeding: see ../../docs/superpowers/specs/2026-05-31-phase3-state-law-seeding-design.md
# License: CC0 — see LICENSE next to this file.
# Maintenance: quarterly review; bump last_verified_date even if unchanged.
# Intentional omissions (combos with no categorical prohibition) are documented
# in ../../docs/importer/OMISSIONS.md — do NOT add UNCERTAIN rows for them.

# ── Federal-uniform cells (state: US) ────────────────────────────────
- state: US
  category: FEDERAL_PROPERTY
  default_status: NO_GUN
  confidence: high
  conditions:
    - "Federal facilities: possession of a firearm by a non-exempt person is prohibited."
  citation: "18 USC §930(a)"
  last_verified_date: 2026-05-31
  source_filter:
    - gsa
    - hifld_military
  notes: |
    Federal-uniform. Applies to GSA-owned/leased federal property and HIFLD
    military installations nationwide. 18 USC §930 exempts law enforcement and
    certain official purposes; pre-populated pins assert the default prohibition.

- state: US
  category: AIRPORT_SECURE
  default_status: NO_GUN
  confidence: high
  conditions:
    - "Applies to the TSA sterile/secured area past the screening checkpoint."
    - "Unloaded, cased firearms in checked baggage are permitted under TSA rules and are not what this pin asserts."
  citation: "49 USC §46505; 49 CFR §1540"
  last_verified_date: 2026-05-31
  source_filter:
    - faa
  notes: |
    Federal-uniform. The FAA NPIAS reference point marks the airport; the
    prohibition legally attaches to the sterile/secured area past screening.

- state: US
  category: STATE_LOCAL_GOVT
  default_status: NO_GUN
  confidence: high
  conditions:
    - "Federal courthouses: carry by non-officers prohibited."
  citation: "18 USC §930(a)"
  last_verified_date: 2026-05-31
  source_filter:
    - hifld_courts
  notes: |
    Federal-uniform fallback for courthouses not matched by a state-specific
    STATE_LOCAL_GOVT row (e.g. outside the pilot states). State rows (TX/FL/PA)
    take precedence via lookup ordering.

# ── Texas ────────────────────────────────────────────────────────────
- state: TX
  category: STATE_LOCAL_GOVT
  default_status: NO_GUN
  confidence: high
  conditions:
    - "On the premises of a government court or offices used by the court."
  citation: "TX Penal Code §46.03(a)(3)"
  last_verified_date: 2026-05-31
  source_filter:
    - hifld_courts
  notes: |
    Pre-populated TX pins default has_posted_signage=false: TX 30.06/30.07
    signage is format-binding and unverifiable from external data.

- state: TX
  category: SCHOOL_K12
  default_status: NO_GUN
  confidence: high
  conditions:
    - "On the physical premises of a K-12 school or educational institution."
  citation: "TX Penal Code §46.03(a)(1)"
  last_verified_date: 2026-05-31
  source_filter:
    - nces

- state: TX
  category: BAR_ALCOHOL
  default_status: NO_GUN
  confidence: medium
  conditions:
    - "Premises deriving 51%+ of revenue from on-premises alcohol sales."
    - "Must display the TABC 51% (red) sign."
  citation: "TX Penal Code §46.03(a)(7); §46.035(b)(1)"
  last_verified_date: 2026-05-31
  source_filter:
    - osm
  notes: |
    Generic OSM bar/pub tagging cannot confirm the 51% TABC designation, so
    confidence is medium. Users verify with photos of the red sign.

# ── Florida ──────────────────────────────────────────────────────────
- state: FL
  category: STATE_LOCAL_GOVT
  default_status: NO_GUN
  confidence: high
  conditions:
    - "Any courthouse."
  citation: "Fla. Stat. §790.06(12)(a)"
  last_verified_date: 2026-05-31
  source_filter:
    - hifld_courts

- state: FL
  category: SCHOOL_K12
  default_status: NO_GUN
  confidence: high
  conditions:
    - "On the property of any K-12 school, school bus, or school bus stop."
  citation: "Fla. Stat. §790.115(2)(a)"
  last_verified_date: 2026-05-31
  source_filter:
    - nces

- state: FL
  category: COLLEGE_UNIVERSITY
  default_status: NO_GUN
  confidence: high
  conditions:
    - "Any college or university facility. Florida does not authorize campus carry."
  citation: "Fla. Stat. §790.06(12)(a)(13)"
  last_verified_date: 2026-05-31
  source_filter:
    - ipeds

- state: FL
  category: BAR_ALCOHOL
  default_status: NO_GUN
  confidence: medium
  conditions:
    - "Any portion of an alcohol-licensed establishment primarily devoted to on-premises consumption."
  citation: "Fla. Stat. §790.06(12)(a)(12)"
  last_verified_date: 2026-05-31
  source_filter:
    - osm
  notes: |
    OSM venue tags cannot confirm the "primarily devoted" portion test, so
    confidence is medium.

# ── Pennsylvania ─────────────────────────────────────────────────────
- state: PA
  category: STATE_LOCAL_GOVT
  default_status: NO_GUN
  confidence: high
  conditions:
    - "Court facility (and adjacent areas posted as such)."
  citation: "18 Pa.C.S. §913"
  last_verified_date: 2026-05-31
  source_filter:
    - hifld_courts

- state: PA
  category: SCHOOL_K12
  default_status: NO_GUN
  confidence: high
  conditions:
    - "In the buildings or on the grounds of an elementary or secondary school."
  citation: "18 Pa.C.S. §912"
  last_verified_date: 2026-05-31
  source_filter:
    - nces
  notes: |
    §912 provides a defense for possession for a lawful purpose. Confidence
    reviewed at high for the categorical premises prohibition; revisit if the
    lawful-purpose defense materially weakens the assertion.
```

> If Task 1 settled PA `SCHOOL_K12` at `medium`, change its `confidence` value here. The tests do not pin it.

- [ ] **Step 4: Run the tests to verify they pass (GREEN).**

```powershell
cd importer
.venv\Scripts\python -m pytest tests/test_state_laws.py -v
```

Expected: all tests PASS, including the full `tests/` suite is unaffected. Optionally run the whole suite:

```powershell
.venv\Scripts\python -m pytest -q
```

Expected: all pass (notably `tests/stages/test_apply_state_law.py` still passes — it uses its own synthetic table, not the production file).

- [ ] **Step 5: Commit.**

```powershell
cd ..
git add data/state_laws/states.yaml importer/tests/test_state_laws.py
git commit -m "feat(state-laws): seed TX/FL/PA + federal cells in states.yaml

12 web-verified, user-approved NO_GUN cells (3 US federal-uniform + TX 3 +
FL 4 + PA 2). Structural tests lock resolution, the campus-carry guard
(TX/PA colleges resolve to None), documented omissions, and the source_filter
drop-edge.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Document the intentional omissions

**Files:**
- Create: `docs/importer/OMISSIONS.md`

- [ ] **Step 1: Write `docs/importer/OMISSIONS.md`.**

```markdown
# State-Law Table — Intentional Omissions

The pre-populate importer's `data/state_laws/states.yaml` contains a cell **only**
where a state has a *categorical statutory prohibition* on carry for that venue
class. Where carry is affirmatively allowed, or where the restriction depends on
owner posting rather than statute, we **omit** the cell: `apply_state_law` then
drops the candidate and creates no pin. This keeps the map asserting only real
`NO_GUN` restrictions.

Each omission below is a researched conclusion, not a gap. These combos will
appear in the importer dry-run report's "missing cells / needs research" list;
that is expected noise — cross-reference this file. Do **not** add `UNCERTAIN`
rows for them.

| State | Category | Why no cell (no categorical statutory prohibition) |
|---|---|---|
| TX | COLLEGE_UNIVERSITY | Campus carry — LTC holders may carry concealed at public universities (Gov't Code §411.2031 / SB 11). Private institutions may opt out by posting. **Asserting NO_GUN here would be wrong.** |
| TX | HEALTHCARE | No categorical hospital prohibition; restriction is owner-posting (TX 30.06/30.07). |
| TX | PLACE_OF_WORSHIP | Post-2019 (SB 535) carry is allowed in places of worship unless posted. |
| TX | SPORTS_ENTERTAINMENT | §46.03(a)(5)/§46.035(b)(2) restrict racetracks and school/collegiate/pro sporting *events*; the OSM source tags *venues* and cannot reliably isolate those. Conservative omit. |
| FL | HEALTHCARE | No categorical prohibition; owner-posting. |
| FL | PLACE_OF_WORSHIP | Allowed unless posted; restriction only when on dedicated school property. |
| FL | SPORTS_ENTERTAINMENT | §790.06(12)(a) restricts athletic *events*, not all venues — same OSM tagging problem. |
| PA | COLLEGE_UNIVERSITY | No state categorical prohibition; depends on institution policy. |
| PA | BAR_ALCOHOL | No categorical bar prohibition for license holders. |
| PA | HEALTHCARE | No categorical prohibition. |
| PA | PLACE_OF_WORSHIP | No prohibition. |
| PA | SPORTS_ENTERTAINMENT | No clear categorical venue prohibition. |

`FEDERAL_PROPERTY` and `AIRPORT_SECURE` are **not** omitted per-state — they are
federal-uniform and covered by `state: US` cells in `states.yaml`.

**Maintenance:** when a state's law changes (e.g., a new campus-carry repeal) or
a new source is added that emits one of these categories, revisit the relevant
row here and in `states.yaml` together.
```

- [ ] **Step 2: Commit.**

```powershell
git add docs/importer/OMISSIONS.md
git commit -m "docs(importer): document the 12 intentional state-law omissions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Status updates

**Files:**
- Modify: `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md` (Phase 3 row in §8)
- Modify: `CLAUDE.md` (Current Status line)
- Modify: `C:\Users\camil\.claude\projects\C--Users-camil-projects-ccwmap\memory\project_pre_populate_roadmap.md`

- [ ] **Step 1: Mark Phase 3 complete in the parent spec's phasing table.**

In `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md`, find the §8 phasing table row for Phase 3 and append a completion marker to its "Exit criteria" cell, e.g. prepend `✅ DONE — ` to the exit-criteria text (match the style used for Phases 0–2 if they were marked; if not, add `**(DONE 2026-05-31)**` to the Phase row's Phase cell).

- [ ] **Step 2: Update the `CLAUDE.md` status line.**

In `CLAUDE.md`, find the `**Current Status:**` line under "Project Overview" and the "Next phase: Phase 3 state-law table seeding" text. Update it to reflect Phase 3 complete and Phase 4 (pilot wave 1: federal floor — HIFLD courthouses + GSA + HIFLD military for TX/FL/PA) as next. Example:

```markdown
**Current Status:** v0.6.0 in production — pre-populate Phases 0–3 complete (schema, viewport sync, importer skeleton, state-law table seeded for TX/FL/PA). Next phase: Phase 4 pilot wave 1 (federal floor — HIFLD courthouses + GSA federal property + HIFLD military for TX/FL/PA). See `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md` §8.
```

- [ ] **Step 3: Update the roadmap memory.**

Edit `C:\Users\camil\.claude\projects\C--Users-camil-projects-ccwmap\memory\project_pre_populate_roadmap.md` so the body reflects: phases 0–3 DONE; NEXT = Phase 4 pilot wave 1 (federal floor for TX/FL/PA). Keep the frontmatter (`name`, `description`, `metadata`) intact; update the description hook accordingly. (The `MEMORY.md` index line may also need its hook text refreshed.)

- [ ] **Step 4: Commit.**

```powershell
git add docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md CLAUDE.md
git commit -m "docs: mark pre-populate Phase 3 complete; Phase 4 next

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

(The memory file lives outside the repo and is not committed.)

---

## Done criteria

- `importer/tests/test_state_laws.py` passes, including the campus-carry guard and source-filter drop-edge tests.
- `data/state_laws/states.yaml` has 12 cells, all dated `2026-05-31`, all user-approved.
- `docs/importer/OMISSIONS.md` documents all 12 omissions.
- Status updated in spec §8, `CLAUDE.md`, and the roadmap memory.

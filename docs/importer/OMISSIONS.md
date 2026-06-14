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
| TX | COLLEGE_UNIVERSITY | Campus carry — LTC holders may carry concealed at public universities (Gov't Code §411.2031 / SB 11). Private institutions may opt out by posting. **Asserting NO_GUN here would be wrong.** As of Phase 5 the `ipeds` source actively emits TX college candidates; they drop at `apply_state_law` and appear in the dry-run "missing cells" list — expected, not a gap. |
| TX | HEALTHCARE | No categorical hospital prohibition; restriction is owner-posting (TX 30.06/30.07). |
| TX | PLACE_OF_WORSHIP | Post-2019 (SB 535) carry is allowed in places of worship unless posted. |
| TX | SPORTS_ENTERTAINMENT | §46.03(a)(5)/§46.035(b)(2) restrict racetracks and school/collegiate/pro sporting *events*; the OSM source tags *venues* and cannot reliably isolate those. Conservative omit. |
| FL | HEALTHCARE | No categorical prohibition; owner-posting. |
| FL | PLACE_OF_WORSHIP | Allowed unless posted; restriction only when on dedicated school property. |
| FL | SPORTS_ENTERTAINMENT | §790.06(12)(a) restricts athletic *events*, not all venues — same OSM tagging problem. |
| PA | COLLEGE_UNIVERSITY | No state categorical prohibition; depends on institution policy. As of Phase 5 the `ipeds` source actively emits PA college candidates; they drop at `apply_state_law` and appear in the dry-run "missing cells" list — expected, not a gap. |
| PA | BAR_ALCOHOL | No categorical bar prohibition for license holders. |
| PA | HEALTHCARE | No categorical prohibition. |
| PA | PLACE_OF_WORSHIP | No prohibition. |
| PA | SPORTS_ENTERTAINMENT | No clear categorical venue prohibition. |

`FEDERAL_PROPERTY` and `AIRPORT_SECURE` are **not** omitted per-state — they are
federal-uniform and covered by `state: US` cells in `states.yaml`.

**Maintenance:** when a state's law changes (e.g., a new campus-carry repeal) or
a new source is added that emits one of these categories, revisit the relevant
row here and in `states.yaml` together.

# State-law lookup table

This directory holds the maintained legal classification table consulted by the
[pre-populate-pins importer](../../importer/README.md). Every pre-populated pin
inherits its status, citation, confidence, and verified date from a row here.

Schema and confidence definitions: see
[the design spec](../../docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md#1--sources-classification-and-the-state-law-lookup-table)
§1 — *Sources, classification, and the state-law lookup table*.

## Editing

1. Edit `states.yaml` directly. The file is a list of cells; ordering does not matter (the loader matches by `(state, category)`).
2. Bump `last_verified_date` on every cell you reviewed, **even if the citation did not change** — the date is the evidence that the cell was checked this cycle.
3. PR with a one-line description per cell touched. Cells older than 6 months are flagged in dry-run reports; older than 12 months trigger UI warnings on affected pins.

## Coverage roadmap

| Phase | Cells covered |
|---|---|
| 2 (this) | `(US, STATE_LOCAL_GOVT)` only — proves the loader and one HIFLD source end-to-end. |
| 3 | TX + FL + PA × 10 categories + 3 federal-uniform US cells (33 cells). |
| 8+ | National rollout: all 50 states × 10 categories. |

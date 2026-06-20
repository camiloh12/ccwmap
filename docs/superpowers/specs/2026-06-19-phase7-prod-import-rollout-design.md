# Phase 7 — Production Pre-Populate Import Rollout (design)

**Date:** 2026-06-19
**Status:** Approved design; pending implementation plans
**Supersedes context:** `docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md` §8 (Phase 7 row)

## Purpose

All pre-populate phases (0–6) are merged to master and **staging-validated** — **23,825 system-owned pins** across TX/FL/PA — but **no pre-populated pin has ever been written to production**. Phase 7 is the first (and effectively irreversible) production import. This document is the rollout design: what must be true before any prod write, the order of operations, the go/no-go gate, and rollback.

The staging baseline this rollout reproduces (verified 2026-06-19 against `miihmfhnsfmwgrvgayns`):

| source | status | count |
|---|---|---|
| nces | NO_GUN (2) | 15,432 |
| gsa | NO_GUN (2) | 4,221 |
| osm | **UNCERTAIN (1)** | 3,275 |
| hifld_courts | NO_GUN (2) | 470 |
| ipeds | NO_GUN (2) | 290 |
| hifld_military | NO_GUN (2) | 77 |
| faa | NO_GUN (2) | 60 |
| **total** | | **23,825** |

≈20,550 hard-red NO_GUN pins plus 3,275 yellow UNCERTAIN (the OSM bars, which cannot satisfy the TX 51% / FL "primarily-devoted" revenue test).

## Overall shape: two sequential stages with a hard gate

```
Stage A: Pre-import app release ──(ship to stores + wait for adoption)──┐
  · verify-locally caveat (PinDialog)                                   │  GATE
  · in-app ODbL attribution (Settings)                                  ▼
Stage B: The prod import (combined 7-source apply via CI)
```

**Stage B does not begin until Stage A's release is live in the stores and adopted.** This is the load-bearing ordering: the flood of red NO_GUN pins must land only after the "verify locally" hedge and the ODbL attribution are already on users' screens. Old-app users cannot render new UI and there is no forced-update mechanism, so the adoption wait is the only mitigation for the un-hedged-pin window.

---

## Stage A — pre-import app release (planned separately)

Two user-facing additions. Both are OSM/legal-driven and both gate the import. This stage gets its **own brainstorm + implementation plan** (smaller scope); this section captures only the requirements and the known integration points so the gate is well-defined.

### A1. "Verify locally" caveat in the pin dialog

- **Why:** Every NO_GUN pin currently renders hard-red with no hedge. The classifications are state-law *inferences* (risk-register top row). The OSM bars are explicitly UNCERTAIN. Users need a visible "confirm locally" note before a 20k-red-pin flood lands.
- **Current state:** `PinDialog` (`lib/presentation/widgets/pin_dialog.dart`) receives **no provenance at all** — only name/status/tags/screening/signage. `SupabasePinDto` already parses `source`, `confidence`, `legal_citation`, `legal_citation_verified_date` from the server, but those fields are **not** carried on the domain `Pin` model or passed into the dialog.
- **Work implied (to be detailed in the sub-plan):** carry `source` / `confidence` / `legalCitation` from DTO → domain `Pin` → `map_viewmodel` → `PinDialog`; render a hedge banner. Trigger keys on system-owned pins (`source != 'user'`), with stronger emphasis for `confidence != 'high'` and for UNCERTAIN pins. Exact copy + trigger logic decided in the sub-plan.

### A2. In-app ODbL attribution

- **Why:** OSM-derived pins become publicly visible in-app. ODbL requires attribution for a produced work. (Share-alike is already satisfied by the public `odbl-dumps` Storage bucket; in-app attribution is the missing user-facing piece.)
- **Current state:** the Settings screen (`lib/presentation/screens/settings_screen.dart`) has **no About/Legal/attributions section** at all.
- **Work implied:** add an About/Legal section (or dedicated attributions page) crediting OpenStreetMap contributors (ODbL) + MapTiler, with the public dump URL. Placement decided in the sub-plan.

### A3. Release

Ship A1 + A2 together in one release tag via the existing GIT_FLOW (`release/v*` → TestFlight + Play Internal → promote with `v*.*.*`). Pilot version number TBD in the sub-plan. After the public-store release, **wait for adoption** (≥7 days clean health-check + an adoption check) before opening Stage B.

---

## Stage B — the prod import

### B0. Prep (all before any prod write)

1. **Fill the importer's prod target.** `importer/config.yaml` currently has `prod.project_ref` / `prod.url` = `REPLACE-WITH-PROD-PROJECT-REF`. The write URL is built from this, so a prod apply fails outright until it is set to `gqbxloaqamokbolcvesg` / `https://gqbxloaqamokbolcvesg.supabase.co`.

2. **Apply migration 009 to prod.** 009 swaps the partial index for a non-partial `UNIQUE (source, source_external_id)` index that the importer's `ON CONFLICT` upsert needs. It is **additive and independent of the app release** — the old app never inserts a non-null `source_external_id`, so 009 imposes no new constraint on shipped clients.
   - **Mechanism (decided):** temporarily repoint `.mcp.json` supabase ref to prod (`gqbxloaqamokbolcvesg`), restart, apply 009 via MCP `apply_migration` (which records it in `schema_migrations`), then repoint back to staging. Operator-gated — Claude does not repoint MCP without explicit confirmation.
   - **Optional tracking backfill:** re-apply 008 via the same MCP path to register its (currently missing) `schema_migrations` row. 008 is idempotent and v0.6.0 (carrying `toJsonForUpdate`) is already live, so re-applying its grants is safe.

3. **Verify prod schema parity (read-only, before apply).** With MCP pointed at prod (or via the prod dashboard SQL editor), confirm: 008 provenance columns + `get_pins_in_view` RPC present; `deny_system_user_insert/update/delete` RLS policies present; system user `81775f8b-1a6a-47d6-b793-e9ab7e38634e` exists in `auth.users`; 009 unique index `pins_source_external_id_key` present; **prod has zero system-owned pins** (the import must be a clean INSERT). Note: `pins.created_by` has **no FK** to `auth.users` (verified on staging), so a missing system user would not block inserts — but it must exist for the deny-write RLS to bind, so verify it regardless.

4. **Generalize the apply workflow.** `.github/workflows/importer-apply.yml` currently hardcodes `--sources hifld_courts`. Add `sources` and `states` as `workflow_dispatch` inputs (defaulting to the full 7-source list / `TX,FL,PA`), keep the existing typed `I-KNOW-THIS-WRITES-TO-PROD` confirmation and the `PROD_SUPABASE_SERVICE_ROLE_KEY` secret (already referenced in the workflow). Honors spec §7's non-negotiable rule: **prod applies run only from CI, never a developer's laptop.**

5. **Write the prod runbook.** `docs/importer/STAGING_REAPPLY.md` covers only 3 sources (predates Phase 5/6) and targets staging. Produce a prod-apply runbook covering all 7 sources via the CI workflow, including the dry-run-compare gate, verification SQL, and rollback. Update `docs/dev/STAGING.md`'s migration-history table for 009.

### B1. Dry-run gate (the canary)

Run a **prod `--dry-run`** (read-only; CI or local both acceptable since it never writes). The importer **re-fetches live upstream URLs**, so prod data can drift from the staging-validated snapshot. Go/no-go criterion:

- The dry-run report's per-source candidate counts and total must match the **staging baseline (23,825; per-source split above)** within a small tolerance.
- Any material divergence → **stop and investigate** before applying (likely an upstream dataset change; re-pin URLs / re-validate on staging first).
- The dry-run also proves config (B0.1), the prod service-role secret, and connectivity end-to-end without writing.

### B2. Apply

Single **combined apply** — all 7 sources, `--states TX,FL,PA` — via the generalized CI workflow (`importer-apply.yml`, target `prod`, typed confirmation). Prod has zero system pins, so this is a **pure INSERT** matching the validated staging path exactly. Cross-source dedup runs across all sources in the one run (the exact dataset that was validated). CI archives the report artifact.

### B3. Verify + idempotency

- Post-apply count check (per-source + status split) must equal the staging baseline.
- Optional idempotency re-run: report shows **INSERT 0** (the diff stage buckets every existing non-user row as UPDATE without value comparison, so UPDATE = existing-count, never 0; the idempotency signal is INSERT 0 with unchanged per-source counts).
- On-device spot check against prod: clustering at Houston / Miami / Philadelphia, the verify-locally caveat banner visible on a system pin, and the ODbL attribution reachable in Settings.

### B4. Rollback

Single clean operation, keyed on the system UUID:

```sql
delete from pins where created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e';
```

Real user pins (`source = 'user'`, different `created_by`) are never matched. Optional `pin_deletions` tombstone cleanup. This is the entire blast-radius reversal — the reason the single combined apply is acceptable despite its larger one-shot footprint.

### B5. Monitoring

Daily health-check (already pings prod + staging). Declare the pilot stable only after **≥7 days clean** (spec §8 Phase 7 exit criteria). Watch for delete-rate-limit trigger fires and any RLS-denied write anomalies.

---

## Risks

| Risk | Mitigation |
|---|---|
| Upstream data drift between staging validation and prod apply | B1 dry-run-compare gate; re-pin + re-validate on staging if divergent |
| Old-app users see un-hedged red pins until they update (no forced update) | Stage A adoption wait; accepted residual after that |
| OSM bars are UNCERTAIN/yellow, not red — users may over-trust | Caveat copy (A1) must state some system pins are explicitly low-confidence |
| Prod-schema verification needs prod DB access (MCP is staging-bound) | Operator runs read-only SQL in prod dashboard, or temporarily repoints MCP (B0.3) |
| Migration tracking table stale (008 unrecorded in prod `schema_migrations`) | Apply 009 via MCP (records it); optional 008 backfill (B0.2) |
| Single combined apply has larger one-shot blast radius | Clean single-statement rollback (B4); pure-INSERT path identical to validated staging run |

## Open questions (deferred to the plans)

- Stage A sub-plan: exact caveat trigger (source- vs confidence- vs status-based) and copy; ODbL attribution placement; whether the domain `Pin` model gains provenance fields or `PinDialog` takes a lightweight provenance param; pilot version number.
- Stage B: tolerance band for the dry-run-compare gate; whether to run the prod dry-run from CI or locally; whether to do the optional 008 tracking backfill.

## Document structure

This one design doc covers both stages. At writing-plans time it spawns **two** implementation plans reflecting the sequential dependency:

1. **Stage A — pre-import UI release** (smaller; brainstormed separately for the caveat + attribution specifics), shipped and adopted **first**.
2. **Stage B — prod import** (prep → dry-run gate → apply → verify → monitor), executed **only after** Stage A is live and adopted.

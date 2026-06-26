# Production pre-populate import — operator runbook (Phase 7 Stage B)

The first (and effectively irreversible) write of pre-populated pins to
**production** (`gqbxloaqamokbolcvesg`). All phases 0–6 are merged to master and
staging-validated; this runbook is the prod execution path. Design:
`docs/superpowers/specs/2026-06-19-phase7-prod-import-rollout-design.md`.

> **HARD GATE — do not start Stage B until Stage A is live and adopted.** The
> "verify locally" caveat UI + in-app ODbL attribution (shipped in **v0.7.0**)
> must be on users' screens *before* ~20.5k red NO_GUN pins land. Wait for the
> public-store release to go live **and** ≥7 days of clean health-checks + an
> adoption check before B1.

All importer-written pins are owned by the system user
`81775f8b-1a6a-47d6-b793-e9ab7e38634e` (`kSystemUserId`, same UUID in prod and
staging). Every clear/rollback keys on that UUID, so real user pins
(`source = 'user'`) are never touched.

**The non-negotiable rule:** the importer's `apply` against **prod** runs
**only** from the `Importer Apply (manual)` GitHub Actions workflow
(`.github/workflows/importer-apply.yml`) — never from a developer laptop. The
read-only `--dry-run` may run locally.

## Staging baseline this rollout reproduces

Verified on staging (`miihmfhnsfmwgrvgayns`); the prod dry-run (B1) must match
within a small tolerance.

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

---

## B0.2 — Apply migration 009 to prod (operator-gated)

`009_pins_source_unique_index.sql` swaps 008's partial index for a non-partial
`UNIQUE (source, source_external_id)` index. The importer's PostgREST upsert
emits `ON CONFLICT (source, source_external_id)` with no predicate, which
Postgres cannot infer against a *partial* index — so without 009 the apply fails
with `42P10: there is no unique or exclusion constraint matching the ON CONFLICT
specification`. 009 is **additive and app-independent**: the shipped app never
inserts a non-null `source_external_id`, so the new uniqueness constraint binds
nothing in existing clients.

The Supabase MCP is **bound to staging** (`.mcp.json` `project_ref =
miihmfhnsfmwgrvgayns`). To apply 009 to prod, choose **one**:

**Option A — MCP repoint (records the row in `schema_migrations`).**
1. Edit `.mcp.json`: set the supabase server `project_ref` to
   `gqbxloaqamokbolcvesg`.
2. **Restart the session** so the MCP picks up the new ref (config changes do
   not take effect mid-session).
3. Apply via MCP `apply_migration` (name `009_pins_source_unique_index`, body =
   the file contents). MCP records it in `supabase_migrations.schema_migrations`.
4. **Optional 008 tracking backfill:** re-apply `008_provenance_and_view_rpc`
   via the same MCP path to register its (currently missing) `schema_migrations`
   row. 008's DDL is already live in prod and idempotent, and v0.6.0 (carrying
   `toJsonForUpdate`) shipped long ago, so re-applying its grants is safe.
5. **Repoint `.mcp.json` back to staging** (`miihmfhnsfmwgrvgayns`) and restart.

**Option B — prod dashboard SQL editor (no MCP repoint).** Paste the contents of
`supabase/migrations/009_pins_source_unique_index.sql` into the **prod** project's
SQL editor and run. Does not register a `schema_migrations` row (acceptable — the
index is what matters; the count-drift check is lenient).

---

## B0.3 — Read-only prod parity check (before any write)

Run in the **prod** SQL editor (or via MCP while repointed for B0.2). Confirm
prod matches the schema the staging-validated import expects.

```sql
SELECT
  -- 008 provenance columns present (expect 9)
  (SELECT count(*) FROM information_schema.columns
     WHERE table_schema='public' AND table_name='pins'
       AND column_name IN ('source','source_external_id','source_dataset_version',
         'imported_at','user_modified','confidence','legal_citation',
         'legal_citation_verified_date','source_orphaned_at')) AS provenance_cols,   -- 9
  -- get_pins_in_view clustering RPC present (expect 1)
  (SELECT count(*) FROM pg_proc WHERE proname='get_pins_in_view')            AS rpc_exists,             -- 1
  -- system-user deny-write policies present (expect 3)
  (SELECT count(*) FROM pg_policy WHERE polrelid='public.pins'::regclass
     AND polname IN ('deny_system_user_insert','deny_system_user_update',
                     'deny_system_user_delete'))                             AS deny_policies,          -- 3
  -- 009 non-partial unique index present (expect 1) — this is what B0.2 adds
  (SELECT count(*) FROM pg_indexes WHERE schemaname='public'
     AND indexname='pins_source_external_id_key')                           AS unique_idx_009,         -- 1
  -- system user exists in auth.users (expect 1)
  (SELECT count(*) FROM auth.users
     WHERE id='81775f8b-1a6a-47d6-b793-e9ab7e38634e')                       AS system_user_exists,     -- 1
  -- prod has ZERO system-owned pins — the import must be a clean INSERT (expect 0)
  (SELECT count(*) FROM pins
     WHERE created_by='81775f8b-1a6a-47d6-b793-e9ab7e38634e')               AS existing_system_pins;   -- 0
```

Expected: `provenance_cols=9, rpc_exists=1, deny_policies=3, unique_idx_009=1,
system_user_exists=1, existing_system_pins=0`. Any deviation → **stop**.
(Note: `pins.created_by` has no FK to `auth.users`, so a missing system user
would not block inserts — but it must exist for the deny-write RLS to bind, so
verify it regardless.)

---

## B1 — Dry-run canary (the go/no-go gate)

The importer **re-fetches live upstream URLs**, so prod data can drift from the
staging snapshot. Run a prod `--dry-run` (read-only — never writes, so local is
fine) and compare to the staging baseline.

```powershell
cd C:\Users\camil\projects\ccwmap\importer
$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = "<PROD service_role key>"
uv run python -m importer.cli --dry-run --states TX,FL,PA `
  --sources hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm `
  --project-ref prod
```

Go/no-go:
- Per-source candidate counts and the total must match the **staging baseline
  (23,825; split above)** within a small tolerance.
- Any material divergence → **STOP and investigate** (likely an upstream dataset
  change). Re-pin URLs / re-validate on staging first; do not apply.
- The dry-run also proves `config.yaml` prod target (B0.1), the
  `PROD_SUPABASE_SERVICE_ROLE_KEY`, and end-to-end connectivity without writing.

---

## B2 — Apply (CI only)

Single **combined apply**, all 7 sources, via the GitHub Actions workflow.

1. Actions → **Importer Apply (manual)** → **Run workflow**.
2. Inputs:
   - `target`: **prod**
   - `confirm`: **`I-KNOW-THIS-WRITES-TO-PROD`** (exact)
   - `sources`: `hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm` (default)
   - `states`: `TX,FL,PA` (default)
3. The workflow injects `PROD_SUPABASE_SERVICE_ROLE_KEY`, validates the
   confirmation phrase, applies, and uploads `importer-report.md/.json` as a
   90-day artifact.

Prod has zero system pins, so this is a **pure INSERT** matching the validated
staging path exactly. Cross-source dedup runs across all sources in the one run.
On the first OSM apply the public `odbl-dumps` Storage bucket is created
idempotently and a `dump-YYYY-MM-DD.csv.gz` uploaded — no manual bucket setup.

---

## B3 — Verify + idempotency

In the **prod** SQL editor:

```sql
-- Per-source + status split must equal the staging baseline.
SELECT source, status, count(*) FROM pins
WHERE created_by='81775f8b-1a6a-47d6-b793-e9ab7e38634e'
GROUP BY source, status ORDER BY source, status;
-- Total must be 23,825 (± the B1 tolerance).

-- No pin landed in the Milwaukee bad-coord box (coordinate validation worked).
SELECT count(*) FROM pins
WHERE created_by='81775f8b-1a6a-47d6-b793-e9ab7e38634e'
  AND latitude BETWEEN 42.9 AND 43.1
  AND longitude BETWEEN -88.0 AND -87.8;            -- expect 0
```

**Optional idempotency re-run** (re-run B2 with the same inputs): the report
must show **INSERT 0** with unchanged per-source counts. The diff stage buckets
every existing non-user row as UPDATE without comparing values, so UPDATE =
existing-count and never drops to 0 — the idempotency signal is **INSERT 0**, not
UPDATE 0.

**On-device spot check against prod:** clustering at Houston / Miami /
Philadelphia; the verify-locally caveat banner visible on a system pin; the ODbL
attribution reachable in Settings.

---

## B4 — Rollback

Single clean operation keyed on the system UUID. Real user pins
(`source='user'`, different `created_by`) are never matched.

```sql
DELETE FROM pins WHERE created_by='81775f8b-1a6a-47d6-b793-e9ab7e38634e';
DELETE FROM pin_deletions;   -- optional tombstone tidy-up
```

This is the entire blast-radius reversal — the reason the single combined apply
is acceptable despite its larger one-shot footprint.

---

## B5 — Monitoring

The daily health-check already pings prod + staging. Declare the pilot stable
only after **≥7 days clean**. Watch for delete-rate-limit trigger fires and any
RLS-denied write anomalies.

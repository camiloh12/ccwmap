# Staging re-apply runbook

Operator runbook for refreshing the pre-populated pins in a Supabase project
(clear the importer-owned rows, then dry-run → apply → verify → idempotency).
Use this whenever the importer source code or source datasets change and the
already-applied pins need to be regenerated.

Two environments are involved:

- **PowerShell** — run from `importer/` with the target project's service-role
  key in `IMPORTER_SUPABASE_SERVICE_ROLE_KEY`.
- **SQL editor** — the Supabase **dashboard** SQL editor for the target project
  (for staging that is project `miihmfhnsfmwgrvgayns`). The Supabase MCP is
  currently bound to **staging** (`.mcp.json` `project_ref =
  miihmfhnsfmwgrvgayns`, as of 2026-06-14), so MCP queries also hit staging; the
  dashboard editor works regardless and is what these steps assume.

All importer-written pins are owned by the system user
`81775f8b-1a6a-47d6-b793-e9ab7e38634e` (`kSystemUserId`, same UUID in prod and
staging). The clear step keys on that UUID so real user pins (`source = 'user'`)
are never touched.

> **Prod note:** this runbook targets **staging** (`--project-ref staging`).
> A prod run is gated separately (app-release timing, `--project-ref prod`
> + `--i-know-this-writes-to-prod`) and is still deferred — do not point this at
> prod without that sign-off.

---

## 0. One-time setup (PowerShell)

```powershell
cd C:\Users\camil\projects\ccwmap\importer
$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = "<staging service_role key>"
```

Get the key from the Supabase dashboard → project **ccwmap-staging** → Project
Settings → API → `service_role` (secret). Never commit it or paste it into a file.

## 1. Dry-run — preview the numbers (PowerShell)

```powershell
uv run python -m importer.cli --dry-run --states TX,FL,PA `
  --sources hifld_courts,gsa,hifld_military --project-ref staging
```

Re-parses the ~145 MB FRPP cache (~90 s) — normal. The report is written to
`./report-<run-id>.md` + `.json` (gitignored). The INSERT vs UPDATE split will
look mixed while the old rows are still present — ignore it; the clean INSERT
numbers come after the clear. What to check: per-source candidate counts, the
cross-source dedup block, and no `missing_cells` / errors.

## 2. Clear the old pre-populated pins (SQL editor)

```sql
-- Preview first — confirm you are only touching importer-owned rows.
select source, count(*) from pins
where created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
group by source order by source;

-- Delete ONLY importer-written pins. Real user pins (source='user') are not
-- owned by the system user, so they are never matched by this predicate.
delete from pins
where created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e';

-- Optional tidy-up.
delete from pin_deletions;     -- clear any stale tombstones
-- delete from import_runs;    -- only if you want a clean audit ledger
```

## 3. Apply (PowerShell)

```powershell
uv run python -m importer.cli --apply --states TX,FL,PA `
  --sources hifld_courts,gsa,hifld_military `
  --project-ref staging --i-know-this-writes-to-staging
```

On a cleared table this is all **INSERT**. The `--i-know-this-writes-to-staging`
flag is mandatory for apply (guards against fat-fingering prod).

## 4. Verify (SQL editor)

```sql
select source, count(*) from pins
where created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
group by source order by source;

-- Coordinate validation worked: no pin landed in the Milwaukee bad-coord box.
select count(*) from pins
where created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
  and latitude between 42.9 and 43.1
  and longitude between -88.0 and -87.8;          -- expect 0

-- Labels composed, not bare city/address.
select name from pins
where created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e' and source = 'gsa'
  and (name like '%, FL' or name like '%, TX' or name like '%, PA')
limit 10;                                          -- "Office — Tampa, FL" style
```

## 5. Idempotency re-apply (PowerShell)

```powershell
uv run python -m importer.cli --apply --states TX,FL,PA `
  --sources hifld_courts,gsa,hifld_military `
  --project-ref staging --i-know-this-writes-to-staging
```

The report must show **INSERT 0** (everything UPDATE, SKIP 0) and the Step 4
counts must be unchanged → re-runs proven non-duplicating.

## 6. Density eyeball

Pull up the target project on the map and judge the GSA layer's clustering. This
is the standing open question on whether per-FRPP-building is the right altitude
for a CCW map before any prod consideration.

## 7. Phase 6 notes (OSM source + title-case normalisation)

**`odbl-dumps` Storage bucket.** The `osm` source creates the public Storage
bucket `odbl-dumps` idempotently on the first OSM apply — no manual dashboard
setup step is required. Subsequent apply runs upload a new
`dump-YYYY-MM-DD.csv.gz` to that bucket without recreating it.

**Title-case label wave (first re-apply after Phase 6).** Phase 6 added all-caps
label title-casing to the normalize stage. The first full re-apply after this
change rewrites every previously imported all-caps label to title case. This is
expected and is not a regression.

Note that the importer's diff stage buckets **every** existing, non-user-modified
row as **UPDATE** — it does not compare field values — so on any re-apply the
report shows `INSERT 0` with `UPDATE` equal to the existing row count (it never
drops to 0). The idempotency signal is therefore **INSERT 0** with unchanged
per-source counts (Step 5), not `UPDATE 0`. What settles after this first
title-case wave is the *stored data*: the second and later runs report the same
`UPDATE` count but no longer change any name.

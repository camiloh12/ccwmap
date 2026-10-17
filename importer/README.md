# CCW Map Pre-Populate Pins Importer

Stand-alone Python project that reads public datasets, classifies pins per the
maintained state-law lookup (`../data/state_laws/states.yaml`), and writes them
to a target Supabase project using the service-role key.

See [`docs/importer/README.md`](../docs/importer/README.md) for the operator
guide and [the design spec](../docs/superpowers/specs/2026-05-10-pre-populate-pins-design.md)
for the why.

## Quick start

```powershell
# One-time
uv venv
uv pip install -e ".[dev]"

# Run the test suite
uv run pytest

# Dry-run against staging (no writes)
$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = "<staging service-role key>"
uv run ccwmap-importer --dry-run --states TX,FL,PA --sources hifld_courts --project-ref staging
```

Apply mode (`--apply`) writes to the project named by `--project-ref`. It is
locked behind `--i-know-this-writes-to-<ref>` to prevent fat-fingering prod.

## Re-keys and orphans

- **Stable ids.** A pin is identified by `(source, source_external_id)`. GSA
  uses `{Reporting Agency Code}-{Reporting Bureau Code}-{Real Property Unique
  Identifier}`; military uses the MIRTA `SDSID`, or `{STATE}:{SITENAME}` when
  the SDSID is blank or all zeros. When a source's id scheme changes, its
  candidates carry the old id and old position, and the diff **re-keys** the
  existing pin in place (UUID and any user correction survive) if it is within
  50 m of where the old code put the record. The report shows `Re-key: N`, and
  `Re-key too far` when an old pin was more than 50 m away (that pin is
  reported as an orphan instead).
- **Orphans** are a source's system pins inside the run's `--states` that no
  record claimed: the record left the dataset (a Disposed building, a closed
  base) or lost cross-source dedup. A plain `--apply` marks them
  (`source_orphaned_at`). `--apply --delete-orphans` deletes them, except pins
  a user corrected, which are marked and listed as "kept, user-corrected".
  Deletions are permanent; the JSON report lists every one.
- **Delete cap.** Before anything is written, each source's deletions are
  checked against `max(50, 5% of its in-scope pins)`. One breach stops the
  whole apply with nothing written. A dry-run plans orphans the way
  `--delete-orphans` would and lists a breach under **Errors**.
  `--orphan-delete-cap N` overrides the cap for a local run; the Actions
  workflow doesn't expose it. `--delete-orphans` is rejected with `--dry-run`.
- **Run the full source set** (the workflow default). Dedup decides between
  sources, so a partial run can re-insert a pin another source won.

## Data Sources & Licenses

Available `--sources` values and their upstream licenses:

| `--sources` key | Module | License |
|---|---|---|
| `hifld_courts` | `sources/hifld_courts.py` | Public domain (DHS HIFLD Open) |
| `gsa` | `sources/gsa.py` | Public domain (US Gov) |
| `hifld_military` | `sources/hifld_military.py` | Public domain (US Gov / DoD DISDI) |
| `nces` | `sources/nces.py` | Public domain (US Gov) |
| `ipeds` | `sources/ipeds.py` | Public domain (US Gov) |
| `faa` | `sources/faa.py` | Public domain (US Gov) |
| `osm` | `sources/osm.py` | **ODbL — share-alike** |

**Compliance posture:**

- **US Government sources** (NCES, IPEDS, FAA, GSA, HIFLD courts/military) are
  public-domain works. No attribution requirement; no downstream restrictions.
- **OSM** is licensed under the
  [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/)
  (share-alike). After each apply run that lands OSM rows, the importer generates
  `dump-YYYY-MM-DD.csv.gz` (columns: `osm_type`, `osm_id`, `name`, `latitude`,
  `longitude`) and uploads it to the public Supabase Storage bucket `odbl-dumps`.
  This fulfills the ODbL "Produced Work" / "share-alike" obligation for the
  derived dataset. In-app attribution UI (pin detail dialog) is deferred to
  Phase 7 (pilot ship) — it is not yet present in the app.

See [`docs/importer/SOURCES.md`](../docs/importer/SOURCES.md) for full per-source
dataset details (URLs, file formats, join keys, coordinate quality).

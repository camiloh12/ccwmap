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

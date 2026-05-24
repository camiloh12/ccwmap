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

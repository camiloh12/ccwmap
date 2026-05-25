# Pre-populate pins — importer operator guide

The importer is a Python project at [`importer/`](../../importer/) that reads
public datasets, classifies them per the maintained state-law table
([`data/state_laws/states.yaml`](../../data/state_laws/states.yaml)), and
either generates a dry-run report or writes upserts to a target Supabase
project using the service-role key.

This guide covers operator workflows. For the why and the schema, see the
[design spec](../superpowers/specs/2026-05-10-pre-populate-pins-design.md).

## When to run

| Workflow | Trigger | Target |
|---|---|---|
| `importer-pr-validate.yml` | PR touching `importer/**` or `data/state_laws/**` | Staging dry-run |
| `importer-dry-run.yml` | Cron, Monday 12:00 UTC | Staging dry-run |
| `importer-apply.yml` | Manual `workflow_dispatch` | Staging or prod (operator-selected) |

Local runs use `uv run python -m importer.cli` and read the service-role key
from the env var `IMPORTER_SUPABASE_SERVICE_ROLE_KEY`.

## Quick start (local)

```powershell
cd importer
uv venv
uv pip install -e ".[dev]"
$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = "<staging service-role key>"

# Dry-run (no writes)
uv run python -m importer.cli --dry-run --states TX,FL,PA --sources hifld_courts --project-ref staging

# Apply to staging
uv run python -m importer.cli --apply --states TX,FL,PA --sources hifld_courts --project-ref staging --i-know-this-writes-to-staging
```

The report is written to `./report-<run-id>.md` and `./report-<run-id>.json`
in the current working directory by default; pass `--report-out path/to/file.md`
to override.

## Re-running is safe

Each pin is keyed by `(source, source_external_id)`. Subsequent runs upsert
into existing rows. The Phase 0 trigger `set_user_modified` marks rows touched
by anyone other than `service_role`; the diff stage SKIPs those rows so user
edits are never overwritten.

## Refreshing the HIFLD fixture

If the HIFLD courthouses dataset changes shape (new properties, dropped
fields), refresh the checked-in fixture and re-run tests:

```powershell
# 1. Grab a fresh sample from the live URL captured in
#    data/sources/.hifld_courts_url.txt (see pre-flight checklist of
#    Phase 2 plan)
# 2. Copy a small representative slice (TX + FL + PA, ~50 rows max) into
#    importer/tests/fixtures/hifld_courts_sample.geojson
# 3. Run tests — failures are signal, not noise
cd importer
uv run pytest
```

## Adding a new source (future phases)

1. Add a module under `importer/importer/sources/<name>.py` implementing the `Source` ABC.
2. Add the source to `SUPPORTED_SOURCES` in `importer/importer/cli.py`.
3. Add a `cache_dir` + `dataset_version` entry under `sources:` in `importer/config.yaml`.
4. Add unit-test fixtures under `importer/tests/fixtures/`.
5. Add row(s) to `data/state_laws/states.yaml` covering the new source's category × states.
6. Update `docs/importer/SOURCES.md`.

## Troubleshooting

- **`ERROR: IMPORTER_SUPABASE_SERVICE_ROLE_KEY env var is required.`** — export the env var or pass it through the workflow.
- **Postgrest returns 401** — the service-role key is wrong, or it is the anon key by mistake.
- **`(state, category)` reported as "Needs research"** — add a row to `states.yaml`. The importer never invents a status; an unclassifiable candidate is dropped, not guessed at.
- **An orphan reappears next run with non-orphan status** — the source actually has it again. `source_orphaned_at` is auto-cleared on the next successful match.

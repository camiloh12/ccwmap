# Phase 7 Stage B — Production Pre-Populate Import Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare and execute the first production import of the ~23,825 system-owned pre-populate pins (TX/FL/PA, 7 sources) as a single combined INSERT, with a dry-run-compare go/no-go gate and a one-statement rollback.

**Architecture:** Two parts. **Part 1 (Tasks 1–3)** is implementable code/doc prep that lands now and is independently testable — fill the importer's prod target, generalize the apply CI workflow, write the prod runbook. **Part 2 (Tasks 4–9)** is the operator-run execution sequence (migration, schema-parity verify, dry-run gate, the combined apply, verify, monitor) — exact checklists, since Claude does not execute prod writes. A contingency rollback section closes the plan.

**Tech Stack:** Python 3.12 + `uv` importer (`importer/`), PyYAML, pytest; GitHub Actions (`importer-apply.yml`); Supabase Postgres (prod ref `gqbxloaqamokbolcvesg`); Supabase MCP for the migration.

**Spec:** `docs/superpowers/specs/2026-06-19-phase7-prod-import-rollout-design.md`

---

## ⛔ Hard prerequisite before Part 2 (the prod write)

**Stage A must ship to the public stores and reach reasonable adoption before Task 7 (the apply) runs.** Stage A is the pre-import app release (verify-locally caveat + in-app ODbL attribution) — planned and executed separately. The flood of ~20,550 red NO_GUN pins must not land before its hedge is on users' screens. Part 1 (Tasks 1–3) and the read-only Tasks 4–6 may proceed earlier; **Task 7 is the gated, irreversible step.**

---

## Part 1 — code/doc prep (implementable now)

### Task 1: Fill the importer's prod target + add a placeholder guard

**Why:** `importer/config.yaml` has `prod.project_ref` / `prod.url` set to `REPLACE-WITH-PROD-PROJECT-REF`. `cli.main()` builds the Supabase client URL from `config["projects"][args.project_ref]["url"]`, so a prod apply would silently target a non-existent host. The prod ref `gqbxloaqamokbolcvesg` is a public project identifier (not a secret); the secret is the service-role key, which stays an env var.

**Files:**
- Modify: `importer/config.yaml` (the `projects.prod` block)
- Modify: `importer/importer/cli.py` (`main()`, after the `project = config["projects"][...]` line ~200)
- Test: `importer/tests/test_cli.py`

- [ ] **Step 1: Write the failing config test**

Add to `importer/tests/test_cli.py`:

```python
def test_prod_project_ref_is_configured_not_placeholder():
    """The prod target must be a real Supabase ref before any prod apply.
    A leftover REPLACE-WITH-PROD-PROJECT-REF builds a garbage URL that
    silently points at a non-existent host."""
    import yaml
    from pathlib import Path
    from importer.cli import CONFIG_PATH

    config = yaml.safe_load(Path(CONFIG_PATH).read_text(encoding="utf-8"))
    prod = config["projects"]["prod"]
    assert prod["project_ref"] == "gqbxloaqamokbolcvesg"
    assert prod["url"] == "https://gqbxloaqamokbolcvesg.supabase.co"
    assert "REPLACE-WITH" not in prod["project_ref"]
    assert "REPLACE-WITH" not in prod["url"]
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd importer && uv run pytest tests/test_cli.py::test_prod_project_ref_is_configured_not_placeholder -v`
Expected: FAIL (`assert 'REPLACE-WITH-PROD-PROJECT-REF' == 'gqbxloaqamokbolcvesg'`)

- [ ] **Step 3: Fill the prod block in `importer/config.yaml`**

Replace:

```yaml
  prod:
    project_ref: "REPLACE-WITH-PROD-PROJECT-REF"
    url: "https://REPLACE-WITH-PROD-PROJECT-REF.supabase.co"
```

with:

```yaml
  prod:
    project_ref: "gqbxloaqamokbolcvesg"
    url: "https://gqbxloaqamokbolcvesg.supabase.co"
```

- [ ] **Step 4: Run it to verify it passes**

Run: `cd importer && uv run pytest tests/test_cli.py::test_prod_project_ref_is_configured_not_placeholder -v`
Expected: PASS

- [ ] **Step 5: Write the failing guard test**

Add to `importer/tests/test_cli.py`:

```python
def test_main_errors_on_placeholder_project_url(monkeypatch):
    """If a project url is ever re-blanked to a placeholder, main() must
    refuse to run rather than build a client against a non-existent host."""
    import importer.cli as cli

    monkeypatch.setenv("IMPORTER_SUPABASE_SERVICE_ROLE_KEY", "dummy")
    monkeypatch.setattr(cli, "_load_config", lambda: {
        "system_user_id": "x",
        "projects": {
            "prod": {
                "project_ref": "REPLACE-WITH-PROD-PROJECT-REF",
                "url": "https://REPLACE-WITH-PROD-PROJECT-REF.supabase.co",
            }
        },
        "sources": {},
    })
    rc = cli.main([
        "--dry-run", "--states", "TX",
        "--sources", "hifld_courts", "--project-ref", "prod",
    ])
    assert rc == 2
```

- [ ] **Step 6: Run it to verify it fails**

Run: `cd importer && uv run pytest tests/test_cli.py::test_main_errors_on_placeholder_project_url -v`
Expected: FAIL (no guard yet — `main()` proceeds past the placeholder and errors later for a different reason, or raises KeyError on the empty `sources` dict, not returning 2 cleanly)

- [ ] **Step 7: Add the guard in `importer/importer/cli.py`**

Immediately after:

```python
    config = _load_config()
    project = config["projects"][args.project_ref]
```

insert:

```python
    if "REPLACE-WITH" in project["url"]:
        sys.stderr.write(
            f"ERROR: project '{args.project_ref}' is not configured "
            f"(url is still a placeholder: {project['url']}).\n"
        )
        return 2
```

- [ ] **Step 8: Run the guard test and the full importer suite**

Run: `cd importer && uv run pytest tests/test_cli.py::test_main_errors_on_placeholder_project_url -v && uv run pytest`
Expected: the guard test PASSES; full suite PASSES (154 tests — 152 prior + 2 new)

- [ ] **Step 9: Commit**

```bash
git add importer/config.yaml importer/importer/cli.py importer/tests/test_cli.py
git commit -m "feat(importer): set prod target ref + guard against placeholder url"
```

---

### Task 2: Generalize the apply workflow to take `sources` + `states`

**Why:** `.github/workflows/importer-apply.yml` hardcodes `--sources hifld_courts`, so it can only import the 470 courthouses, not the full 7-source set. Spec §7 mandates prod applies run only from CI, so this workflow is the prod-write path and must be parameterized. Defaults to the full pilot set so the common case is a single click.

**Files:**
- Modify: `.github/workflows/importer-apply.yml` (the `workflow_dispatch.inputs` block and the apply `run:` step)
- Test: `importer/tests/test_apply_workflow.py` (new)

- [ ] **Step 1: Write the failing workflow-guard test**

Create `importer/tests/test_apply_workflow.py`:

```python
from pathlib import Path

import yaml

WORKFLOW = (
    Path(__file__).resolve().parents[2] / ".github" / "workflows" / "importer-apply.yml"
)


def test_apply_workflow_parametrizes_sources_and_states():
    """The prod apply path must take sources/states as inputs, defaulting to
    the full 7-source pilot set — never a hardcoded single source."""
    raw = WORKFLOW.read_text(encoding="utf-8")

    # Must remain valid YAML.
    yaml.safe_load(raw)

    # Inputs declared.
    assert "sources:" in raw
    assert "states:" in raw

    # Default is the full pilot source set.
    assert "hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm" in raw

    # The run step references the inputs, not a hardcoded source.
    assert "${{ inputs.sources }}" in raw
    assert "${{ inputs.states }}" in raw

    # The old hardcoded line must be gone.
    assert "--sources hifld_courts" not in raw
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd importer && uv run pytest tests/test_apply_workflow.py -v`
Expected: FAIL (`assert 'sources:' in raw` — current workflow has no `sources` input)

- [ ] **Step 3: Add the two inputs to `importer-apply.yml`**

In `.github/workflows/importer-apply.yml`, the `workflow_dispatch.inputs` block currently ends with the `confirm` input. After it, add:

```yaml
      sources:
        description: 'Comma-separated source list'
        required: true
        type: string
        default: 'hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm'
      states:
        description: 'Comma-separated state codes'
        required: true
        type: string
        default: 'TX,FL,PA'
```

(Keep the existing `target` and `confirm` inputs exactly as they are; just append these two.)

- [ ] **Step 4: Parameterize the apply `run:` step**

Replace the apply step's command:

```yaml
          uv run --no-sync python -m importer.cli \
            --apply \
            --states TX,FL,PA \
            --sources hifld_courts \
            --project-ref ${{ inputs.target }} \
            --i-know-this-writes-to-${{ inputs.target }} \
            --report-out "$GITHUB_WORKSPACE/importer-report.md"
```

with:

```yaml
          uv run --no-sync python -m importer.cli \
            --apply \
            --states "${{ inputs.states }}" \
            --sources "${{ inputs.sources }}" \
            --project-ref ${{ inputs.target }} \
            --i-know-this-writes-to-${{ inputs.target }} \
            --report-out "$GITHUB_WORKSPACE/importer-report.md"
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd importer && uv run pytest tests/test_apply_workflow.py -v`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/importer-apply.yml importer/tests/test_apply_workflow.py
git commit -m "feat(ci): parameterize importer-apply sources/states (default full pilot set)"
```

---

### Task 3: Write the prod-import runbook + update migration docs

**Why:** `docs/importer/STAGING_REAPPLY.md` covers only 3 sources and targets staging. The operator needs a prod-specific, all-7-source runbook that encodes the gate, the migration mechanism, and rollback. No code; this is the operator's source of truth for Part 2.

**Files:**
- Create: `docs/importer/PROD_IMPORT.md`
- Modify: `docs/dev/STAGING.md` (migration-history table + prod-apply note)

- [ ] **Step 1: Create `docs/importer/PROD_IMPORT.md`**

Write the runbook with these sections (content mirrors Tasks 4–9 below, so the operator can follow either):

```markdown
# Production pre-populate import runbook

First and only production import of the system-owned pre-populate pins
(TX/FL/PA, 7 sources, ~23,825 pins). Effectively irreversible except via the
delete-by-system-UUID rollback. Do not run the apply (step 5) until Stage A
(verify-locally caveat + ODbL attribution app release) is live and adopted.

System user (owns every imported pin): `81775f8b-1a6a-47d6-b793-e9ab7e38634e`.
Prod project ref: `gqbxloaqamokbolcvesg`.

Staging baseline to reproduce (per-source / status):
| source | status | count |
|---|---|---|
| nces | NO_GUN (2) | 15,432 |
| gsa | NO_GUN (2) | 4,221 |
| osm | UNCERTAIN (1) | 3,275 |
| hifld_courts | NO_GUN (2) | 470 |
| ipeds | NO_GUN (2) | 290 |
| hifld_military | NO_GUN (2) | 77 |
| faa | NO_GUN (2) | 60 |
| total | | 23,825 |

## 1. Apply migration 009 to prod (MCP)
Temporarily repoint `.mcp.json` supabase ref → `gqbxloaqamokbolcvesg`, restart
Claude Code, apply `supabase/migrations/009_pins_source_unique_index.sql` via
MCP `apply_migration` (records it in `schema_migrations`). Optionally re-apply
008 the same way to backfill its tracking row (idempotent; v0.6.0 already live).
Repoint `.mcp.json` back to staging (`miihmfhnsfmwgrvgayns`) and restart.

## 2. Verify prod schema parity (read-only)
Run the parity SQL (008 cols + get_pins_in_view, deny_system_user_* RLS,
system user exists, 009 unique index present, zero existing system pins). All
must hold before proceeding.

## 3. Prod dry-run gate (local, read-only)
Set `IMPORTER_SUPABASE_SERVICE_ROLE_KEY` to the PROD service-role key, then:
    uv run python -m importer.cli --dry-run --states TX,FL,PA \
      --sources hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm \
      --project-ref prod --refetch --report-out ./prod-dryrun.md
Compare the per-source candidate/INSERT counts to the baseline table within a
small tolerance. Material divergence → STOP, re-pin URLs, re-validate on
staging first. Unset the prod key from the shell afterward.

## 4. (gate) Confirm Stage A is live + adopted before continuing.

## 5. Apply (CI only)
GitHub → Actions → "Importer Apply (manual)" → Run workflow:
  target = prod
  confirm = I-KNOW-THIS-WRITES-TO-PROD
  sources = hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm
  states  = TX,FL,PA
Download the report artifact; confirm pure INSERT totalling ~23,825.

## 6. Verify + idempotency
Re-run the verify SQL (counts == baseline). Optional second apply →
INSERT 0 with unchanged per-source counts (the diff stage reports every
existing non-user row as UPDATE, so UPDATE == existing-count, never 0).

## 7. Spot check + monitor
On-device against prod: clustering at Houston/Miami/Philadelphia, the
verify-locally banner on a system pin, ODbL attribution in Settings. Daily
health-check; declare stable after >= 7 clean days.

## Rollback
    delete from pins where created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e';
User pins (source='user', different created_by) are never matched.
```

- [ ] **Step 2: Update `docs/dev/STAGING.md` migration history**

In the migration-history table, add a row for 009 and note the prod-apply mechanism:

```markdown
| 009_pins_source_unique_index    | 2026-05-26 | (Phase 7, via MCP apply_migration) | Unique index for the importer ON CONFLICT upsert. Additive; independent of app release. Applied to prod through MCP (records in schema_migrations) per docs/importer/PROD_IMPORT.md. |
```

Also adjust the prose note that says prod migrations are applied "via the dashboard SQL editor" to prefer MCP `apply_migration` (records the migration; the dashboard path does not).

- [ ] **Step 3: Verify the docs are internally consistent**

Read both files back. Confirm: source list identical in both (`hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm`), baseline totals identical (23,825), system UUID identical, prod ref identical (`gqbxloaqamokbolcvesg`).

- [ ] **Step 4: Commit**

```bash
git add docs/importer/PROD_IMPORT.md docs/dev/STAGING.md
git commit -m "docs(importer): add prod-import runbook + 009 migration history"
```

---

## Part 2 — operator execution (gated; Claude does not run prod writes)

> Each task below is run by the **operator**. Claude assists with verification queries against staging only (MCP is staging-bound) and with reading reports, but does **not** repoint MCP to prod or trigger the apply without explicit per-step confirmation.

### Task 4: Apply migration 009 to prod (OPERATOR — via MCP)

- [ ] **Step 1: Repoint MCP to prod**
Edit `.mcp.json`: change the supabase url's `project_ref` from `miihmfhnsfmwgrvgayns` to `gqbxloaqamokbolcvesg`. Restart Claude Code so the binding takes effect.

- [ ] **Step 2: Confirm the binding**
Call `mcp__supabase__get_project_url`. Expected: `https://gqbxloaqamokbolcvesg.supabase.co`. **Do not proceed if it still shows staging.**

- [ ] **Step 3: Apply 009**
Apply `supabase/migrations/009_pins_source_unique_index.sql` via MCP `apply_migration` (name e.g. `009_pins_source_unique_index`).
Expected: success; the `DROP INDEX IF EXISTS` + `CREATE UNIQUE INDEX IF NOT EXISTS` run cleanly.

- [ ] **Step 4 (optional): Backfill 008 tracking**
Re-apply `008_provenance_and_view_rpc.sql` via MCP `apply_migration` to register its missing `schema_migrations` row. Idempotent; safe because v0.6.0 (with `toJsonForUpdate`) is already live.

- [ ] **Step 5: Repoint MCP back to staging**
Revert `.mcp.json` `project_ref` to `miihmfhnsfmwgrvgayns`. Restart Claude Code. Re-confirm via `get_project_url` → staging. Leaving MCP on prod is the standing live-app footgun this binding exists to prevent.

### Task 5: Verify prod schema parity (OPERATOR — read-only)

Run while MCP is pointed at prod (fold into Task 4 before repointing back), or via the prod dashboard SQL editor.

- [ ] **Step 1: Run the parity query**

```sql
SELECT 'provenance_cols' AS check,
       (SELECT count(*) FROM information_schema.columns
        WHERE table_name='pins'
          AND column_name IN ('source','source_external_id','confidence',
                              'legal_citation','legal_citation_verified_date'))::text AS detail
UNION ALL SELECT 'rpc_get_pins_in_view', proname FROM pg_proc WHERE proname='get_pins_in_view'
UNION ALL SELECT 'unique_index_009', indexname FROM pg_indexes WHERE indexname='pins_source_external_id_key'
UNION ALL SELECT 'deny_rls', string_agg(polname, ',') FROM pg_policy WHERE polname ILIKE '%system%'
UNION ALL SELECT 'system_user', (SELECT email FROM auth.users WHERE id='81775f8b-1a6a-47d6-b793-e9ab7e38634e')
UNION ALL SELECT 'existing_system_pins', count(*)::text FROM pins WHERE created_by='81775f8b-1a6a-47d6-b793-e9ab7e38634e';
```

- [ ] **Step 2: Confirm expected results**
Expected: `provenance_cols=5`; `rpc_get_pins_in_view=get_pins_in_view`; `unique_index_009=pins_source_external_id_key`; `deny_rls` contains insert+update+delete policies; `system_user` is the `system+ccwmap@kyberneticlabs.com` alias; **`existing_system_pins=0`**. Any miss → resolve before the apply.

### Task 6: Prod dry-run gate (OPERATOR — local, read-only)

- [ ] **Step 1: Set the prod service-role key in the shell**
PowerShell: `$env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY = "<PROD service_role key>"` (from prod dashboard → Settings → API). Never commit or echo it.

- [ ] **Step 2: Run the dry-run**

```powershell
cd C:\Users\camil\projects\ccwmap\importer
uv run python -m importer.cli --dry-run --states TX,FL,PA `
  --sources hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm `
  --project-ref prod --refetch --report-out ./prod-dryrun.md
```

- [ ] **Step 3: Compare to baseline (go/no-go)**
Open `prod-dryrun.md`. Per-source candidate/INSERT counts must match within a small tolerance: nces 15,432 / gsa 4,221 / osm 3,275 / courts 470 / ipeds 290 / military 77 / faa 60; total ≈ 23,825. Cross-source dedup block should look like staging (~40 collapses). **Material divergence → STOP**, re-pin upstream URLs, re-validate on staging.

- [ ] **Step 4: Clear the key from the shell**
`Remove-Item Env:IMPORTER_SUPABASE_SERVICE_ROLE_KEY`

### Task 7: ⛔ The combined apply (OPERATOR — CI only, GATED on Stage A)

- [ ] **Step 1: Confirm the gate**
Verify Stage A (verify-locally caveat + ODbL attribution) is live in the public stores and adopted (≥7 days clean health-check + adoption check). **Do not proceed otherwise.**

- [ ] **Step 2: Trigger the apply workflow**
GitHub → Actions → **Importer Apply (manual)** → Run workflow:
- `target` = `prod`
- `confirm` = `I-KNOW-THIS-WRITES-TO-PROD`
- `sources` = `hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm`
- `states` = `TX,FL,PA`

- [ ] **Step 3: Confirm the run**
Download the `importer-apply-prod-*` artifact. Expected: pure INSERT, totalling ~23,825 across the 7 sources, 0 errors, 0 orphans.

### Task 8: Verify + idempotency (OPERATOR)

- [ ] **Step 1: Verify counts (prod dashboard SQL editor)**

```sql
SELECT source, status, count(*) FROM pins
WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
GROUP BY source, status ORDER BY source, status;
```

Expected: matches the baseline table (osm at status 1; all others at status 2; total 23,825).

- [ ] **Step 2 (optional): Idempotency re-run**
Re-trigger the apply workflow with identical inputs. Expected: report shows **INSERT 0**, per-source counts unchanged (UPDATE equals existing-count by design, never 0).

### Task 9: Spot check + monitor (OPERATOR)

- [ ] **Step 1: On-device spot check against prod**
Pan Houston / Miami / Philadelphia — clusters render/expand sensibly. Open a system NO_GUN pin → the **verify-locally caveat** banner shows. Open Settings → **ODbL attribution** present. Open an OSM bar → it is **yellow/UNCERTAIN**, not red.

- [ ] **Step 2: Monitor**
Daily health-check (already pings prod). Declare the pilot stable after **≥7 consecutive clean days**. Watch for delete-rate-limit trigger fires or RLS-denied write anomalies.

---

## Contingency — rollback

If the import must be reverted (bad data, app instability, or any go-back decision), run once in the prod dashboard SQL editor:

```sql
-- Preview first.
SELECT source, count(*) FROM pins
WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e'
GROUP BY source ORDER BY source;

-- Remove ONLY importer-written pins. Real user pins (source='user') have a
-- different created_by and are never matched.
DELETE FROM pins WHERE created_by = '81775f8b-1a6a-47d6-b793-e9ab7e38634e';

-- Optional tombstone tidy-up.
DELETE FROM pin_deletions;
```

The deny-system-user RLS does not block this — it runs as the dashboard's privileged role, not `authenticated`. After rollback, clients re-fetch and the system pins disappear on next viewport sync.

---

## Self-review notes

- **Spec coverage:** B0.1 → Task 1; B0.2 (009 via MCP + 008 backfill) → Task 4; B0.3 (schema parity) → Task 5; B0.4 (generalize workflow) → Task 2; B0.5 (prod runbook + STAGING.md) → Task 3; B1 (dry-run gate) → Task 6; B2 (combined apply) → Task 7; B3 (verify + idempotency) → Task 8; B4 (rollback) → Contingency; B5 (monitoring) → Task 9. Stage A gate → Hard-prerequisite banner + Task 7 Step 1.
- **Source list** is identical everywhere: `hifld_courts,gsa,hifld_military,nces,ipeds,faa,osm`.
- **Baseline total** 23,825 and the system UUID `81775f8b-1a6a-47d6-b793-e9ab7e38634e` are consistent across tasks.
- **Test count:** 152 confirmed today. Task 1 adds 2 tests in `test_cli.py` → 154 (Task 1 Step 8 expected). Task 2 adds 1 test in new `test_apply_workflow.py` → 155 total.

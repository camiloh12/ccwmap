"""Entrypoint for `python -m importer.cli`.

Exit codes:
  0 — success
  1 — operational failure (network, Supabase, etc.)
  2 — usage error (bad flags, missing env var)
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

import yaml

from importer.geo.census_geocode import CensusGeocoder
from importer.geo.states import load_state_locator
from importer.pipeline import run_pipeline
from importer.reports.json_report import render_json
from importer.reports.markdown import render_markdown
from importer.sources.gsa import GsaSource
from importer.sources.hifld_courts import HifldCourthousesSource
from importer.sources.hifld_military import HifldMilitarySource
from importer.state_laws import load_state_laws
from importer.supabase_client import SupabaseClient


SUPPORTED_SOURCES = ("hifld_courts", "gsa", "hifld_military")
SUPPORTED_REFS = ("staging", "prod")

REPO_ROOT = Path(__file__).resolve().parent.parent.parent  # importer/../ == repo root
CONFIG_PATH = Path(__file__).resolve().parent.parent / "config.yaml"
STATES_YAML = REPO_ROOT / "data" / "state_laws" / "states.yaml"
# PHASE 2 SCOPE: this points at the TX+FL+PA test fixture, which is the only
# state coverage Phase 2 demonstrates. Running --states with any code outside
# {TX,FL,PA} will silently yield zero candidates (every courthouse outside those
# polygons fails state point-in-polygon and is skipped). Phase 3 MUST replace
# this with a committed full-50-state boundary file under data/ before widening
# state coverage. See docs/superpowers/plans/2026-05-24-pre-populate-pins-phase-2.md.
STATES_BOUNDARY_FIXTURE = (
    Path(__file__).resolve().parent.parent / "tests" / "fixtures" / "states_sample.geojson"
)


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="importer",
        description="CCW Map pre-populate-pins importer.",
    )
    mode = p.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true", help="Default; no writes.")
    mode.add_argument("--apply", action="store_true", help="Write to Supabase.")

    p.add_argument(
        "--states",
        required=True,
        type=lambda v: [s.strip().upper() for s in v.split(",") if s.strip()],
        help="Comma-separated USPS state codes, e.g. TX,FL,PA.",
    )
    p.add_argument(
        "--sources",
        required=True,
        type=lambda v: [s.strip() for s in v.split(",") if s.strip()],
        choices=None,  # validated manually below for friendlier error
        help=f"Comma-separated source names. Supported: {','.join(SUPPORTED_SOURCES)}.",
    )
    p.add_argument(
        "--project-ref",
        required=True,
        choices=SUPPORTED_REFS,
        help="Which Supabase project to target.",
    )
    p.add_argument(
        "--i-know-this-writes-to-staging",
        action="store_true",
        help="Required confirmation for --apply --project-ref staging.",
    )
    p.add_argument(
        "--i-know-this-writes-to-prod",
        action="store_true",
        help="Required confirmation for --apply --project-ref prod.",
    )
    p.add_argument(
        "--report-out",
        type=Path,
        default=None,
        help="Path to write the Markdown report (default: ./report-<timestamp>.md).",
    )
    p.add_argument(
        "--refetch",
        action="store_true",
        help="Force per-source fetch() to re-download even if cached.",
    )

    # Manual choice validation for friendlier errors than argparse's default.
    orig_parse_args = p.parse_args

    def _parse_args(argv=None):
        args = orig_parse_args(argv)
        for s in args.sources:
            if s not in SUPPORTED_SOURCES:
                p.error(f"unsupported source: {s!r}; supported: {','.join(SUPPORTED_SOURCES)}")
        if args.apply:
            confirm_attr = f"i_know_this_writes_to_{args.project_ref}"
            if not getattr(args, confirm_attr, False):
                p.error(
                    f"--apply with --project-ref {args.project_ref} requires "
                    f"--i-know-this-writes-to-{args.project_ref}"
                )
        return args

    p.parse_args = _parse_args  # type: ignore[assignment]
    return p


def _load_config() -> dict:
    return yaml.safe_load(CONFIG_PATH.read_text(encoding="utf-8"))


def _build_source(name, *, config, locator, repo_root):
    cfg = config["sources"][name]
    cache_dir = Path(repo_root) / cfg["cache_dir"]
    version = cfg["dataset_version"]
    url = cfg.get("url", "")
    if name == "hifld_courts":
        return HifldCourthousesSource(
            cache_path=cache_dir / "courthouses.geojson",
            state_locator=locator, dataset_version=version,
            **({"url": url} if url else {}),
        )
    if name == "hifld_military":
        return HifldMilitarySource(
            cache_path=cache_dir / "military.geojson",
            state_locator=locator, dataset_version=version, url=url,
        )
    if name == "gsa":
        return GsaSource(
            cache_path=cache_dir / "frpp.xlsx",
            dataset_version=version, url=url,
            geocoder=CensusGeocoder(cache_path=cache_dir / "geocoded.json"),
        )
    raise NotImplementedError(name)


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(
        level=logging.INFO,
        format='{"level":"%(levelname)s","msg":%(message)r,"logger":"%(name)s"}',
    )

    parser = build_parser()
    args = parser.parse_args(argv)

    service_role_key = os.environ.get("IMPORTER_SUPABASE_SERVICE_ROLE_KEY")
    if not service_role_key:
        sys.stderr.write(
            "ERROR: IMPORTER_SUPABASE_SERVICE_ROLE_KEY env var is required.\n"
        )
        return 2

    config = _load_config()
    project = config["projects"][args.project_ref]
    system_user_id = config["system_user_id"]

    locator = load_state_locator(STATES_BOUNDARY_FIXTURE)
    state_laws = load_state_laws(STATES_YAML)

    mode = "apply" if args.apply else "dry-run"
    run_id: str | None = None

    with SupabaseClient(
        url=project["url"],
        service_role_key=service_role_key,
        system_user_id=system_user_id,
    ) as client:
        try:
            run_id = client.insert_import_run(
                mode=mode, source_filter=",".join(args.sources)
            )

            sources = [
                _build_source(name, config=config, locator=locator, repo_root=REPO_ROOT)
                for name in args.sources
            ]
            result = run_pipeline(
                sources=sources,
                state_laws=state_laws,
                client=client,
                states=args.states,
                mode=mode,
                system_user_id=system_user_id,
                refetch=args.refetch,
            )

            report_md = render_markdown(result)
            report_json = render_json(result)
            report_path = args.report_out or Path.cwd() / f"report-{run_id}.md"
            json_path = report_path.with_suffix(".json")
            report_path.write_text(report_md, encoding="utf-8")
            json_path.write_text(report_json, encoding="utf-8")
            sys.stdout.write(report_md)

            client.update_import_run(
                run_id=run_id,
                candidates_processed=sum(s.candidates_fetched for s in result.sources),
                inserts=sum(len(s.diff.inserts) for s in result.sources),
                updates=sum(len(s.diff.updates) for s in result.sources),
                skips=sum(len(s.diff.skips) for s in result.sources),
                orphans_marked=sum(len(s.diff.orphans) for s in result.sources),
                errors_json=None,
                report_artifact_url=None,
            )
        except Exception as exc:  # noqa: BLE001  — top-level catchall by design
            logging.exception("importer failed")
            if run_id is not None:
                try:
                    client.update_import_run(
                        run_id=run_id,
                        candidates_processed=0,
                        inserts=0,
                        updates=0,
                        skips=0,
                        orphans_marked=0,
                        errors_json={"message": str(exc)},
                        report_artifact_url=None,
                    )
                except Exception:  # noqa: BLE001
                    logging.exception("failed to mark import_run as errored")
            return 1

    return 0


if __name__ == "__main__":
    # Support `python -m importer.cli ...` (used by every CI workflow, the
    # operator README, and the Task 19 smoke). Without this guard the module
    # would import and exit 0 without ever calling main() — a silent no-op.
    # `python -m importer` also works via importer/__main__.py.
    raise SystemExit(main())

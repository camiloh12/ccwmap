from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import load_state_locator
from importer.pipeline import run_pipeline
from importer.reports import PipelineResult
from importer.restriction_tag import RestrictionTag
from importer.sources.hifld_courts import HifldCourthousesSource
from importer.state_laws import StateLawCell, StateLawTable


FIXTURE_DIR = Path(__file__).parent / "fixtures"


def test_pipeline_dry_run_against_fixture() -> None:
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    source = HifldCourthousesSource(
        cache_path=FIXTURE_DIR / "hifld_courts_sample.geojson",
        state_locator=locator,
        dataset_version="HIFLD-FIXTURE",
    )
    table = StateLawTable(rows=[
        StateLawCell(
            state="US",
            category=RestrictionTag.STATE_LOCAL_GOVT,
            default_status="NO_GUN",
            confidence="high",
            conditions=[],
            citation="18 USC 930(a)",
            last_verified_date=date(2026, 5, 1),
        ),
    ])
    client = MagicMock()
    # Diff stage asks "what's already there?" — return empty so everything is INSERT.
    client.select_pins_by_keys.return_value = []

    result = run_pipeline(
        source=source,
        state_laws=table,
        client=client,
        states=["TX", "FL", "PA"],
        mode="dry-run",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert isinstance(result, PipelineResult)
    assert result.mode == "dry-run"
    assert result.candidates_fetched > 0
    assert len(result.diff.inserts) > 0
    # Dry-run must not write anything.
    client.upsert_pins.assert_not_called()
    client.mark_orphans.assert_not_called()


def test_pipeline_apply_mode_calls_client(monkeypatch) -> None:
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    source = HifldCourthousesSource(
        cache_path=FIXTURE_DIR / "hifld_courts_sample.geojson",
        state_locator=locator,
        dataset_version="HIFLD-FIXTURE",
    )
    table = StateLawTable(rows=[
        StateLawCell(
            state="US",
            category=RestrictionTag.STATE_LOCAL_GOVT,
            default_status="NO_GUN",
            confidence="high",
            conditions=[],
            citation="18 USC 930(a)",
            last_verified_date=date(2026, 5, 1),
        ),
    ])
    client = MagicMock()
    client.select_pins_by_keys.return_value = []

    run_pipeline(
        source=source,
        state_laws=table,
        client=client,
        states=["TX"],
        mode="apply",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert client.upsert_pins.called

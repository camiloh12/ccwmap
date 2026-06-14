from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import load_state_locator
from importer.pipeline import run_pipeline
from importer.reports import PipelineResult
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source
from importer.sources.hifld_courts import HifldCourthousesSource
from importer.state_laws import StateLawCell, StateLawTable


FIXTURE_DIR = Path(__file__).parent / "fixtures"


def _table() -> StateLawTable:
    return StateLawTable(rows=[
        StateLawCell(
            state="US", category=RestrictionTag.STATE_LOCAL_GOVT,
            default_status="NO_GUN", confidence="high", conditions=[],
            citation="18 USC 930(a)", last_verified_date=date(2026, 5, 1),
        ),
        StateLawCell(
            state="US", category=RestrictionTag.FEDERAL_PROPERTY,
            default_status="NO_GUN", confidence="high", conditions=[],
            citation="18 USC 930(a)", last_verified_date=date(2026, 5, 1),
        ),
    ])


def _mock_client():
    client = MagicMock()
    client.select_pins_by_keys.return_value = []
    client.select_user_pins.return_value = []
    return client


def test_pipeline_dry_run_against_fixture() -> None:
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    source = HifldCourthousesSource(
        cache_path=FIXTURE_DIR / "hifld_courts_sample.geojson",
        state_locator=locator,
        dataset_version="HIFLD-FIXTURE",
    )
    client = _mock_client()
    result = run_pipeline(
        sources=[source],
        state_laws=_table(),
        client=client,
        states=["TX", "FL", "PA"],
        mode="dry-run",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert isinstance(result, PipelineResult)
    assert result.mode == "dry-run"
    assert len(result.sources) == 1
    assert result.sources[0].candidates_fetched > 0
    assert len(result.sources[0].diff.inserts) > 0
    client.upsert_pins.assert_not_called()
    client.mark_orphans.assert_not_called()


def test_pipeline_apply_mode_calls_client() -> None:
    locator = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
    source = HifldCourthousesSource(
        cache_path=FIXTURE_DIR / "hifld_courts_sample.geojson",
        state_locator=locator,
        dataset_version="HIFLD-FIXTURE",
    )
    client = _mock_client()
    run_pipeline(
        sources=[source],
        state_laws=_table(),
        client=client,
        states=["TX"],
        mode="apply",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert client.upsert_pins.called


class _FakeSource(Source):
    def __init__(self, name, candidates):
        self.SOURCE_NAME = name
        self._candidates = candidates
        self.last_skip_counts = {}

    def fetch(self, *, refetch=False):
        pass

    def iter_candidates(self, state_filter):
        yield from self._candidates


def _cand(source, eid, name, lat, lng):
    return Candidate(
        source=source, source_external_id=eid, source_dataset_version="v",
        name=name, latitude=lat, longitude=lng,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.FEDERAL_PROPERTY, state="TX",
    )


def test_pipeline_dedups_across_sources() -> None:
    gsa = _FakeSource("gsa", [_cand("gsa", "g1", "Federal Building Austin", 30.2672, -97.7431)])
    mil = _FakeSource("hifld_military", [_cand("hifld_military", "m1", "Federal Building Austin", 30.2673, -97.7432)])
    client = _mock_client()
    result = run_pipeline(
        sources=[gsa, mil],
        state_laws=_table(),
        client=client,
        states=["TX"],
        mode="dry-run",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert {s.source for s in result.sources} == {"gsa", "hifld_military"}
    assert result.dedup.drops_by_pair.get(("gsa", "hifld_military")) == 1
    total_inserts = sum(len(s.diff.inserts) for s in result.sources)
    assert total_inserts == 1


def test_pipeline_surfaces_ipeds_missing_cells() -> None:
    from datetime import date as _date
    from importer.state_laws import StateLawCell

    def _college(eid, state, lat, lng):
        return Candidate(
            source="ipeds", source_external_id=eid, source_dataset_version="v",
            name=f"College {eid}", latitude=lat, longitude=lng,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.COLLEGE_UNIVERSITY, state=state,
        )

    ipeds = _FakeSource("ipeds", [
        _college("u-fl", "FL", 29.6436, -82.3549),
        _college("u-tx", "TX", 30.2849, -97.7341),
        _college("u-pa", "PA", 40.7982, -77.8599),
    ])
    table = StateLawTable(rows=[
        StateLawCell(
            state="FL", category=RestrictionTag.COLLEGE_UNIVERSITY,
            default_status="NO_GUN", confidence="high", conditions=[],
            citation="Fla. Stat. 790.06(12)(a)(13)",
            last_verified_date=_date(2026, 5, 31), source_filter=["ipeds"],
        ),
    ])
    client = _mock_client()
    result = run_pipeline(
        sources=[ipeds],
        state_laws=table,
        client=client,
        states=["TX", "FL", "PA"],
        mode="dry-run",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    src = next(s for s in result.sources if s.source == "ipeds")
    assert src.classified == 1            # only FL
    assert src.dropped_no_cell == 2       # TX + PA
    assert ("TX", "COLLEGE_UNIVERSITY") in src.missing_cells
    assert ("PA", "COLLEGE_UNIVERSITY") in src.missing_cells
    assert len(src.diff.inserts) == 1     # only the FL college is written

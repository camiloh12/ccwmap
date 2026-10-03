from datetime import date
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import load_state_locator
from importer.pipeline import run_pipeline
from importer.reports import PipelineResult
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source
from importer.sources.hifld_courts import HifldCourthousesSource
from importer.stages.orphans import OrphanCapExceeded
from importer.state_laws import StateLawCell, StateLawTable
from importer.supabase_client import ExistingPinRow


FIXTURE_DIR = Path(__file__).parent / "fixtures"
LOCATOR = load_state_locator(FIXTURE_DIR / "states_sample.geojson")
SYS = "81775f8b-1a6a-47d6-b793-e9ab7e38634e"
AUSTIN, MIAMI = (30.27, -97.74), (25.77, -80.19)


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
    client.select_system_pins.return_value = []
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
    def __init__(self, name, candidates, skips=None):
        self.SOURCE_NAME = name
        self._candidates = candidates
        self.last_skip_counts = dict(skips or {})

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


def _osm_bar_table() -> StateLawTable:
    return StateLawTable(rows=[
        StateLawCell(
            state="TX", category=RestrictionTag.BAR_ALCOHOL,
            default_status="NO_GUN", confidence="medium", conditions=[],
            citation="TX Penal Code 46.03(a)(7)",
            last_verified_date=date(2026, 5, 31), source_filter=["osm"],
        ),
    ])


def _osm_bar() -> Candidate:
    return Candidate(
        source="osm", source_external_id="node/1", source_dataset_version="v",
        name="The Houston Tap", latitude=29.7604, longitude=-95.3698,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.BAR_ALCOHOL, state="TX",
    )


def test_apply_generates_odbl_dump_when_osm_inserts(monkeypatch) -> None:
    import importer.pipeline as pipeline_mod
    calls = {}

    def fake_generate(*, client, out_dir, **kwargs):
        calls["called"] = True
        return "https://example/storage/v1/object/public/odbl-dumps/dump-2026-06-16.csv.gz"

    monkeypatch.setattr(pipeline_mod, "generate_and_upload", fake_generate)

    result = run_pipeline(
        sources=[_FakeSource("osm", [_osm_bar()])],
        state_laws=_osm_bar_table(),
        client=_mock_client(),
        states=["TX"],
        mode="apply",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert calls.get("called") is True
    assert result.odbl_dump_url.endswith("dump-2026-06-16.csv.gz")


def test_dry_run_does_not_generate_odbl_dump(monkeypatch) -> None:
    import importer.pipeline as pipeline_mod
    calls = {}
    monkeypatch.setattr(
        pipeline_mod, "generate_and_upload",
        lambda **kw: calls.setdefault("called", True),
    )
    result = run_pipeline(
        sources=[_FakeSource("osm", [_osm_bar()])],
        state_laws=_osm_bar_table(),
        client=_mock_client(),
        states=["TX"],
        mode="dry-run",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )
    assert "called" not in calls
    assert result.odbl_dump_url is None


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


def _pin(pid, at=AUSTIN, *, source="gsa", eid=None, user_modified=False):
    return ExistingPinRow(
        id=pid, source=source, source_external_id=eid or f"E-{pid}", name=f"Pin {pid}",
        latitude=at[0], longitude=at[1], status=2, restriction_tag="FEDERAL_PROPERTY",
        user_modified=user_modified, source_dataset_version="v",
    )


def _client_with(pins_by_source):
    client = _mock_client()
    client.select_system_pins.side_effect = lambda name: pins_by_source.get(name, [])
    return client


def _run(sources, client, *, mode="apply", states=("TX",), **kw):
    return run_pipeline(
        sources=sources, state_laws=_table(), client=client, states=list(states),
        mode=mode, system_user_id=SYS, state_locator=LOCATOR, **kw,
    )


def test_orphans_are_scoped_to_the_run_states():
    tx, fl = _pin("tx", AUSTIN), _pin("fl", MIAMI)
    result = _run([_FakeSource("gsa", [])], _client_with({"gsa": [tx, fl]}), mode="dry-run")
    assert result.sources[0].diff.orphans == [tx]


def test_default_apply_marks_orphans_and_deletes_nothing():
    client = _client_with({"gsa": [_pin("tx")]})
    _run([_FakeSource("gsa", [])], client)
    client.mark_orphans.assert_called_once_with(["tx"])
    client.delete_pins.assert_not_called()


def test_delete_orphans_deletes_uncorrected_and_marks_corrected():
    gone, fixed = _pin("gone"), _pin("fixed", user_modified=True)
    client = _client_with({"gsa": [gone, fixed]})
    client.delete_pins.return_value = ["gone"]
    _run([_FakeSource("gsa", [])], client, delete_orphans=True)
    client.delete_pins.assert_called_once_with(["gone"])
    client.mark_orphans.assert_called_once_with(["fixed"])


def _over_cap_run(**kw):
    # gsa would insert one pin; military would delete 51 of its 51 in-scope pins (cap 50).
    gsa = _FakeSource("gsa", [_cand("gsa", "g1", "Federal Building Austin", 30.2672, -97.7431)])
    mil = _FakeSource("hifld_military", [])
    client = _client_with({"hifld_military": [_pin(f"m{i}", source="hifld_military") for i in range(51)]})
    return client, (lambda mode: _run([gsa, mil], client, mode=mode, **kw))


def test_cap_breach_stops_the_apply_before_any_write():
    client, run = _over_cap_run(delete_orphans=True)
    with pytest.raises(OrphanCapExceeded, match="hifld_military: 51 orphan deletions exceed the cap of 50"):
        run("apply")
    for write in ("upsert_pins", "patch_external_id", "delete_pins", "mark_orphans"):
        getattr(client, write).assert_not_called()


def test_dry_run_reports_a_cap_breach_as_an_error():
    client, run = _over_cap_run()
    result = run("dry-run")
    assert any("hifld_military: 51 orphan deletions exceed the cap of 50" in e for e in result.errors)
    client.delete_pins.assert_not_called()


def test_cap_override_lets_a_large_deletion_through():
    client, run = _over_cap_run(delete_orphans=True, orphan_delete_cap=100)
    client.delete_pins.return_value = [f"m{i}" for i in range(51)]
    run("apply")
    assert len(client.delete_pins.call_args.args[0]) == 51


def test_rekey_flows_from_source_to_writes():
    cand = Candidate(
        source="gsa", source_external_id="13-14-140", source_dataset_version="v",
        name="San Antonio Federal Center", latitude=29.4241, longitude=-98.4936,
        coord_quality=CoordQuality.PRECISE, category=RestrictionTag.FEDERAL_PROPERTY,
        state="TX", legacy_external_id="140", legacy_point=(29.4241, -98.4936),
    )
    client = _client_with({"gsa": [_pin("pin-140", (29.4241, -98.4936), eid="140")]})
    result = _run([_FakeSource("gsa", [cand])], client)
    assert [r.pin_id for r in result.sources[0].diff.rekeys] == ["pin-140"]
    client.patch_external_id.assert_called_once_with("pin-140", "13-14-140")
    assert [r.source_external_id for r in client.upsert_pins.call_args.args[0]] == ["13-14-140"]
    client.mark_orphans.assert_not_called()


def test_delete_orphans_is_rejected_outside_apply():
    with pytest.raises(ValueError, match="apply-only"):
        _run([_FakeSource("gsa", [])], _mock_client(), mode="dry-run", delete_orphans=True)


def test_skip_counts_reach_the_result():
    result = _run([_FakeSource("gsa", [], skips={"disposed": 3})], _mock_client(), mode="dry-run")
    assert result.sources[0].skip_counts == {"disposed": 3}

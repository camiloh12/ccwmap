import json
from datetime import datetime, timezone

from importer.reports import DedupReport, PipelineResult, SourceResult
from importer.reports.json_report import render_json
from importer.stages.diff import DiffResult


def test_json_report_is_valid_json_and_contains_counts() -> None:
    result = PipelineResult(
        mode="apply",
        started_at=datetime(2026, 5, 24, tzinfo=timezone.utc),
        completed_at=datetime(2026, 5, 24, tzinfo=timezone.utc),
        states=["TX"],
        sources=[SourceResult(
            source="hifld_courts",
            candidates_fetched=10,
            candidates_after_state_filter=10,
            classified=10,
            dropped_no_cell=0,
            missing_cells=[],
            name_truncations=0,
            diff=DiffResult(inserts=[], updates=[], skips=[], orphans=[]),
        )],
        dedup=DedupReport(),
    )
    payload = json.loads(render_json(result))
    assert payload["mode"] == "apply"
    assert payload["sources"][0]["source"] == "hifld_courts"
    assert payload["sources"][0]["counts"]["candidates_fetched"] == 10
    assert payload["sources"][0]["counts"]["inserts"] == 0


def test_json_report_has_rekeys_the_orphan_split_and_skips() -> None:
    from datetime import date

    from importer.candidate import Candidate, CoordQuality
    from importer.restriction_tag import RestrictionTag
    from importer.stages.apply_state_law import ClassifiedCandidate
    from importer.stages.diff import Rekey
    from importer.stages.orphans import OrphanPlan
    from importer.state_laws import StateLawCell
    from importer.supabase_client import ExistingPinRow

    cell = StateLawCell(state="US", category=RestrictionTag.FEDERAL_PROPERTY, default_status="NO_GUN",
                        confidence="high", conditions=[], citation="x", last_verified_date=date(2026, 5, 31))
    cc = ClassifiedCandidate(candidate=Candidate(
        source="gsa", source_external_id="13-14-140", source_dataset_version="v", name="B",
        latitude=30.0, longitude=-97.0, coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.FEDERAL_PROPERTY, state="TX"), cell=cell)
    gone = ExistingPinRow(id="g", source="gsa", source_external_id="OLD", name="Old", latitude=30.0,
                          longitude=-97.0, status=2, restriction_tag="FEDERAL_PROPERTY",
                          user_modified=False, source_dataset_version="v")
    diff = DiffResult(inserts=[], updates=[], skips=[], orphans=[gone],
                      rekeys=[Rekey(pin_id="p", old_external_id="140", new_external_id="13-14-140",
                                    user_modified=False, classified=cc)])
    result = PipelineResult(
        mode="apply", started_at=datetime(2026, 10, 2, tzinfo=timezone.utc), completed_at=None,
        states=["TX"], dedup=DedupReport(),
        sources=[SourceResult(source="gsa", candidates_fetched=1, candidates_after_state_filter=1,
                              classified=1, dropped_no_cell=0, missing_cells=[], name_truncations=0,
                              diff=diff, orphan_plan=OrphanPlan(delete=[gone], cap=50),
                              skip_counts={"disposed": 103})],
    )
    src = json.loads(render_json(result))["sources"][0]
    assert src["counts"]["rekeys"] == 1
    assert src["counts"]["rekey_too_far"] == 0
    assert src["counts"]["orphans_deleted"] == 1
    assert src["counts"]["orphans_kept_user_corrected"] == 0
    assert src["counts"]["orphans_marked"] == 0
    assert src["counts"]["orphan_delete_cap"] == 50
    assert src["counts"]["orphan_cap_breached"] is False
    assert src["skip_counts"] == {"disposed": 103}
    assert src["rekeys"] == [{"pin_id": "p", "old_external_id": "140",
                              "new_external_id": "13-14-140", "user_modified": False}]
    assert src["orphans"] == [{"id": "g", "source_external_id": "OLD", "name": "Old", "action": "delete"}]

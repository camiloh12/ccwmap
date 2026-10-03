from datetime import datetime, timezone

from importer.reports import DedupReport, PipelineResult, SourceResult
from importer.reports.markdown import render_markdown
from importer.stages.diff import DiffResult


def _empty_diff() -> DiffResult:
    return DiffResult(inserts=[], updates=[], skips=[], orphans=[])


def _source(**kw) -> SourceResult:
    defaults = dict(
        source="hifld_courts",
        candidates_fetched=200,
        candidates_after_state_filter=150,
        classified=148,
        dropped_no_cell=2,
        missing_cells=[("TX", "HEALTHCARE")],
        name_truncations=3,
        diff=_empty_diff(),
    )
    defaults.update(kw)
    return SourceResult(**defaults)


def test_markdown_includes_header_and_counts() -> None:
    result = PipelineResult(
        mode="dry-run",
        started_at=datetime(2026, 5, 24, 12, 0, tzinfo=timezone.utc),
        completed_at=datetime(2026, 5, 24, 12, 1, tzinfo=timezone.utc),
        states=["TX", "FL", "PA"],
        sources=[_source()],
        dedup=DedupReport(),
    )
    md = render_markdown(result)
    assert "# Importer dry-run report" in md
    assert "hifld_courts" in md
    assert "TX, FL, PA" in md
    assert "Candidates fetched: **200**" in md
    assert "Name truncations: **3**" in md
    assert "(TX, HEALTHCARE)" in md
    assert "## Cross-source dedup" in md


def test_markdown_flags_missing_cells_section() -> None:
    result = PipelineResult(
        mode="dry-run",
        started_at=datetime.now(timezone.utc),
        completed_at=None,
        states=["TX"],
        sources=[_source(
            candidates_fetched=10,
            candidates_after_state_filter=10,
            classified=8,
            dropped_no_cell=2,
            missing_cells=[("TX", "BAR_ALCOHOL"), ("TX", "HEALTHCARE")],
            name_truncations=0,
        )],
        dedup=DedupReport(),
    )
    md = render_markdown(result)
    assert "**Needs research**" in md
    assert "(TX, BAR_ALCOHOL)" in md
    assert "(TX, HEALTHCARE)" in md


def test_markdown_renders_odbl_dump_url() -> None:
    result = PipelineResult(
        mode="apply",
        started_at=datetime(2026, 6, 16, tzinfo=timezone.utc),
        completed_at=datetime(2026, 6, 16, tzinfo=timezone.utc),
        states=["TX", "FL"],
        sources=[],
        dedup=DedupReport(),
        odbl_dump_url="https://example.supabase.co/storage/v1/object/public/odbl-dumps/dump-2026-06-16.csv.gz",
    )
    md = render_markdown(result)
    assert "## ODbL dump" in md
    assert "dump-2026-06-16.csv.gz" in md


from datetime import date

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import Rekey
from importer.stages.orphans import OrphanPlan
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow

CELL = StateLawCell(state="US", category=RestrictionTag.FEDERAL_PROPERTY, default_status="NO_GUN",
                    confidence="high", conditions=[], citation="18 USC §930(a)",
                    last_verified_date=date(2026, 5, 31))


def _row(pid, eid, *, user_modified=False):
    return ExistingPinRow(id=pid, source="gsa", source_external_id=eid, name=f"Pin {eid}",
                          latitude=30.0, longitude=-97.0, status=2, restriction_tag="FEDERAL_PROPERTY",
                          user_modified=user_modified, source_dataset_version="v")


def _rekey(new):
    cc = ClassifiedCandidate(candidate=Candidate(
        source="gsa", source_external_id=new, source_dataset_version="v", name="B",
        latitude=30.0, longitude=-97.0, coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.FEDERAL_PROPERTY, state="TX"), cell=CELL)
    return Rekey(pin_id=f"pin-{new}", old_external_id="140", new_external_id=new,
                 user_modified=False, classified=cc)


def _cleanup_result(mode, *, too_far=0, plan=None):
    a, b, c = _row("a", "GONE-A"), _row("b", "GONE-B"), _row("c", "FIXED", user_modified=True)
    diff = DiffResult(inserts=[], updates=[], skips=[], orphans=[a, b, c],
                      rekeys=[_rekey("13-14-140")], rekey_too_far=too_far)
    return PipelineResult(
        mode=mode, started_at=datetime(2026, 10, 2, tzinfo=timezone.utc), completed_at=None,
        states=["TX"], dedup=DedupReport(),
        sources=[_source(diff=diff, orphan_plan=plan or OrphanPlan(delete=[a, b], keep=[c]),
                         skip_counts={"disposed": 103, "filtered_out": 7})],
    )


def test_markdown_apply_shows_rekeys_and_the_orphan_split() -> None:
    md = render_markdown(_cleanup_result("apply"))
    assert "Re-key: **1**" in md
    assert "Orphan: **3** (deleted **2**, kept, user-corrected **1**, marked **0**)" in md
    assert "- `GONE-A` — Pin GONE-A (delete)" in md
    assert "- `FIXED` — Pin FIXED (keep)" in md
    assert "too far" not in md


def test_markdown_dry_run_previews_what_delete_orphans_would_do() -> None:
    md = render_markdown(_cleanup_result("dry-run"))
    assert "an apply with `--delete-orphans` would delete **2** and keep **1** user-corrected" in md


def test_markdown_shows_rekey_too_far_and_a_cap_breach() -> None:
    a = _row("a", "GONE-A")
    md = render_markdown(_cleanup_result("dry-run", too_far=2, plan=OrphanPlan(delete=[a], cap=0)))
    assert "Re-key too far (inserted; old pin left as an orphan): **2**" in md
    assert "Orphan delete cap breached: 1 deletions > cap 0" in md


def test_markdown_lists_skip_counts() -> None:
    md = render_markdown(_cleanup_result("apply"))
    assert "Skipped at source: `disposed` 103, `filtered_out` 7" in md

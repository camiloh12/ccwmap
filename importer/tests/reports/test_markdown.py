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

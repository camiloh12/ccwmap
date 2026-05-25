import json
from datetime import datetime, timezone

from importer.reports import PipelineResult
from importer.reports.json_report import render_json
from importer.stages.diff import DiffResult


def test_json_report_is_valid_json_and_contains_counts() -> None:
    result = PipelineResult(
        mode="apply",
        started_at=datetime(2026, 5, 24, tzinfo=timezone.utc),
        completed_at=datetime(2026, 5, 24, tzinfo=timezone.utc),
        source="hifld_courts",
        states=["TX"],
        candidates_fetched=10,
        candidates_after_state_filter=10,
        classified=10,
        dropped_no_cell=0,
        missing_cells=[],
        name_truncations=0,
        diff=DiffResult(inserts=[], updates=[], skips=[], orphans=[]),
    )
    payload = json.loads(render_json(result))
    assert payload["mode"] == "apply"
    assert payload["source"] == "hifld_courts"
    assert payload["counts"]["candidates_fetched"] == 10
    assert payload["counts"]["inserts"] == 0

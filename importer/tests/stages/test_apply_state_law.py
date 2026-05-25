from datetime import date
from pathlib import Path

import pytest

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import (
    ApplyStateLawStats,
    ClassifiedCandidate,
    apply_state_law,
)
from importer.state_laws import StateLawCell, StateLawTable


def _candidate(state: str, category: RestrictionTag) -> Candidate:
    return Candidate(
        source="hifld_courts",
        source_external_id=f"{state}-{category.name}",
        source_dataset_version="v1",
        name="X",
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.PRECISE,
        category=category,
        state=state,
    )


@pytest.fixture()
def table() -> StateLawTable:
    return StateLawTable(
        rows=[
            StateLawCell(
                state="US",
                category=RestrictionTag.STATE_LOCAL_GOVT,
                default_status="NO_GUN",
                confidence="high",
                conditions=[],
                citation="18 USC 930(a)",
                last_verified_date=date(2026, 5, 1),
            ),
        ]
    )


def test_candidate_with_us_fallback_is_classified(table: StateLawTable) -> None:
    stats = ApplyStateLawStats()
    out = list(
        apply_state_law(
            [_candidate("TX", RestrictionTag.STATE_LOCAL_GOVT)],
            table=table,
            stats=stats,
        )
    )
    assert len(out) == 1
    cc = out[0]
    assert isinstance(cc, ClassifiedCandidate)
    assert cc.cell.citation == "18 USC 930(a)"
    assert stats.dropped_no_cell == 0


def test_candidate_with_no_cell_is_dropped_and_recorded(table: StateLawTable) -> None:
    stats = ApplyStateLawStats()
    out = list(
        apply_state_law(
            [_candidate("TX", RestrictionTag.HEALTHCARE)],
            table=table,
            stats=stats,
        )
    )
    assert out == []
    assert stats.dropped_no_cell == 1
    assert ("TX", RestrictionTag.HEALTHCARE.name) in stats.missing_cells


def test_source_filter_in_cell_is_respected(table: StateLawTable) -> None:
    # Cell with source_filter=['osm'] must NOT match an hifld_courts candidate.
    table_with_filter = StateLawTable(
        rows=[
            StateLawCell(
                state="US",
                category=RestrictionTag.STATE_LOCAL_GOVT,
                default_status="NO_GUN",
                confidence="high",
                conditions=[],
                citation="should not apply",
                last_verified_date=date(2026, 5, 1),
                source_filter=["osm"],
            ),
        ]
    )
    stats = ApplyStateLawStats()
    out = list(
        apply_state_law(
            [_candidate("TX", RestrictionTag.STATE_LOCAL_GOVT)],
            table=table_with_filter,
            stats=stats,
        )
    )
    assert out == []
    assert stats.dropped_no_cell == 1

from datetime import date

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
    assert stats.classified == 1
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
    assert ("TX", RestrictionTag.STATE_LOCAL_GOVT.name) in stats.missing_cells


def _fed_cell(confidence):
    return StateLawCell(
        state="US", category=RestrictionTag.FEDERAL_PROPERTY, default_status="NO_GUN",
        confidence=confidence, citation="18 USC §930(a)", last_verified_date=date(2026, 10, 25),
    )


def _fed(override=None):
    return Candidate(
        source="gsa", source_external_id="47-00-1", source_dataset_version="v",
        name="Federal Building", latitude=30.27, longitude=-97.74,
        coord_quality=CoordQuality.PRECISE, category=RestrictionTag.FEDERAL_PROPERTY,
        state="TX", confidence_override=override,
    )


def test_override_lowers_confidence_and_leaves_the_cell_alone():
    cc = ClassifiedCandidate(candidate=_fed("medium"), cell=_fed_cell("high"))
    assert cc.confidence == "medium"
    assert (cc.cell.default_status, cc.cell.citation) == ("NO_GUN", "18 USC §930(a)")


def test_without_an_override_the_cell_decides():
    assert ClassifiedCandidate(candidate=_fed(), cell=_fed_cell("high")).confidence == "high"


def test_an_override_cannot_raise_confidence():
    with pytest.raises(ValueError, match="may only lower"):
        ClassifiedCandidate(candidate=_fed("high"), cell=_fed_cell("medium"))


def test_classification_fails_on_an_illegal_override():
    table = StateLawTable(rows=[_fed_cell("medium")])
    with pytest.raises(ValueError, match="may only lower"):
        list(apply_state_law([_fed("high")], table=table, stats=ApplyStateLawStats()))

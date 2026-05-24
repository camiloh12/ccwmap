import pytest
from pydantic import ValidationError

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag


def test_restriction_tag_mirrors_dart_enum_exactly() -> None:
    expected = [
        "FEDERAL_PROPERTY",
        "AIRPORT_SECURE",
        "STATE_LOCAL_GOVT",
        "SCHOOL_K12",
        "COLLEGE_UNIVERSITY",
        "BAR_ALCOHOL",
        "HEALTHCARE",
        "PLACE_OF_WORSHIP",
        "SPORTS_ENTERTAINMENT",
        "PRIVATE_PROPERTY",
    ]
    assert [t.name for t in RestrictionTag] == expected


def test_candidate_round_trips_minimal_fields() -> None:
    c = Candidate(
        source="hifld_courts",
        source_external_id="C-123",
        source_dataset_version="HIFLD-2026-05",
        name="Harris County Courthouse",
        latitude=29.7604,
        longitude=-95.3698,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.STATE_LOCAL_GOVT,
        state="TX",
        extra={"loemins": "STATE"},
    )
    assert c.state == "TX"
    assert c.category is RestrictionTag.STATE_LOCAL_GOVT


def test_candidate_rejects_out_of_range_latitude() -> None:
    with pytest.raises(ValidationError):
        Candidate(
            source="hifld_courts",
            source_external_id="C-1",
            source_dataset_version="v1",
            name="x",
            latitude=91.0,
            longitude=0.0,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.STATE_LOCAL_GOVT,
            state="TX",
        )


def test_candidate_rejects_non_two_letter_state() -> None:
    with pytest.raises(ValidationError):
        Candidate(
            source="hifld_courts",
            source_external_id="C-1",
            source_dataset_version="v1",
            name="x",
            latitude=30.0,
            longitude=-95.0,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.STATE_LOCAL_GOVT,
            state="Texas",
        )

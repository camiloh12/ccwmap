from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.refine_coords import refine_coords


def _candidate() -> Candidate:
    return Candidate(
        source="hifld_courts",
        source_external_id="C-1",
        source_dataset_version="v1",
        name="Test",
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.ADDRESS_CENTROID,
        category=RestrictionTag.STATE_LOCAL_GOVT,
        state="TX",
    )


def test_refine_coords_returns_input_unchanged() -> None:
    inputs = [_candidate()]
    outputs = list(refine_coords(inputs))
    assert outputs == inputs

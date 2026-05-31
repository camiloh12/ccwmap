from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.dedup import dedup


def _candidate(eid: str) -> Candidate:
    return Candidate(
        source="hifld_courts",
        source_external_id=eid,
        source_dataset_version="v1",
        name=f"Test {eid}",
        latitude=29.0,
        longitude=-95.0,
        coord_quality=CoordQuality.PRECISE,
        category=RestrictionTag.STATE_LOCAL_GOVT,
        state="TX",
    )


def test_dedup_returns_all_inputs_in_phase_2() -> None:
    inputs = [_candidate("a"), _candidate("b")]
    outputs = list(dedup(inputs, existing_user_pins=[]))
    assert outputs == inputs

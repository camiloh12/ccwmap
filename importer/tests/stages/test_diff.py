from datetime import date
from uuid import uuid4

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import DiffResult, DiffStats, diff_candidates
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow


CELL = StateLawCell(
    state="US",
    category=RestrictionTag.STATE_LOCAL_GOVT,
    default_status="NO_GUN",
    confidence="high",
    conditions=[],
    citation="18 USC 930(a)",
    last_verified_date=date(2026, 5, 1),
)


def _classified(eid: str, name: str = "X") -> ClassifiedCandidate:
    return ClassifiedCandidate(
        candidate=Candidate(
            source="hifld_courts",
            source_external_id=eid,
            source_dataset_version="HIFLD-2026-05",
            name=name,
            latitude=29.0,
            longitude=-95.0,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.STATE_LOCAL_GOVT,
            state="TX",
        ),
        cell=CELL,
    )


def test_no_match_classifies_as_insert() -> None:
    stats = DiffStats()
    result = diff_candidates([_classified("NEW")], existing=[], stats=stats)
    assert isinstance(result, DiffResult)
    assert len(result.inserts) == 1
    assert result.inserts[0].candidate.source_external_id == "NEW"
    assert stats.inserts == 1


def test_match_user_modified_is_skip() -> None:
    existing = [
        ExistingPinRow(
            id=str(uuid4()),
            source="hifld_courts",
            source_external_id="USR",
            name="User-edited name",
            latitude=29.0,
            longitude=-95.0,
            status=2,
            restriction_tag="STATE_LOCAL_GOVT",
            user_modified=True,
            source_dataset_version="HIFLD-2026-04",
        )
    ]
    stats = DiffStats()
    result = diff_candidates([_classified("USR", "Source name")], existing=existing, stats=stats)
    assert result.inserts == []
    assert len(result.skips) == 1
    assert stats.skips == 1


def test_match_not_user_modified_is_update() -> None:
    existing = [
        ExistingPinRow(
            id=str(uuid4()),
            source="hifld_courts",
            source_external_id="UPD",
            name="Stale name",
            latitude=29.0,
            longitude=-95.0,
            status=2,
            restriction_tag="STATE_LOCAL_GOVT",
            user_modified=False,
            source_dataset_version="HIFLD-2026-04",
        )
    ]
    stats = DiffStats()
    result = diff_candidates([_classified("UPD", "Fresh name")], existing=existing, stats=stats)
    assert len(result.updates) == 1
    assert stats.updates == 1


def test_existing_row_not_in_current_run_is_orphan() -> None:
    existing = [
        ExistingPinRow(
            id=str(uuid4()),
            source="hifld_courts",
            source_external_id="GONE",
            name="Closed courthouse",
            latitude=29.0,
            longitude=-95.0,
            status=2,
            restriction_tag="STATE_LOCAL_GOVT",
            user_modified=False,
            source_dataset_version="HIFLD-2026-04",
        )
    ]
    stats = DiffStats()
    result = diff_candidates([_classified("STAYING")], existing=existing, stats=stats)
    assert len(result.inserts) == 1
    assert len(result.orphans) == 1
    assert result.orphans[0].source_external_id == "GONE"
    assert stats.orphans == 1

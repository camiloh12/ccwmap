from datetime import date
from unittest.mock import MagicMock

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply import apply_to_supabase
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import DiffResult
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow, SupabaseUpsertRow


CELL = StateLawCell(
    state="US",
    category=RestrictionTag.STATE_LOCAL_GOVT,
    default_status="NO_GUN",
    confidence="high",
    conditions=[],
    citation="18 USC 930(a)",
    last_verified_date=date(2026, 5, 1),
)


def _classified(eid: str) -> ClassifiedCandidate:
    return ClassifiedCandidate(
        candidate=Candidate(
            source="hifld_courts",
            source_external_id=eid,
            source_dataset_version="HIFLD-2026-05",
            name="Courthouse",
            latitude=29.0,
            longitude=-95.0,
            coord_quality=CoordQuality.PRECISE,
            category=RestrictionTag.STATE_LOCAL_GOVT,
            state="TX",
        ),
        cell=CELL,
    )


def _orphan(eid: str) -> ExistingPinRow:
    return ExistingPinRow(
        id="00000000-0000-0000-0000-000000000099",
        source="hifld_courts",
        source_external_id=eid,
        name="X",
        latitude=0.0,
        longitude=0.0,
        status=2,
        restriction_tag="STATE_LOCAL_GOVT",
        user_modified=False,
        source_dataset_version="old",
    )


def test_apply_writes_inserts_and_updates_and_marks_orphans() -> None:
    client = MagicMock()
    diff = DiffResult(
        inserts=[_classified("A"), _classified("B")],
        updates=[_classified("C")],
        skips=[_classified("D")],
        orphans=[_orphan("Z")],
    )
    apply_to_supabase(
        diff,
        client=client,
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
        source="hifld_courts",
    )

    # Upsert called once with insert+update rows merged (3 total).
    client.upsert_pins.assert_called_once()
    rows = client.upsert_pins.call_args.args[0]
    assert len(rows) == 3
    assert all(isinstance(r, SupabaseUpsertRow) for r in rows)
    assert {r.source_external_id for r in rows} == {"A", "B", "C"}

    # Orphan-marking called for "Z" only.
    client.mark_orphans.assert_called_once_with("hifld_courts", ["Z"])


def test_apply_derives_status_from_cell() -> None:
    client = MagicMock()
    diff = DiffResult(inserts=[_classified("A")], updates=[], skips=[], orphans=[])
    apply_to_supabase(
        diff,
        client=client,
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
        source="hifld_courts",
    )
    row = client.upsert_pins.call_args.args[0][0]
    assert row.status == 2  # NO_GUN
    assert row.restriction_tag == "STATE_LOCAL_GOVT"
    assert row.legal_citation == "18 USC 930(a)"
    assert row.confidence == "high"
    assert row.legal_citation_verified_date == "2026-05-01"
    assert row.has_security_screening is True  # courthouses default true
    assert row.has_posted_signage is False     # spec §1: importer cannot verify
    assert row.created_by == "81775f8b-1a6a-47d6-b793-e9ab7e38634e"


def test_apply_with_empty_diff_does_nothing() -> None:
    client = MagicMock()
    diff = DiffResult(inserts=[], updates=[], skips=[], orphans=[])
    apply_to_supabase(
        diff,
        client=client,
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
        source="hifld_courts",
    )
    client.upsert_pins.assert_not_called()
    client.mark_orphans.assert_not_called()

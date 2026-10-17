from datetime import date
from unittest.mock import MagicMock

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply import apply_to_supabase
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import DiffResult, Rekey
from importer.stages.orphans import OrphanPlan
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow, SupabaseUpsertRow


SYS = "81775f8b-1a6a-47d6-b793-e9ab7e38634e"


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


def _orphan(eid: str, *, pin_id: str = "00000000-0000-0000-0000-000000000099",
            user_modified: bool = False) -> ExistingPinRow:
    return ExistingPinRow(
        id=pin_id, source="hifld_courts", source_external_id=eid, name="X",
        latitude=0.0, longitude=0.0, status=2, restriction_tag="STATE_LOCAL_GOVT",
        user_modified=user_modified, source_dataset_version="old",
    )


def _rekey(new: str, *, user_modified: bool) -> Rekey:
    return Rekey(pin_id=f"pin-{new}", old_external_id=" ", new_external_id=new,
                 user_modified=user_modified, classified=_classified(new))


def _empty_diff(**kw) -> DiffResult:
    return DiffResult(**{"inserts": [], "updates": [], "skips": [], "orphans": [], **kw})


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
    )

    # Upsert called once with insert+update rows merged (3 total).
    client.upsert_pins.assert_called_once()
    rows = client.upsert_pins.call_args.args[0]
    assert len(rows) == 3
    assert all(isinstance(r, SupabaseUpsertRow) for r in rows)
    assert {r.source_external_id for r in rows} == {"A", "B", "C"}

    # Orphan-marking by pin id.
    client.mark_orphans.assert_called_once_with(["00000000-0000-0000-0000-000000000099"])


def test_apply_derives_status_from_cell() -> None:
    client = MagicMock()
    diff = DiffResult(inserts=[_classified("A")], updates=[], skips=[], orphans=[])
    apply_to_supabase(
        diff,
        client=client,
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
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
    )
    client.upsert_pins.assert_not_called()
    client.mark_orphans.assert_not_called()


def test_rekeys_are_patched_before_the_upsert_and_refreshed_unless_corrected() -> None:
    client = MagicMock()
    diff = _empty_diff(inserts=[_classified("A")],
                       rekeys=[_rekey("R1", user_modified=False), _rekey("R2", user_modified=True)])
    apply_to_supabase(diff, client=client, system_user_id=SYS)
    assert [c[0] for c in client.mock_calls][:3] == ["patch_external_id", "patch_external_id", "upsert_pins"]
    client.patch_external_id.assert_any_call("pin-R1", "R1")
    client.patch_external_id.assert_any_call("pin-R2", "R2")
    rows = client.upsert_pins.call_args.args[0]
    # The corrected pin keeps its edits: re-keyed, but not refreshed.
    assert {r.source_external_id for r in rows} == {"A", "R1"}


def test_delete_plan_deletes_and_marks_the_user_corrected() -> None:
    client = MagicMock()
    gone, fixed = _orphan("G", pin_id="g"), _orphan("F", pin_id="f", user_modified=True)
    client.delete_pins.return_value = ["g"]
    apply_to_supabase(_empty_diff(orphans=[gone, fixed]), client=client, system_user_id=SYS,
                      orphan_plan=OrphanPlan(delete=[gone], keep=[fixed]))
    client.delete_pins.assert_called_once_with(["g"])
    client.mark_orphans.assert_called_once_with(["f"])


def test_pin_corrected_after_the_diff_is_marked_not_deleted() -> None:
    # The DELETE filters on user_modified = false, so a pin corrected between
    # the diff and the apply survives the delete; it must still be marked.
    client = MagicMock()
    a, b = _orphan("A", pin_id="a"), _orphan("B", pin_id="b")
    client.delete_pins.return_value = ["a"]
    apply_to_supabase(_empty_diff(orphans=[a, b]), client=client, system_user_id=SYS,
                      orphan_plan=OrphanPlan(delete=[a, b]))
    client.mark_orphans.assert_called_once_with(["b"])


def test_mark_plan_never_deletes() -> None:
    client = MagicMock()
    o = _orphan("Z", pin_id="z")
    apply_to_supabase(_empty_diff(orphans=[o]), client=client, system_user_id=SYS,
                      orphan_plan=OrphanPlan(mark=[o]))
    client.delete_pins.assert_not_called()
    client.mark_orphans.assert_called_once_with(["z"])

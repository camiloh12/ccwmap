from datetime import date
from uuid import uuid4

from importer.candidate import Candidate, CoordQuality
from importer.geo.distance import DEG_LAT_M
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import REKEY_MAX_M, DiffResult, DiffStats, diff_candidates
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


FED = StateLawCell(
    state="US", category=RestrictionTag.FEDERAL_PROPERTY, default_status="NO_GUN",
    confidence="high", conditions=[], citation="18 USC §930(a)",
    last_verified_date=date(2026, 5, 31),
)
SA = (29.4241, -98.4936)
LUBBOCK = (33.5779, -101.8552)


def _gsa(eid, legacy=None, legacy_point=SA):
    lat, lng = legacy_point
    return ClassifiedCandidate(
        candidate=Candidate(
            source="gsa", source_external_id=eid, source_dataset_version="FRPP-FY24",
            name=f"Building {eid}", latitude=lat, longitude=lng,
            coord_quality=CoordQuality.PRECISE, category=RestrictionTag.FEDERAL_PROPERTY,
            state="TX", legacy_external_id=legacy,
            legacy_point=legacy_point if legacy is not None else None,
        ),
        cell=FED,
    )


def _pin(eid, at=SA, *, pin_id=None, user_modified=False):
    return ExistingPinRow(
        id=pin_id or f"pin-{eid}", source="gsa", source_external_id=eid,
        name=f"Pin {eid}", latitude=at[0], longitude=at[1], status=2,
        restriction_tag="FEDERAL_PROPERTY", user_modified=user_modified,
        source_dataset_version="FRPP-FY24",
    )


def test_legacy_match_is_a_rekey() -> None:
    stats = DiffStats()
    result = diff_candidates([_gsa("13-14-140", legacy="140")], existing=[_pin("140")], stats=stats)
    assert [(r.pin_id, r.old_external_id, r.new_external_id) for r in result.rekeys] == [
        ("pin-140", "140", "13-14-140")
    ]
    assert result.inserts == [] and result.orphans == []
    assert stats.rekeys == 1


def test_colliding_legacy_ids_go_to_the_nearest_candidate() -> None:
    # Two agencies reported property id 140; the pin was the San Antonio one.
    # The Lubbock building comes first in file order and must not steal it.
    lubbock = _gsa("14-10-140", legacy="140", legacy_point=LUBBOCK)
    san_antonio = _gsa("13-14-140", legacy="140", legacy_point=SA)
    stats = DiffStats()
    result = diff_candidates([lubbock, san_antonio], existing=[_pin("140", SA)], stats=stats)
    assert [r.new_external_id for r in result.rekeys] == ["13-14-140"]
    assert [cc.candidate.source_external_id for cc in result.inserts] == ["14-10-140"]
    assert result.rekey_too_far == 0 and stats.rekey_too_far == 0


def test_legacy_pin_too_far_is_an_insert_an_orphan_and_counted() -> None:
    far = (SA[0] + (REKEY_MAX_M + 30) / 111_320.0, SA[1])  # 80 m north
    stats = DiffStats()
    result = diff_candidates([_gsa("13-14-140", legacy="140", legacy_point=far)],
                             existing=[_pin("140", SA)], stats=stats)
    assert result.rekeys == []
    assert [cc.candidate.source_external_id for cc in result.inserts] == ["13-14-140"]
    assert [row.source_external_id for row in result.orphans] == ["140"]
    assert result.rekey_too_far == 1 and stats.rekey_too_far == 1


def test_user_corrected_pin_is_rekeyed_and_flagged() -> None:
    result = diff_candidates([_gsa("13-14-140", legacy="140")],
                             existing=[_pin("140", user_modified=True)], stats=DiffStats())
    assert [r.user_modified for r in result.rekeys] == [True]
    assert result.skips == [] and result.updates == []


def test_a_new_id_match_wins_over_a_legacy_match() -> None:
    existing = [_pin("13-14-140", pin_id="already-rekeyed"), _pin("140", pin_id="legacy")]
    result = diff_candidates([_gsa("13-14-140", legacy="140")], existing=existing, stats=DiffStats())
    assert [cc.candidate.source_external_id for cc in result.updates] == ["13-14-140"]
    assert result.rekeys == []
    assert [row.id for row in result.orphans] == ["legacy"]


def test_a_second_run_is_update_only() -> None:
    cands = [_gsa("13-14-140", legacy="140"), _gsa("47-00-200", legacy="200", legacy_point=LUBBOCK)]
    first = diff_candidates(cands, existing=[_pin("140", SA), _pin("200", LUBBOCK)], stats=DiffStats())
    assert len(first.rekeys) == 2
    rekeyed = [_pin(r.new_external_id, pin_id=r.pin_id,
                    at=(r.classified.candidate.latitude, r.classified.candidate.longitude))
               for r in first.rekeys]
    second = diff_candidates(cands, existing=rekeyed, stats=DiffStats())
    assert len(second.updates) == 2
    assert second.rekeys == [] and second.inserts == [] and second.orphans == []


def test_partial_apply_rerun_resolves_without_duplicates() -> None:
    # The apply crashed after re-keying 140 but before 200: one pin carries its
    # new id, the other still its legacy id.
    cands = [_gsa("13-14-140", legacy="140"), _gsa("47-00-200", legacy="200", legacy_point=LUBBOCK)]
    existing = [_pin("13-14-140", SA, pin_id="pin-140"), _pin("200", LUBBOCK)]
    result = diff_candidates(cands, existing=existing, stats=DiffStats())
    assert [cc.candidate.source_external_id for cc in result.updates] == ["13-14-140"]
    assert [r.new_external_id for r in result.rekeys] == ["47-00-200"]
    assert result.inserts == [] and result.orphans == []


def test_closest_candidate_wins_regardless_of_yield_order() -> None:
    # Two candidates share legacy id "140", both within REKEY_MAX_M of the
    # pin. The farther one (~30 m) is yielded first and must not steal the
    # pin from the nearer one (~5 m) that comes second.
    farther = (SA[0] + 30 / DEG_LAT_M, SA[1])
    nearer = (SA[0] + 5 / DEG_LAT_M, SA[1])
    far_cand = _gsa("14-10-140", legacy="140", legacy_point=farther)
    near_cand = _gsa("13-14-140", legacy="140", legacy_point=nearer)
    stats = DiffStats()
    result = diff_candidates([far_cand, near_cand], existing=[_pin("140", SA)], stats=stats)
    assert [r.new_external_id for r in result.rekeys] == ["13-14-140"]
    assert [cc.candidate.source_external_id for cc in result.inserts] == ["14-10-140"]
    assert result.rekey_too_far == 0 and stats.rekey_too_far == 0


def test_rekey_boundary_at_rekey_max_m() -> None:
    # Offset latitude by a precise number of metres via DEG_LAT_M, with a
    # margin either side of REKEY_MAX_M so float error can't flip the result.
    just_inside = (SA[0] + (REKEY_MAX_M - 0.1) / DEG_LAT_M, SA[1])
    inside_stats = DiffStats()
    inside = diff_candidates(
        [_gsa("13-14-140", legacy="140", legacy_point=just_inside)],
        existing=[_pin("140", SA)], stats=inside_stats,
    )
    assert [r.new_external_id for r in inside.rekeys] == ["13-14-140"]
    assert inside.inserts == [] and inside.orphans == []
    assert inside.rekey_too_far == 0 and inside_stats.rekey_too_far == 0

    just_outside = (SA[0] + (REKEY_MAX_M + 0.1) / DEG_LAT_M, SA[1])
    outside_stats = DiffStats()
    outside = diff_candidates(
        [_gsa("13-14-140", legacy="140", legacy_point=just_outside)],
        existing=[_pin("140", SA)], stats=outside_stats,
    )
    assert outside.rekeys == []
    assert [cc.candidate.source_external_id for cc in outside.inserts] == ["13-14-140"]
    assert [row.source_external_id for row in outside.orphans] == ["140"]
    assert outside.rekey_too_far == 1 and outside_stats.rekey_too_far == 1


def test_orphans_come_only_from_in_scope_pins() -> None:
    tx, fl = _pin("TX-GONE"), _pin("FL-GONE", (25.77, -80.19))
    result = diff_candidates([], existing=[tx, fl], in_scope=[tx], stats=DiffStats())
    assert [row.source_external_id for row in result.orphans] == ["TX-GONE"]

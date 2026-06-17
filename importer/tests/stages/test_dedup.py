from datetime import date

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.dedup import _matches, _meters_between, dedup
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow


def test_meters_between_is_zero_for_same_point():
    assert _meters_between(30.0, -97.0, 30.0, -97.0) == 0.0


def test_meters_between_approximates_one_degree_lat():
    # ~111 km per degree latitude.
    m = _meters_between(30.0, -97.0, 31.0, -97.0)
    assert 110_000 < m < 112_000


def test_matches_true_when_close_and_similar_name():
    assert _matches("Travis County Courthouse", 30.2672, -97.7431,
                    "Travis County Court House", 30.2673, -97.7432) is True


def test_matches_false_when_far_apart():
    assert _matches("Travis County Courthouse", 30.2672, -97.7431,
                    "Travis County Courthouse", 31.0, -97.7431) is False


def test_matches_false_when_names_differ():
    assert _matches("Federal Building", 30.2672, -97.7431,
                    "City Animal Shelter", 30.2673, -97.7432) is False


def test_matches_is_case_insensitive():
    # Real cross-source collision: GSA emits UPPERCASE names, HIFLD mixed-case.
    # token_set_ratio is case-sensitive without normalization, so these must be
    # lowercased before comparison or cross-source dedup silently misses.
    assert _matches("UNITED STATES COURTHOUSE", 30.2672, -97.7431,
                    "United States Courthouse", 30.2673, -97.7432) is True


def _cell(category: RestrictionTag) -> StateLawCell:
    return StateLawCell(
        state="TX", category=category, default_status="NO_GUN",
        confidence="high", citation="x", last_verified_date=date(2026, 5, 31),
    )


def _cc(source: str, eid: str, name: str, lat: float, lng: float,
        category: RestrictionTag = RestrictionTag.FEDERAL_PROPERTY) -> ClassifiedCandidate:
    return ClassifiedCandidate(
        candidate=Candidate(
            source=source, source_external_id=eid, source_dataset_version="v",
            name=name, latitude=lat, longitude=lng,
            coord_quality=CoordQuality.PRECISE, category=category, state="TX",
        ),
        cell=_cell(category),
    )


def test_dedup_keeps_higher_priority_source():
    gsa = _cc("gsa", "g1", "US Courthouse Austin", 30.2672, -97.7431)
    courts = _cc("hifld_courts", "c1", "US Court House Austin", 30.2673, -97.7432,
                 category=RestrictionTag.STATE_LOCAL_GOVT)
    result = dedup([courts, gsa], existing_user_pins=[])
    assert [cc.candidate.source for cc in result.survivors] == ["gsa"]
    assert result.drops_by_pair[("gsa", "hifld_courts")] == 1


def test_dedup_keeps_both_when_far_apart():
    a = _cc("gsa", "g1", "Federal Building", 30.2672, -97.7431)
    b = _cc("hifld_military", "m1", "Fort Hood", 31.13, -97.78)
    result = dedup([a, b], existing_user_pins=[])
    assert len(result.survivors) == 2
    assert result.dropped_total == 0


def test_dedup_drops_candidate_matching_user_pin():
    cand = _cc("gsa", "g1", "Travis County Courthouse", 30.2672, -97.7431)
    user = ExistingPinRow(
        id="u1", source="user", source_external_id=None,
        name="Travis County Courthouse", latitude=30.2673, longitude=-97.7432,
        status=2, restriction_tag="STATE_LOCAL_GOVT", user_modified=True,
        source_dataset_version=None,
    )
    result = dedup([cand], existing_user_pins=[user])
    assert result.survivors == []
    assert result.drops_by_pair[("user", "gsa")] == 1


def test_dedup_drops_within_source_duplicate_external_id():
    a = _cc("gsa", "dup", "Federal Building", 30.2672, -97.7431)
    b = _cc("gsa", "dup", "Federal Building", 40.0, -100.0)
    result = dedup([a, b], existing_user_pins=[])
    assert len(result.survivors) == 1
    assert result.within_source_dups == 1


def test_dedup_equal_tier_tiebreak_is_deterministic():
    courts = _cc("hifld_courts", "c1", "Joint Base Courthouse", 30.2672, -97.7431,
                 category=RestrictionTag.STATE_LOCAL_GOVT)
    military = _cc("hifld_military", "m1", "Joint Base Court House", 30.2673, -97.7432)
    survivors_a = {cc.candidate.source for cc in dedup([courts, military], existing_user_pins=[]).survivors}
    survivors_b = {cc.candidate.source for cc in dedup([military, courts], existing_user_pins=[]).survivors}
    assert survivors_a == survivors_b
    assert len(survivors_a) == 1


def test_dedup_osm_loses_to_higher_priority_source():
    # Same point + matching names; gsa (priority 4) outranks osm (priority 6).
    gsa = _cc("gsa", "g1", "Veterans Hall", 30.2672, -97.7431)
    osm = _cc("osm", "node/9", "Veterans Hall", 30.2673, -97.7432)
    result = dedup([gsa, osm], existing_user_pins=[])
    assert [cc.candidate.source for cc in result.survivors] == ["gsa"]
    assert result.drops_by_pair[("gsa", "osm")] == 1

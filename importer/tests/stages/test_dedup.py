from datetime import date

from importer.candidate import Candidate, CoordQuality
from importer.restriction_tag import RestrictionTag
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.dedup import _matches, _meters_between, dedup
from importer.state_laws import StateLawCell
from importer.supabase_client import ExistingPinRow, SuppressionRow


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


DFC = "Denver Federal Center"


def _gsa(eid, lat=39.7200, lng=-105.1200, override=None):
    cc = _cc("gsa", eid, DFC, lat, lng)
    return cc.model_copy(update={"candidate": cc.candidate.model_copy(
        update={"confidence_override": override})})


def _eids(result):
    return [s.candidate.source_external_id for s in result.survivors]


def test_an_equal_priority_match_keeps_the_key_already_in_the_database():
    a, b = _gsa("47-00-A"), _gsa("47-00-B", lat=39.7201)
    assert _eids(dedup([a, b], existing_user_pins=[])) == ["47-00-A"]
    assert _eids(dedup([a, b], existing_user_pins=[],
                       existing_keys={("gsa", "47-00-B")})) == ["47-00-B"]


def test_stickiness_never_beats_source_priority():
    faa = _cc("faa", "DEN", DFC, 39.7200, -105.1200, category=RestrictionTag.AIRPORT_SECURE)
    gsa = _gsa("47-00-A", lat=39.7201)
    result = dedup([gsa, faa], existing_user_pins=[], existing_keys={("gsa", "47-00-A")})
    assert [s.candidate.source for s in result.survivors] == ["faa"]


def test_a_cluster_pin_takes_the_highest_confidence_in_either_order():
    office = _gsa("47-00-A", override="medium")   # existing key: survives
    court = _gsa("47-00-B", lat=39.7201)           # high
    for order in ([office, court], [court, office]):
        (pin,) = dedup(order, existing_user_pins=[],
                       existing_keys={("gsa", "47-00-A")}).survivors
        assert pin.candidate.source_external_id == "47-00-A"
        assert pin.confidence == "high"


def test_absorbed_rows_pass_their_confidence_through_a_chain():
    # A-B and B-C are about 90 m apart, A-C about 180 m (beyond the 100 m match
    # radius), so C's confidence can only reach A through B.
    a = _gsa("47-00-A", 39.72000, -105.12000, override="medium")
    b = _gsa("47-00-B", 39.72081, -105.12000, override="medium")
    c = _gsa("47-00-C", 39.72162, -105.12000)   # high
    (pin,) = dedup([c, b, a], existing_user_pins=[]).survivors
    assert pin.candidate.source_external_id == "47-00-A"
    assert pin.confidence == "high"


def test_cluster_confidence_ignores_other_sources():
    gsa = _gsa("47-00-A", override="medium")
    mil = _cc("hifld_military", "MIL-1", DFC, 39.7201, -105.1200)   # high, lower priority
    (pin,) = dedup([gsa, mil], existing_user_pins=[]).survivors
    assert (pin.candidate.source, pin.confidence) == ("gsa", "medium")


def test_cluster_confidence_never_exceeds_the_survivors_cell():
    medium_cell = _cell(RestrictionTag.FEDERAL_PROPERTY).model_copy(update={"confidence": "medium"})
    a = _gsa("47-00-A").model_copy(update={"cell": medium_cell})
    b = _gsa("47-00-B", lat=39.7201)   # high cell
    (pin,) = dedup([a, b], existing_user_pins=[]).survivors
    assert (pin.candidate.source_external_id, pin.confidence) == ("47-00-A", "medium")


# --- do-not-import list (suppressions) ---------------------------------------

def _sup(source="gsa", eid="A-B-1", name="Office — Tampa, FL", lat=27.95, lng=-82.46):
    return SuppressionRow(source=source, source_external_id=eid, name=name,
                          latitude=lat, longitude=lng)


_OFFICE = "Office — Tampa, FL"
_M90 = 0.00081  # ~90 m of latitude


def test_suppression_drops_candidate_with_the_entry_key():
    cand = _cc("gsa", "A-B-1", "Whatever", 40.0, -100.0)
    result = dedup([cand], existing_user_pins=[], suppressions=[_sup()])
    assert result.survivors == []
    assert result.suppressed_by_source == {"gsa": 1}


def test_suppression_drops_same_source_neighbour_matching_the_entry():
    cand = _cc("gsa", "A-B-2", _OFFICE, 27.95 + 0.00036, -82.46)  # ~40 m
    result = dedup([cand], existing_user_pins=[], suppressions=[_sup()])
    assert result.survivors == []
    assert result.suppressed_by_source == {"gsa": 1}


def test_suppression_keeps_other_sources_at_the_same_spot():
    cand = _cc("faa", "F1", _OFFICE, 27.95, -82.46)
    result = dedup([cand], existing_user_pins=[], suppressions=[_sup()])
    assert [cc.candidate.source_external_id for cc in result.survivors] == ["F1"]
    assert result.suppressed_by_source == {}


def test_suppression_never_drops_a_candidate_that_already_has_a_pin():
    cand = _cc("gsa", "A-B-2", _OFFICE, 27.95 + 0.00036, -82.46)
    result = dedup([cand], existing_user_pins=[], suppressions=[_sup()],
                   existing_keys={("gsa", "A-B-2")})
    assert len(result.survivors) == 1
    assert result.suppressed_by_source == {}


def test_suppression_without_coordinates_matches_by_key_only():
    entry = _sup(name=None, lat=None, lng=None)
    near = _cc("gsa", "A-B-2", _OFFICE, 27.95 + 0.00009, -82.46)  # ~10 m
    assert len(dedup([near], existing_user_pins=[], suppressions=[entry]).survivors) == 1
    same = _cc("gsa", "A-B-1", _OFFICE, 27.95, -82.46)
    assert dedup([same], existing_user_pins=[], suppressions=[entry]).survivors == []


def test_suppression_does_not_chain_through_neighbours():
    a = _cc("gsa", "A", _OFFICE, 27.95 + _M90, -82.46)
    b = _cc("gsa", "B", _OFFICE, 27.95 + 2 * _M90, -82.46)
    result = dedup([a, b], existing_user_pins=[], suppressions=[_sup()])
    assert [cc.candidate.source_external_id for cc in result.survivors] == ["B"]
    assert result.suppressed_by_source == {"gsa": 1}


def test_suppression_runs_before_user_pin_and_cross_source_steps():
    cand = _cc("gsa", "A-B-1", _OFFICE, 27.95, -82.46)
    user = ExistingPinRow(
        id="u", source="user", source_external_id=None, name=_OFFICE,
        latitude=27.95, longitude=-82.46, status=2, restriction_tag=None,
        user_modified=False, source_dataset_version=None)
    result = dedup([cand], existing_user_pins=[user], suppressions=[_sup()])
    assert result.suppressed_by_source == {"gsa": 1}
    assert result.dropped_total == 0
    assert ("user", "gsa") not in result.drops_by_pair


def test_suppression_never_drops_a_candidate_whose_legacy_key_has_a_pin():
    cand = _cc("gsa", "A-B-2", _OFFICE, 27.95 + 0.00036, -82.46)
    cand = cand.model_copy(update={"candidate": cand.candidate.model_copy(
        update={"legacy_external_id": "OLD-KEY"})})
    result = dedup([cand], existing_user_pins=[], suppressions=[_sup()],
                   existing_keys={("gsa", "OLD-KEY")})
    assert len(result.survivors) == 1
    assert result.suppressed_by_source == {}

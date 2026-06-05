"""Cross-source + within-source dedup (spec §4 step 4).

Two records match when they are within MATCH_RADIUS_M AND
rapidfuzz.token_set_ratio(name_a, name_b) >= NAME_RATIO_THRESHOLD. On a match the
lower-priority record is dropped. user-created pins are highest priority and are
never dropped; a candidate matching a user pin is dropped.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from rapidfuzz import fuzz
from shapely.geometry import Point
from shapely.strtree import STRtree

from importer.stages.apply_state_law import ClassifiedCandidate
from importer.supabase_client import ExistingPinRow

# Highest priority = lowest number = wins a match. HIFLD sub-sources share a tier.
SOURCE_PRIORITY: dict[str, int] = {
    "user": 0,
    "nces": 1,
    "ipeds": 2,
    "faa": 3,
    "gsa": 4,
    "hifld_courts": 5,
    "hifld_hospitals": 5,
    "hifld_military": 5,
    "osm": 6,
}

MATCH_RADIUS_M = 100.0
NAME_RATIO_THRESHOLD = 70.0
_DEG_LAT_M = 111_320.0  # meters per degree of latitude


def _priority(source: str) -> int:
    return SOURCE_PRIORITY.get(source, 99)


def _meters_between(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Equirectangular approximation — adequate at the 100 m scale in CONUS."""
    mean_lat = math.radians((lat1 + lat2) / 2.0)
    dx = (lng2 - lng1) * _DEG_LAT_M * math.cos(mean_lat)
    dy = (lat2 - lat1) * _DEG_LAT_M
    return math.hypot(dx, dy)


def _matches(
    name_a: str, lat_a: float, lng_a: float,
    name_b: str, lat_b: float, lng_b: float,
) -> bool:
    if _meters_between(lat_a, lng_a, lat_b, lng_b) > MATCH_RADIUS_M:
        return False
    # Normalize case before fuzzy comparison: GSA emits UPPERCASE names while
    # HIFLD sources are mixed-case, so without this cross-source matches (e.g.
    # "UNITED STATES COURTHOUSE" vs "United States Courthouse") score ~20 and
    # silently miss, defeating the GSA-wins-courthouse dedup.
    return fuzz.token_set_ratio(
        name_a, name_b, processor=str.lower
    ) >= NAME_RATIO_THRESHOLD


@dataclass
class DedupResult:
    """Result of cross-source dedup.

    dropped_total counts cross-source drops (user-pin + cross-candidate) only.
    Total records removed = dropped_total + within_source_dups.
    """

    survivors: list[ClassifiedCandidate]
    dropped_total: int = 0
    within_source_dups: int = 0
    # (winner_source, loser_source) -> count
    drops_by_pair: dict[tuple[str, str], int] = field(default_factory=dict)


def _record_drop(result: DedupResult, winner: str, loser: str) -> None:
    result.dropped_total += 1
    key = (winner, loser)
    result.drops_by_pair[key] = result.drops_by_pair.get(key, 0) + 1


def dedup(
    classified: list[ClassifiedCandidate],
    *,
    existing_user_pins: list[ExistingPinRow],
) -> DedupResult:
    result = DedupResult(survivors=[])

    # 1. Within-source dedup on (source, external_id). First occurrence wins.
    seen_keys: set[tuple[str, str]] = set()
    unique: list[ClassifiedCandidate] = []
    for cc in classified:
        key = (cc.candidate.source, cc.candidate.source_external_id)
        if key in seen_keys:
            result.within_source_dups += 1
            continue
        seen_keys.add(key)
        unique.append(cc)

    if not unique:
        return result

    # 2. Suppress candidates that collide with an existing user pin.
    survivors_stage2: list[ClassifiedCandidate] = []
    if existing_user_pins:
        user_geoms = [Point(p.longitude, p.latitude) for p in existing_user_pins]
        user_tree = STRtree(user_geoms)
        radius_deg = (MATCH_RADIUS_M / _DEG_LAT_M) * 2.0  # generous bbox pre-filter (safe past 49 N in lng)
        for cc in unique:
            cand = cc.candidate
            cg = Point(cand.longitude, cand.latitude)
            hit = False
            for j in user_tree.query(cg.buffer(radius_deg)):
                up = existing_user_pins[int(j)]
                if _matches(cand.name, cand.latitude, cand.longitude,
                            up.name, up.latitude, up.longitude):
                    _record_drop(result, "user", cand.source)
                    hit = True
                    break
            if not hit:
                survivors_stage2.append(cc)
    else:
        survivors_stage2 = unique

    if not survivors_stage2:
        return result

    # 3. Cross-candidate resolution via one STRtree over all remaining points.
    geoms = [Point(cc.candidate.longitude, cc.candidate.latitude) for cc in survivors_stage2]
    tree = STRtree(geoms)
    radius_deg = (MATCH_RADIUS_M / _DEG_LAT_M) * 2.0  # generous bbox pre-filter (safe past 49 N in lng)
    dropped = [False] * len(survivors_stage2)

    for i, cc in enumerate(survivors_stage2):
        if dropped[i]:
            continue
        a = cc.candidate
        for j_raw in tree.query(geoms[i].buffer(radius_deg)):
            j = int(j_raw)
            if j == i or dropped[j]:
                continue
            b = survivors_stage2[j].candidate
            if not _matches(a.name, a.latitude, a.longitude, b.name, b.latitude, b.longitude):
                continue
            pi, pj = _priority(a.source), _priority(b.source)
            if pi < pj:        # a wins
                dropped[j] = True
                _record_drop(result, a.source, b.source)
            elif pj < pi:      # b wins
                dropped[i] = True
                _record_drop(result, b.source, a.source)
                break
            else:              # same tier — deterministic tiebreak on (source, eid)
                key_a = (a.source, a.source_external_id)
                key_b = (b.source, b.source_external_id)
                if key_a <= key_b:
                    dropped[j] = True
                    _record_drop(result, a.source, b.source)
                else:
                    dropped[i] = True
                    _record_drop(result, b.source, a.source)
                    break

    result.survivors = [cc for k, cc in enumerate(survivors_stage2) if not dropped[k]]
    return result

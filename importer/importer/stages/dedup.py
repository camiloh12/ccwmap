"""Cross-source + within-source dedup (spec §4 step 4).

Two records match when they are within MATCH_RADIUS_M AND
rapidfuzz.token_set_ratio(name_a, name_b) >= NAME_RATIO_THRESHOLD. On a match the
lower-priority record is dropped. user-created pins are highest priority and are
never dropped; a candidate matching a user pin is dropped.

Two rules decide the rest:
- On an equal-priority match, the record whose (source, source_external_id) is
  already in the database wins (so a re-run keeps existing pins' keys), then
  the existing (source, external_id) order.
- A survivor takes the highest confidence of the same-source rows it absorbed
  (transitively, through chains), never above its own cell's confidence.
"""

from __future__ import annotations

from collections.abc import Collection, Sequence
from dataclasses import dataclass, field

from rapidfuzz import fuzz
from shapely.geometry import Point
from shapely.strtree import STRtree

from importer.geo.distance import DEG_LAT_M as _DEG_LAT_M
from importer.geo.distance import meters_between as _meters_between
from importer.stages.apply_state_law import CONFIDENCE_RANK, ClassifiedCandidate
from importer.supabase_client import ExistingPinRow, SuppressionRow

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


def _priority(source: str) -> int:
    return SOURCE_PRIORITY.get(source, 99)


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
    # Candidates dropped by the do-not-import list, by their source.
    suppressed_by_source: dict[str, int] = field(default_factory=dict)


def _record_drop(result: DedupResult, winner: str, loser: str) -> None:
    result.dropped_total += 1
    key = (winner, loser)
    result.drops_by_pair[key] = result.drops_by_pair.get(key, 0) + 1


def _suppresses(entry: SuppressionRow, cand) -> bool:
    if entry.source_external_id == cand.source_external_id:
        return True
    if entry.latitude is None or entry.longitude is None or not entry.name:
        return False
    return _matches(entry.name, entry.latitude, entry.longitude,
                    cand.name, cand.latitude, cand.longitude)


def dedup(
    classified: list[ClassifiedCandidate],
    *,
    existing_user_pins: list[ExistingPinRow],
    existing_keys: Collection[tuple[str, str]] = frozenset(),
    suppressions: Sequence[SuppressionRow] = (),
) -> DedupResult:
    result = DedupResult(survivors=[])
    existing_keys = frozenset(existing_keys)

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

    # 1b. Drop candidates on the do-not-import list: the entry's own key, or a
    # same-source neighbour matching the entry's name and spot (the source
    # re-keyed the record). Direct neighbours only, so it never chains, and a
    # candidate whose key already has a pin is never dropped here.
    if suppressions:
        by_source: dict[str, list[SuppressionRow]] = {}
        for entry in suppressions:
            by_source.setdefault(entry.source, []).append(entry)
        kept: list[ClassifiedCandidate] = []
        for cc in unique:
            cand = cc.candidate
            key = (cand.source, cand.source_external_id)
            entries = by_source.get(cand.source, ())
            if key not in existing_keys and any(
                _suppresses(e, cand) for e in entries
            ):
                result.suppressed_by_source[cand.source] = (
                    result.suppressed_by_source.get(cand.source, 0) + 1
                )
                continue
            kept.append(cc)
        unique = kept

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
    # absorbed[w] = every row that lost to w, directly or through a chain.
    absorbed: list[list[ClassifiedCandidate]] = [[] for _ in survivors_stage2]

    def _absorb(winner: int, loser: int) -> None:
        absorbed[winner] += [survivors_stage2[loser], *absorbed[loser]]

    def _rank(c) -> tuple[bool, str, str]:
        # Same tier: the key already in the database wins, then (source, eid).
        return ((c.source, c.source_external_id) not in existing_keys,
                c.source, c.source_external_id)

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
            if pi < pj or (pi == pj and _rank(a) <= _rank(b)):   # a wins
                dropped[j] = True
                _absorb(i, j)
                _record_drop(result, a.source, b.source)
            else:              # b wins
                dropped[i] = True
                _absorb(j, i)
                _record_drop(result, b.source, a.source)
                break

    for k, cc in enumerate(survivors_stage2):
        if dropped[k]:
            continue
        source = cc.candidate.source
        members = [cc] + [m for m in absorbed[k] if m.candidate.source == source]
        best = min(max(CONFIDENCE_RANK[m.confidence] for m in members),
                   CONFIDENCE_RANK[cc.cell.confidence])
        if best != CONFIDENCE_RANK[cc.confidence]:
            override = (None if best == CONFIDENCE_RANK[cc.cell.confidence]
                        else next(n for n, r in CONFIDENCE_RANK.items() if r == best))
            cc = cc.model_copy(update={"candidate": cc.candidate.model_copy(
                update={"confidence_override": override})})
        result.survivors.append(cc)
    return result

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
    return fuzz.token_set_ratio(name_a, name_b) >= NAME_RATIO_THRESHOLD


@dataclass
class DedupResult:
    survivors: list[ClassifiedCandidate]
    dropped_total: int = 0
    within_source_dups: int = 0
    # (winner_source, loser_source) -> count
    drops_by_pair: dict[tuple[str, str], int] = field(default_factory=dict)


def _record_drop(result: DedupResult, winner: str, loser: str) -> None:
    result.dropped_total += 1
    key = (winner, loser)
    result.drops_by_pair[key] = result.drops_by_pair.get(key, 0) + 1


# ---------------------------------------------------------------------------
# Pass-through stub — replaced by Task 2 with the real spatial+name dedup.
# ---------------------------------------------------------------------------
from collections.abc import Iterable, Iterator
from typing import Any


def dedup(
    candidates: Iterable[Any],
    *,
    existing_user_pins: list[Any],
) -> Iterator[Any]:
    """Phase 3 pass-through.  Task 2 replaces this with the real dedup."""
    yield from candidates

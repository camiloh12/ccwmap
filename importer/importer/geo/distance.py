"""Short-range distances in metres, for the importer's CONUS-scale checks
(dedup matching, re-key matching, MIRTA site points)."""

from __future__ import annotations

import math

DEG_LAT_M = 111_320.0  # metres per degree of latitude


def meters_between(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Equirectangular approximation: well under 1% error at the sub-kilometre
    distances the importer compares."""
    mean_lat = math.radians((lat1 + lat2) / 2.0)
    dx = (lng2 - lng1) * DEG_LAT_M * math.cos(mean_lat)
    dy = (lat2 - lat1) * DEG_LAT_M
    return math.hypot(dx, dy)

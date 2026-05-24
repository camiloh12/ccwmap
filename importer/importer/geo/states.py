"""Resolve a lat/lng to its USPS two-letter state code via point-in-polygon."""

from __future__ import annotations

import json
from pathlib import Path

from shapely.geometry import Point, shape
from shapely.strtree import STRtree


class StateLocator:
    """In-memory STRtree over US state polygons keyed by USPS code."""

    def __init__(self, geometries: list, codes: list[str]) -> None:
        assert len(geometries) == len(codes)
        self._tree = STRtree(geometries)
        self._geometries = geometries
        self._codes = codes

    def state_for(self, lat: float, lng: float) -> str | None:
        pt = Point(lng, lat)  # shapely is (x=lng, y=lat)
        # STRtree.query returns positional indices into the original list.
        for idx in self._tree.query(pt):
            if self._geometries[idx].covers(pt):
                return self._codes[idx]
        return None


def load_state_locator(path: Path) -> StateLocator:
    raw = json.loads(path.read_text(encoding="utf-8"))
    features = raw.get("features", [])
    geometries: list = []
    codes: list[str] = []
    for f in features:
        codes.append(f["properties"]["STUSPS"])
        geometries.append(shape(f["geometry"]))
    return StateLocator(geometries, codes)

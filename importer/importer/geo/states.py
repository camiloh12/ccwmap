"""Resolve a lat/lng to its USPS two-letter state code via point-in-polygon."""

from __future__ import annotations

import json
from pathlib import Path

from shapely.geometry import Point, shape
from shapely.strtree import STRtree

# The 50 states plus DC. Territories are excluded on purpose: they have no
# state-law cells and lie outside the app's US bounding box.
US_STATES_AND_DC = frozenset(
    "AL AK AZ AR CA CO CT DE DC FL GA HI ID IL IN IA KS KY LA ME MD MA MI MN MS "
    "MO MT NE NV NH NJ NM NY NC ND OH OK OR PA RI SC SD TN TX UT VT VA WA WV WI WY".split()
)

# What the importer accepts for --states: Alaska and Hawaii are outside the app's
# continental-US bounding box, so pins there could never be shown or created.
CONTIGUOUS_STATES_AND_DC = US_STATES_AND_DC - {"AK", "HI"}


class StateLocator:
    """In-memory STRtree over US state polygons keyed by USPS code."""

    def __init__(self, geometries: list, codes: list[str]) -> None:
        if len(geometries) != len(codes):
            raise ValueError(
                f"geometries and codes must be the same length "
                f"({len(geometries)} vs {len(codes)})"
            )
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

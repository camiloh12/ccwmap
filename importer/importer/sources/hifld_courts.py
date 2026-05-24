"""HIFLD Courthouses -> Candidate stream.

Source: https://hifld-geoplatform.opendata.arcgis.com/datasets/courthouses
Format: GeoJSON, ~3 MB nationally, ~5k features.
License: Public domain (DHS / HIFLD Open).
"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source


# The URL is captured at pre-flight and pinned here. If HIFLD republishes under
# a new UUID, update this constant in the same PR that refreshes the fixture.
HIFLD_COURTHOUSES_URL = (
    "https://opendata.arcgis.com/api/v3/datasets/"
    "REPLACE-WITH-HIFLD-DATASET-UUID_0/downloads/data"
    "?format=geojson&spatialRefId=4326"
)


class HifldCourthousesSource(Source):
    SOURCE_NAME: ClassVar[str] = "hifld_courts"

    def __init__(
        self,
        *,
        cache_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = HIFLD_COURTHOUSES_URL,
    ) -> None:
        self._cache_path = cache_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        if self._cache_path.exists() and not refetch:
            return
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=60.0, follow_redirects=True) as client:
            r = client.get(self._url)
            r.raise_for_status()
            self._cache_path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        raw = json.loads(self._cache_path.read_text(encoding="utf-8"))
        for feature in raw.get("features", []):
            geom = feature.get("geometry") or {}
            props = feature.get("properties") or {}

            coords = geom.get("coordinates")
            if geom.get("type") != "Point" or not coords or len(coords) < 2:
                self.last_skip_counts["missing_geometry"] += 1
                continue
            lng, lat = float(coords[0]), float(coords[1])

            state = self._locator.state_for(lat, lng)
            if state is None:
                self.last_skip_counts["state_pip_miss"] += 1
                continue
            if state_filter is not None and state not in state_filter:
                self.last_skip_counts["filtered_out"] += 1
                continue

            external_id = self._external_id(props)
            name = (props.get("NAME") or props.get("name") or "").strip()
            if not name:
                self.last_skip_counts["missing_name"] += 1
                continue

            yield Candidate(
                source=self.SOURCE_NAME,
                source_external_id=external_id,
                source_dataset_version=self._version,
                name=name,
                latitude=lat,
                longitude=lng,
                coord_quality=CoordQuality.PRECISE,
                category=RestrictionTag.STATE_LOCAL_GOVT,
                state=state,
                extra={
                    "loemins": props.get("LOEMINS"),
                    "address": props.get("ADDRESS"),
                    "city": props.get("CITY"),
                },
            )

    @staticmethod
    def _external_id(props: dict) -> str:
        for key in ("GFID", "GLOBALID", "OBJECTID", "FID"):
            v = props.get(key)
            if v not in (None, ""):
                return str(v)
        raise ValueError(f"HIFLD courthouse row has no stable ID: {props!r}")

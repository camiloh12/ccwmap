"""HIFLD Courthouses -> Candidate stream.

Source: Courthouses dataset on the HIFLD/GeoPlatform ArcGIS Hub — layer 3 of the
USGS NGDA "Structures_Landmarks_v1" feature service.
  https://hub.arcgis.com/datasets/462b08b0811c4a77aa09afc36c4f4b73_3
Format: GeoJSON, ~2.8 MB nationally, a few thousand Point features.
License: Public domain (US Gov / USGS NGDA).

Field note (verified 2026-05-25): this NGDA-sourced dataset exposes GLOBALID,
OBJECTID, NAME, ADDRESS, CITY, STATE, PERMANENT_IDENTIFIER. It does NOT carry the
classic HIFLD GFID or LOEMINS fields — `_external_id` falls back to GLOBALID
(a stable GUID), and `extra["loemins"]` is therefore None. Phase 3's federal-vs-
state/local split cannot rely on LOEMINS for this dataset version.
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


# ArcGIS Hub download API for the Courthouses layer (item 462b08b0...4b73,
# layer 3). redirect=true is REQUIRED: the endpoint 302-redirects to a freshly
# generated, time-limited (SAS-signed) blob, which our follow_redirects client
# then streams. With redirect=false the endpoint returns a tiny JSON status
# object instead of the GeoJSON, so fetch() would cache garbage. The signed blob
# URLs expire (~1h) and must never be hard-pinned — only this stable hub URL is.
# If HIFLD republishes under a new item/layer, update this constant in the same
# PR that refreshes the fixture. Also recorded in data/sources/.hifld_courts_url.txt.
HIFLD_COURTHOUSES_URL = (
    "https://hub.arcgis.com/api/download/v1/items/"
    "462b08b0811c4a77aa09afc36c4f4b73/geojson"
    "?redirect=true&layers=3&spatialRefId=4326"
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
        """Yield one Candidate per upstream record; respect state_filter when set.

        Side effect: resets and populates `self.last_skip_counts`. Callers must
        fully exhaust the iterator (e.g. via `list(...)`) before reading the
        counts — partial iteration leaves a half-populated Counter.
        """
        self.last_skip_counts = Counter()
        # HIFLD courthouses is ~3 MB; loaded whole intentionally. If this pattern is
        # copy-pasted for larger sources (NCES schools ~20 MB), consider streaming.
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
            if external_id is None:
                self.last_skip_counts["missing_external_id"] += 1
                continue
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
                    "loemins": props.get("LOEMINS"),  # HIFLD: Level of Government (minimum)
                    "address": props.get("ADDRESS"),
                    "city": props.get("CITY"),
                },
            )

    @staticmethod
    def _external_id(props: dict) -> str | None:
        for key in ("GFID", "GLOBALID", "OBJECTID", "FID"):
            v = props.get(key)
            if v not in (None, ""):
                return str(v)
        return None

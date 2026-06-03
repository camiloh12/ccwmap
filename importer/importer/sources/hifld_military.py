"""HIFLD Military Installations -> Candidate stream.

Source: Military Installations boundary dataset on the HIFLD/GeoPlatform ArcGIS
Hub. Format: GeoJSON, Polygon/MultiPolygon features (installation boundaries).
License: Public domain (DHS HIFLD Open).

Unlike hifld_courts (Point features), installations are areas: we emit the
shapely centroid with coord_quality=BUILDING_POLYGON. Category is
FEDERAL_PROPERTY (18 USC 930 via the US FEDERAL_PROPERTY state-law cell, whose
source_filter includes hifld_military).

Pre-flight: confirm the live Hub item/layer + GUID field and refresh the fixture
in the same PR. The signed blob URL expires (~1h) and must never be hard-pinned —
only the stable hub URL belongs in config.yaml.
"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx
from shapely.geometry import shape

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source


class HifldMilitarySource(Source):
    SOURCE_NAME: ClassVar[str] = "hifld_military"

    def __init__(
        self,
        *,
        cache_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        if self._cache_path.exists() and not refetch:
            return
        if not self._url:
            raise RuntimeError(
                "hifld_military url not configured; set sources.hifld_military.url in config.yaml"
            )
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=120.0, follow_redirects=True) as client:
            r = client.get(self._url)
            r.raise_for_status()
            self._cache_path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        """Yield one Candidate per installation polygon; respect state_filter when set.

        Polygon/MultiPolygon features are reduced to their shapely centroid.
        Side effect: resets and populates `self.last_skip_counts`. Callers must
        fully exhaust the iterator (e.g. via `list(...)`) before reading the
        counts — partial iteration leaves a half-populated Counter.
        """
        self.last_skip_counts = Counter()
        raw = json.loads(self._cache_path.read_text(encoding="utf-8"))
        for feature in raw.get("features", []):
            geom = feature.get("geometry")
            props = feature.get("properties") or {}

            if not geom or geom.get("type") not in ("Polygon", "MultiPolygon"):
                self.last_skip_counts["missing_geometry"] += 1
                continue

            centroid = shape(geom).centroid
            lat, lng = float(centroid.y), float(centroid.x)

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

            name = (props.get("siteName") or props.get("NAME") or props.get("name") or "").strip()
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
                coord_quality=CoordQuality.BUILDING_POLYGON,
                category=RestrictionTag.FEDERAL_PROPERTY,
                state=state,
                extra={"component": props.get("component")},
            )

    @staticmethod
    def _external_id(props: dict) -> str | None:
        for key in ("GLOBALID", "OBJECTID", "FID"):
            v = props.get(key)
            if v not in (None, ""):
                return str(v)
        return None

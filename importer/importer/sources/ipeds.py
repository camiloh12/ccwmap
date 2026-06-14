"""IPEDS colleges/universities -> Candidate stream.

Source: IPEDS HD ("Directory information") CSV — one per survey year with UNITID
(stable id), INSTNM, STABBR (state), LATITUDE/LONGITUD, CYACTIVE (1 = active).
https://nces.ed.gov/ipeds/ — License: public domain (US Gov / NCES).
Category: COLLEGE_UNIVERSITY. Native coordinates, so every Candidate is PRECISE.

Only FL has a COLLEGE_UNIVERSITY state-law cell; TX and PA college candidates are
emitted here and then dropped downstream by apply_state_law (no matching cell),
surfacing as expected "missing cell" report noise — see docs/importer/OMISSIONS.md
(TX campus-carry; PA institution-policy).
"""

from __future__ import annotations

import csv
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source


class IpedsSource(Source):
    SOURCE_NAME: ClassVar[str] = "ipeds"

    _COL_ID = "UNITID"
    _COL_NAME = "INSTNM"
    _COL_STATE = "STABBR"  # 2-letter USPS
    _COL_LAT = "LATITUDE"
    _COL_LON = "LONGITUD"
    _COL_ACTIVE = "CYACTIVE"  # 1 = active in current year

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
            raise RuntimeError("ipeds url not configured; set sources.ipeds.url in config.yaml")
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=120.0, follow_redirects=True) as client:
            r = client.get(self._url)
            r.raise_for_status()
            self._cache_path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        with open(self._cache_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                eid = (row.get(self._COL_ID) or "").strip()
                if not eid:
                    self.last_skip_counts["missing_external_id"] += 1
                    continue
                name = (row.get(self._COL_NAME) or "").strip()
                if not name:
                    self.last_skip_counts["missing_name"] += 1
                    continue
                state = (row.get(self._COL_STATE) or "").strip().upper()
                if state_filter is not None and state not in state_filter:
                    self.last_skip_counts["filtered_out"] += 1
                    continue
                if (row.get(self._COL_ACTIVE) or "").strip() != "1":
                    self.last_skip_counts["not_operating"] += 1
                    continue
                lat, lng = self._coords(row)
                if lat is None or lng is None:
                    self.last_skip_counts["missing_coords"] += 1
                    continue
                if self._locator.state_for(lat, lng) != state:
                    self.last_skip_counts["coord_state_mismatch"] += 1
                    continue
                yield Candidate(
                    source=self.SOURCE_NAME,
                    source_external_id=eid,
                    source_dataset_version=self._version,
                    name=name,
                    latitude=lat,
                    longitude=lng,
                    coord_quality=CoordQuality.PRECISE,
                    category=RestrictionTag.COLLEGE_UNIVERSITY,
                    state=state,
                    extra={},
                )

    @staticmethod
    def _coords(row: dict) -> tuple[float | None, float | None]:
        lat_s = (row.get(IpedsSource._COL_LAT) or "").strip()
        lng_s = (row.get(IpedsSource._COL_LON) or "").strip()
        if not lat_s or not lng_s:
            return None, None
        try:
            return float(lat_s), float(lng_s)
        except ValueError:
            return None, None

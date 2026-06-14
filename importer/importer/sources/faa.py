"""FAA commercial-service airports -> Candidate stream.

The AIRPORT_SECURE prohibition attaches to the TSA sterile/secured area past a
screening checkpoint, which exists only at airports with passenger screening. This
source emits the COMMERCIAL-SERVICE subset only, not all NPIAS.

Two companion CSVs (both public domain, US Gov), joined on the airport location id:
  - Commercial-service list: LOCID, STATE, AIRPORT_NAME, SERVICE_LEVEL — the
    authoritative set of commercial-service airports.
    https://www.faa.gov/airports/planning_capacity/npias/
  - FAA NASR APT data: ARPT_ID, LAT_DECIMAL, LONG_DECIMAL — coordinate source
    (airport reference point).
    https://www.faa.gov/air_traffic/flight_info/aeronav/aero_data/NASR_Subscription/

Category: AIRPORT_SECURE (federal-uniform US cell). The pin name uses the
mixed-case commercial-service list; coordinates use the NASR ARP. PRECISE.
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


class FaaSource(Source):
    SOURCE_NAME: ClassVar[str] = "faa"

    # Commercial-service list columns.
    _CS_COL_ID = "LOCID"
    _CS_COL_STATE = "STATE"
    _CS_COL_NAME = "AIRPORT_NAME"
    _CS_COL_SERVICE = "SERVICE_LEVEL"
    # Service levels with scheduled passenger service (hence TSA screening).
    # Compared case-insensitively.
    _COMMERCIAL_SERVICE: ClassVar[frozenset[str]] = frozenset({
        "primary",
        "nonprimary commercial service",
        "commercial service",
    })
    # NASR APT columns.
    _APT_COL_ID = "ARPT_ID"
    _APT_COL_LAT = "LAT_DECIMAL"
    _APT_COL_LON = "LONG_DECIMAL"

    def __init__(
        self,
        *,
        cache_path: Path,
        nasr_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = "",
        nasr_url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._nasr_path = nasr_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self._nasr_url = nasr_url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        for path, src_url in (
            (self._cache_path, self._url),
            (self._nasr_path, self._nasr_url),
        ):
            if path.exists() and not refetch:
                continue
            if not src_url:
                raise RuntimeError(
                    "faa url(s) not configured; set sources.faa.url and "
                    "sources.faa.nasr_url in config.yaml"
                )
            path.parent.mkdir(parents=True, exist_ok=True)
            with httpx.Client(timeout=120.0, follow_redirects=True) as client:
                r = client.get(src_url)
                r.raise_for_status()
                path.write_bytes(r.content)

    def _load_nasr_coords(self) -> dict[str, tuple[float, float]]:
        out: dict[str, tuple[float, float]] = {}
        with open(self._nasr_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                locid = (row.get(self._APT_COL_ID) or "").strip().upper()
                lat_s = (row.get(self._APT_COL_LAT) or "").strip()
                lng_s = (row.get(self._APT_COL_LON) or "").strip()
                if not locid or not lat_s or not lng_s:
                    continue
                try:
                    out[locid] = (float(lat_s), float(lng_s))
                except ValueError:
                    continue
        return out

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        coords = self._load_nasr_coords()
        with open(self._cache_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                service = (row.get(self._CS_COL_SERVICE) or "").strip().lower()
                if service not in self._COMMERCIAL_SERVICE:
                    self.last_skip_counts["not_commercial_service"] += 1
                    continue
                state = (row.get(self._CS_COL_STATE) or "").strip().upper()
                if state_filter is not None and state not in state_filter:
                    self.last_skip_counts["filtered_out"] += 1
                    continue
                locid = (row.get(self._CS_COL_ID) or "").strip().upper()
                if not locid:
                    self.last_skip_counts["missing_external_id"] += 1
                    continue
                name = (row.get(self._CS_COL_NAME) or "").strip()
                if not name:
                    self.last_skip_counts["missing_name"] += 1
                    continue
                hit = coords.get(locid)
                if hit is None:
                    self.last_skip_counts["missing_coords"] += 1
                    continue
                lat, lng = hit
                if self._locator.state_for(lat, lng) != state:
                    self.last_skip_counts["coord_state_mismatch"] += 1
                    continue
                yield Candidate(
                    source=self.SOURCE_NAME,
                    source_external_id=locid,
                    source_dataset_version=self._version,
                    name=name,
                    latitude=lat,
                    longitude=lng,
                    coord_quality=CoordQuality.PRECISE,
                    category=RestrictionTag.AIRPORT_SECURE,
                    state=state,
                    extra={},
                )

"""FAA commercial-service airports -> Candidate stream.

The AIRPORT_SECURE prohibition attaches to the TSA sterile/secured area past a
screening checkpoint, which exists only at airports with passenger screening. This
source emits the COMMERCIAL-SERVICE subset only, not all NPIAS / public-use
airports.

Two companion files (both public domain, US Gov), joined on the airport location id
(verified against the CY2023 / 28-day NASR releases):
  - Commercial-service list: the FAA "CY Enplanements at All Commercial Service
    Airports" workbook — a bare .xlsx with columns Rank, RO, ST, Locid, City,
    "Airport Name", "S/L" (service level: P=primary, CS=nonprimary commercial
    service), Hub, enplanements. Every row is a commercial-service airport by
    definition (>=2,500 annual enplanements). `fetch()` flattens it to CSV.
    https://www.faa.gov/airports/planning_capacity/passenger_allcargo_stats/passenger
  - FAA NASR APT data: APT_BASE.csv (inside the 28-day "<date>_APT_CSV.zip"),
    columns ARPT_ID, LAT_DECIMAL, LONG_DECIMAL (signed decimal degrees) — the
    coordinate source (airport reference point). `fetch()` extracts that member.
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

from importer.candidate import Candidate, CoordQuality
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources import _archive
from importer.sources.base import Source


class FaaSource(Source):
    SOURCE_NAME: ClassVar[str] = "faa"

    # Commercial-service list columns (FAA CY enplanements workbook).
    _CS_COL_ID = "Locid"
    _CS_COL_STATE = "ST"
    _CS_COL_NAME = "Airport Name"
    _CS_COL_SERVICE = "S/L"
    # S/L codes with scheduled passenger service (hence TSA screening): P=primary,
    # CS=nonprimary commercial service. Compared case-insensitively.
    _COMMERCIAL_SERVICE: ClassVar[frozenset[str]] = frozenset({"p", "cs"})
    # NASR APT_BASE columns.
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
        # Commercial-service list: a bare .xlsx — flatten to CSV at cache_path.
        if refetch or not self._cache_path.exists():
            if not self._url:
                raise RuntimeError(
                    "faa url not configured; set sources.faa.url in config.yaml"
                )
            self._cache_path.parent.mkdir(parents=True, exist_ok=True)
            _archive.xlsx_bytes_to_csv(_archive.download(self._url), self._cache_path)
        # NASR coordinates: APT_BASE.csv inside the 28-day APT_CSV.zip bundle.
        if refetch or not self._nasr_path.exists():
            if not self._nasr_url:
                raise RuntimeError(
                    "faa nasr_url not configured; set sources.faa.nasr_url in config.yaml"
                )
            self._nasr_path.parent.mkdir(parents=True, exist_ok=True)
            _archive.extract_member(
                _archive.download(self._nasr_url),
                self._nasr_path,
                match=lambda n: n.upper() == "APT_BASE.CSV",
            )

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

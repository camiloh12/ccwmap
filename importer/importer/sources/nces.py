"""NCES public K-12 schools -> Candidate stream.

Two companion files joined on NCESSCH (verified against the SY 2024-25 release):
  - EDGE public-school geocode file (NCESSCH, NAME, STATE, LAT, LON, address) —
    the coordinate-bearing driver. https://nces.ed.gov/programs/edge/
    Ships as a .zip containing an .xlsx; `fetch()` extracts the sheet and writes
    it to `cache_path` as a plain CSV that `iter_candidates` reads.
  - CCD directory file (NCESSCH, SY_STATUS) — operational-status lookup so closed
    campuses are not pinned. https://nces.ed.gov/ccd/
    Ships inside the CCD nonfiscal "preliminary directory" bundle .zip as
    ccd_sch_029_<years>_w_*.csv (utf-8-sig); `fetch()` extracts that member to
    `directory_path`.
License: public domain (US Gov / NCES). Category: SCHOOL_K12 (cells exist for
TX/FL/PA). Native coordinates, so every Candidate is PRECISE.

Live SY 2024-25 confirms the constants below: EDGE header carries NCESSCH/NAME/
STATE/LAT/LON; CCD uses SY_STATUS with numeric codes (1=Open, 2=Closed, 3=New,
8=Reopened, plus 4-7 inactive). If NCES renames a column, update the constant AND
the frozen fixture together.
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


class NcesSource(Source):
    SOURCE_NAME: ClassVar[str] = "nces"

    # EDGE geocode columns.
    _COL_ID = "NCESSCH"
    _COL_NAME = "NAME"
    _COL_STATE = "STATE"  # 2-letter USPS
    _COL_LAT = "LAT"
    _COL_LON = "LON"
    # CCD directory columns.
    _DIR_COL_ID = "NCESSCH"
    _DIR_COL_STATUS = "SY_STATUS"
    # CCD status codes that mean operating: 1=Open, 3=New, 8=Reopened.
    _OPERATIONAL_STATUSES: ClassVar[frozenset[str]] = frozenset({"1", "3", "8"})

    def __init__(
        self,
        *,
        cache_path: Path,
        directory_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = "",
        directory_url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._directory_path = directory_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self._directory_url = directory_url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        # EDGE geocode: a .zip wrapping an .xlsx — flatten the sheet to a plain
        # CSV at cache_path so iter_candidates() can read it unchanged.
        if refetch or not self._cache_path.exists():
            if not self._url:
                raise RuntimeError(
                    "nces url not configured; set sources.nces.url in config.yaml"
                )
            self._cache_path.parent.mkdir(parents=True, exist_ok=True)
            _archive.xlsx_in_zip_to_csv(_archive.download(self._url), self._cache_path)
        # CCD directory: the school directory CSV (ccd_sch_029_*.csv) lives inside
        # the nonfiscal "preliminary directory" bundle .zip — extract that member.
        if refetch or not self._directory_path.exists():
            if not self._directory_url:
                raise RuntimeError(
                    "nces directory_url not configured; set "
                    "sources.nces.directory_url in config.yaml"
                )
            self._directory_path.parent.mkdir(parents=True, exist_ok=True)
            _archive.extract_member(
                _archive.download(self._directory_url),
                self._directory_path,
                match=lambda n: n.lower().startswith("ccd_sch_029")
                and n.lower().endswith(".csv"),
            )

    def _load_status_map(self) -> dict[str, str]:
        out: dict[str, str] = {}
        with open(self._directory_path, encoding="utf-8-sig", newline="") as f:
            for row in csv.DictReader(f):
                eid = (row.get(self._DIR_COL_ID) or "").strip()
                if eid:
                    out[eid] = (row.get(self._DIR_COL_STATUS) or "").strip()
        return out

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        status_map = self._load_status_map()
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
                lat, lng = self._coords(row)
                if lat is None or lng is None:
                    self.last_skip_counts["missing_coords"] += 1
                    continue
                if self._locator.state_for(lat, lng) != state:
                    self.last_skip_counts["coord_state_mismatch"] += 1
                    continue
                status = status_map.get(eid)
                if status is not None and status not in self._OPERATIONAL_STATUSES:
                    self.last_skip_counts["not_operational"] += 1
                    continue
                yield Candidate(
                    source=self.SOURCE_NAME,
                    source_external_id=eid,
                    source_dataset_version=self._version,
                    name=name,
                    latitude=lat,
                    longitude=lng,
                    coord_quality=CoordQuality.PRECISE,
                    category=RestrictionTag.SCHOOL_K12,
                    state=state,
                    extra={},
                )

    @staticmethod
    def _coords(row: dict) -> tuple[float | None, float | None]:
        lat_s = (row.get(NcesSource._COL_LAT) or "").strip()
        lng_s = (row.get(NcesSource._COL_LON) or "").strip()
        if not lat_s or not lng_s:
            return None, None
        try:
            return float(lat_s), float(lng_s)
        except ValueError:
            return None, None

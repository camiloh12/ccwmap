"""GSA FRPP (Federal Real Property Profile) -> Candidate stream.

Source: GSA FRPP public dataset (CSV). Federal owned/leased real property.
License: Public domain (US Gov). Category: FEDERAL_PROPERTY (18 USC 930 via the
US FEDERAL_PROPERTY state-law cell, source_filter includes gsa).

Coordinates: rows may carry Latitude/Longitude; when present we trust them
(coord_quality=PRECISE), otherwise we geocode the street address via the US
Census batch geocoder (coord_quality=ADDRESS_CENTROID). State filtering happens
on the dataset's own State column BEFORE geocoding so only pilot rows hit the API.

Pre-flight: confirm the live CSV URL + column headers; refresh _COL_* + fixture
in the same PR.
"""

from __future__ import annotations

import csv
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar, Protocol

import httpx

from importer.candidate import Candidate, CoordQuality
from importer.geo.census_geocode import AddressRecord
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source

_COL_ID = "Real Property Unique Identifier"
_COL_TYPE = "Real Property Type"
_COL_STREET = "Street Address"
_COL_CITY = "City"
_COL_STATE = "State"
_COL_ZIP = "Zip Code"
_COL_LAT = "Latitude"
_COL_LNG = "Longitude"
_COL_NAME = "Real Property Asset Name"

# 18 USC 930 attaches to federal *facilities* (buildings/structures), not land.
_EXCLUDED_TYPES = {"land"}


class _Geocoder(Protocol):
    def geocode(self, records: list[AddressRecord]) -> dict[str, tuple[float, float]]: ...


class GsaSource(Source):
    SOURCE_NAME: ClassVar[str] = "gsa"

    def __init__(
        self,
        *,
        cache_path: Path,
        dataset_version: str,
        geocoder: _Geocoder,
        url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._version = dataset_version
        self._geocoder = geocoder
        self._url = url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        if self._cache_path.exists() and not refetch:
            return
        if not self._url:
            raise RuntimeError("gsa url not configured; set sources.gsa.url in config.yaml")
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=120.0, follow_redirects=True) as client:
            r = client.get(self._url)
            r.raise_for_status()
            self._cache_path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        rows = list(csv.DictReader(self._cache_path.read_text(encoding="utf-8").splitlines()))

        kept: list[dict] = []
        to_geocode: list[AddressRecord] = []
        for row in rows:
            state = (row.get(_COL_STATE) or "").strip().upper()
            if state_filter is not None and state not in state_filter:
                self.last_skip_counts["filtered_out"] += 1
                continue
            if (row.get(_COL_TYPE) or "").strip().lower() in _EXCLUDED_TYPES:
                self.last_skip_counts["not_federal_facility"] += 1
                continue
            eid = (row.get(_COL_ID) or "").strip()
            if not eid:
                self.last_skip_counts["missing_external_id"] += 1
                continue
            name = (row.get(_COL_NAME) or "").strip()
            if not name:
                self.last_skip_counts["missing_name"] += 1
                continue
            street = (row.get(_COL_STREET) or "").strip()
            lat, lng = self._existing_coords(row)
            if lat is None and not street:
                self.last_skip_counts["missing_address"] += 1
                continue
            row["_state"] = state
            row["_eid"] = eid
            row["_name"] = name
            row["_lat"] = lat
            row["_lng"] = lng
            kept.append(row)
            if lat is None:
                to_geocode.append(AddressRecord(
                    id=eid, street=street,
                    city=(row.get(_COL_CITY) or "").strip(),
                    state=state, zip=(row.get(_COL_ZIP) or "").strip(),
                ))

        geocoded = self._geocoder.geocode(to_geocode) if to_geocode else {}

        for row in kept:
            lat, lng = row["_lat"], row["_lng"]
            quality = CoordQuality.PRECISE
            if lat is None:
                hit = geocoded.get(row["_eid"])
                if hit is None:
                    self.last_skip_counts["geocode_miss"] += 1
                    continue
                lat, lng = hit
                quality = CoordQuality.ADDRESS_CENTROID
            yield Candidate(
                source=self.SOURCE_NAME,
                source_external_id=row["_eid"],
                source_dataset_version=self._version,
                name=row["_name"],
                latitude=lat,
                longitude=lng,
                coord_quality=quality,
                category=RestrictionTag.FEDERAL_PROPERTY,
                state=row["_state"],
                extra={},
            )

    @staticmethod
    def _existing_coords(row: dict) -> tuple[float | None, float | None]:
        lat_s = (row.get(_COL_LAT) or "").strip()
        lng_s = (row.get(_COL_LNG) or "").strip()
        if not lat_s or not lng_s:
            return None, None
        try:
            return float(lat_s), float(lng_s)
        except ValueError:
            return None, None

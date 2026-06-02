"""US Census batch geocoder (public domain, no API key, US-only).

Endpoint: POST /geocoder/locations/addressbatch with an uploaded CSV of
id,street,city,state,zip. Returns CSV rows; matched rows carry "lng,lat".
Successful matches are cached to disk keyed by a hash of the normalized address
so re-runs skip already-geocoded rows.
"""

from __future__ import annotations

import csv
import hashlib
import io
import json
from dataclasses import dataclass
from pathlib import Path

import httpx

CENSUS_BATCH_URL = "https://geocoding.geo.census.gov/geocoder/locations/addressbatch"
_BENCHMARK = "Public_AR_Current"


@dataclass(frozen=True)
class AddressRecord:
    id: str
    street: str
    city: str
    state: str
    zip: str

    def cache_key(self) -> str:
        norm = f"{self.street}|{self.city}|{self.state}|{self.zip}".upper().strip()
        return hashlib.sha1(norm.encode("utf-8")).hexdigest()


class CensusGeocoder:
    def __init__(self, *, cache_path: Path, timeout: float = 120.0) -> None:
        self._cache_path = cache_path
        self._timeout = timeout
        self._cache: dict[str, list[float]] = {}
        if cache_path.exists():
            self._cache = json.loads(cache_path.read_text(encoding="utf-8"))

    def geocode(self, records: list[AddressRecord]) -> dict[str, tuple[float, float]]:
        """Return {record.id: (lat, lng)} for matched records only."""
        out: dict[str, tuple[float, float]] = {}
        uncached: list[AddressRecord] = []
        for rec in records:
            cached = self._cache.get(rec.cache_key())
            if cached is not None:
                out[rec.id] = (cached[0], cached[1])
            else:
                uncached.append(rec)

        if uncached:
            fetched = self._fetch_batch(uncached)
            by_key = {rec.id: rec.cache_key() for rec in uncached}
            for rid, (lat, lng) in fetched.items():
                out[rid] = (lat, lng)
                self._cache[by_key[rid]] = [lat, lng]
            self._flush_cache()
        return out

    def _fetch_batch(self, records: list[AddressRecord]) -> dict[str, tuple[float, float]]:
        buf = io.StringIO()
        writer = csv.writer(buf)
        for rec in records:
            writer.writerow([rec.id, rec.street, rec.city, rec.state, rec.zip])
        files = {"addressFile": ("addresses.csv", buf.getvalue(), "text/csv")}
        data = {"benchmark": _BENCHMARK}
        with httpx.Client(timeout=self._timeout) as client:
            r = client.post(CENSUS_BATCH_URL, data=data, files=files)
            r.raise_for_status()
            return self._parse(r.text)

    @staticmethod
    def _parse(text: str) -> dict[str, tuple[float, float]]:
        out: dict[str, tuple[float, float]] = {}
        for row in csv.reader(io.StringIO(text)):
            if len(row) < 6 or row[2] != "Match":
                continue
            rid = row[0]
            lng_str, lat_str = row[5].split(",")
            out[rid] = (float(lat_str), float(lng_str))
        return out

    def _flush_cache(self) -> None:
        self._cache_path.parent.mkdir(parents=True, exist_ok=True)
        self._cache_path.write_text(json.dumps(self._cache), encoding="utf-8")

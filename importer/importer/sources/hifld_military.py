"""HIFLD Military Installations (MIRTA) -> Candidate stream.

Source: Military Installations, Ranges, and Training Areas (MIRTA) DoD Sites,
from the USACE-owned MIRTA feature service (item owner `usace_crrel_als`); the
legacy HIFLD Open hub was deactivated 2025-08-26. License: public domain (US
Gov / DoD DISDI). Two layers, each fetched with one GeoJSON GET
(maxRecordCount 1000 exceeds both counts: 825 boundaries, 737 points, 2026-09):
  - layer 1, "DoD Sites - Boundaries" (`url`): a Polygon/MultiPolygon per record.
  - layer 0, "DoD Sites - Point" (`points_url`): one DoD-placed point per site.

Identity. A site's key is its `SDSID` when that is a real GUID (not blank, not
all zeros). 202 boundaries have no SDSID and 3 share the all-zero one; those
are keyed "{STATE}:{SITENAME}" (upper-cased, whitespace collapsed). Records
that share a key are one installation split across records; their geometries
are merged into one candidate.

Position. The pin goes on the site's DoD point (matched by SDSID, else by
state + name) when that point lies within SITE_POINT_MAX_M of the boundary;
otherwise on a point inside the boundary's largest part. The area-weighted
centroid used before 2026-10 fell outside the base for 77 multi-part sites.

Closed sites (SITEOPERATIONALSTATUS 'clsd') are skipped. Caretaker, excess
and semi-active sites stay: DoD still holds them.

Legacy identity. Before 2026-10 the id fell back to MIRTALOCATIONSIDPK, which
is a single space on every record, so all blank-SDSID sites collapsed into one
pin. A candidate whose key differs from that old id carries the old id and the
old centroid (of its first record in file order, which the old code kept), so
the diff stage can re-key that pin instead of replacing it.

Category is FEDERAL_PROPERTY (18 USC 930 via the US FEDERAL_PROPERTY
state-law cell, whose source_filter includes hifld_military).
"""

from __future__ import annotations

import json
from collections import Counter
from collections.abc import Iterator
from pathlib import Path
from typing import ClassVar

import httpx
from shapely.geometry import Point, shape
from shapely.ops import nearest_points, unary_union

from importer.candidate import Candidate, CoordQuality
from importer.geo.distance import meters_between
from importer.geo.states import StateLocator
from importer.restriction_tag import RestrictionTag
from importer.sources.base import Source

# A DoD site point this close to the boundary counts as on the base: boundary
# digitizing and the point's placement disagree by a few metres at the edge.
SITE_POINT_MAX_M = 50.0

_CLOSED = "clsd"


def _real_sdsid(props: dict) -> str | None:
    """The SDSID when it is a real GUID: not blank and not all zeros."""
    v = str(props.get("SDSID") or "").strip()
    if not v or set(v) <= set("{}-0"):
        return None
    return v


def _site_name(props: dict) -> str:
    return str(
        props.get("SITENAME")
        or props.get("siteName")
        or props.get("NAME")
        or props.get("name")
        or ""
    ).strip()


def _name_key(props: dict) -> str:
    state = str(props.get("STATENAMECODE") or "").strip().upper()
    return f"{state}:{' '.join(_site_name(props).upper().split())}"


def _site_key(props: dict) -> str:
    return _real_sdsid(props) or _name_key(props)


def _legacy_external_id(props: dict) -> str | None:
    """The id the pre-2026-10 code used, kept verbatim for re-keying."""
    for key in ("SDSID", "MIRTALOCATIONSIDPK", "GLOBALID", "OBJECTID", "FID"):
        v = props.get(key)
        if v not in (None, ""):
            return str(v)
    return None


def _load_features(path: Path, what: str) -> list[dict]:
    """Features of a cached layer. A missing file, an ArcGIS error body or an
    empty layer is an error: an empty boundary layer would orphan every
    military pin, and an empty points layer would silently move them all."""
    if not path.exists():
        raise RuntimeError(f"hifld_military {what} file missing: {path}; run fetch()")
    raw = json.loads(path.read_text(encoding="utf-8"))
    features = raw.get("features") if isinstance(raw, dict) else None
    if not features:
        raise RuntimeError(f"hifld_military {what} file has no features: {path}")
    return features


class _SitePoints:
    """DoD site points, looked up by real SDSID, else by state + name."""

    def __init__(self, features: list[dict]) -> None:
        self._by_sdsid: dict[str, Point] = {}
        self._by_name: dict[str, Point] = {}
        for f in features:
            geom = f.get("geometry") or {}
            if geom.get("type") != "Point":
                continue
            props = f.get("properties") or {}
            pt = shape(geom)
            sdsid = _real_sdsid(props)
            if sdsid:
                self._by_sdsid.setdefault(sdsid, pt)
            self._by_name.setdefault(_name_key(props), pt)

    def match(self, props: dict) -> Point | None:
        sdsid = _real_sdsid(props)
        if sdsid and sdsid in self._by_sdsid:
            return self._by_sdsid[sdsid]
        return self._by_name.get(_name_key(props))


def _meters_outside(area, pt: Point) -> float:
    if area.covers(pt):
        return 0.0
    near = nearest_points(area, pt)[0]
    return meters_between(near.y, near.x, pt.y, pt.x)


def _position(area, site_point: Point | None) -> Point:
    """The site point when it is on the base, else a point inside the largest part."""
    if site_point is not None and _meters_outside(area, site_point) <= SITE_POINT_MAX_M:
        return site_point
    parts = [g for g in getattr(area, "geoms", [area]) if g.geom_type == "Polygon"]
    return max(parts, key=lambda g: g.area).representative_point()


class HifldMilitarySource(Source):
    SOURCE_NAME: ClassVar[str] = "hifld_military"

    def __init__(
        self,
        *,
        cache_path: Path,
        points_cache_path: Path,
        state_locator: StateLocator,
        dataset_version: str,
        url: str = "",
        points_url: str = "",
    ) -> None:
        self._cache_path = cache_path
        self._points_cache_path = points_cache_path
        self._locator = state_locator
        self._version = dataset_version
        self._url = url
        self._points_url = points_url
        self.last_skip_counts: Counter[str] = Counter()

    def fetch(self, *, refetch: bool = False) -> None:
        layers = (
            ("url", self._url, self._cache_path),
            ("points_url", self._points_url, self._points_cache_path),
        )
        todo = [(key, url, path) for key, url, path in layers if refetch or not path.exists()]
        for key, url, _ in todo:
            if not url:
                raise RuntimeError(
                    f"hifld_military {key} not configured; set sources.hifld_military.{key} in config.yaml"
                )
        if not todo:
            return
        with httpx.Client(timeout=120.0, follow_redirects=True) as client:
            for _, url, path in todo:
                r = client.get(url)
                r.raise_for_status()
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(r.content)

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        """One Candidate per installation; respect state_filter when set.

        Side effect: resets and populates `self.last_skip_counts`. Callers must
        fully exhaust the iterator (e.g. via `list(...)`) before reading them.
        """
        self.last_skip_counts = Counter()
        features = _load_features(self._cache_path, "boundary")
        points = _SitePoints(_load_features(self._points_cache_path, "site-points"))

        # Insertion order is the file order of each key's first record.
        groups: dict[str, list[dict]] = {}
        for feature in features:
            geom = feature.get("geometry")
            props = feature.get("properties") or {}
            if not geom or geom.get("type") not in ("Polygon", "MultiPolygon"):
                self.last_skip_counts["missing_geometry"] += 1
                continue
            if str(props.get("SITEOPERATIONALSTATUS") or "").strip().lower() == _CLOSED:
                self.last_skip_counts["closed"] += 1
                continue
            if not _site_name(props):
                self.last_skip_counts["missing_name"] += 1
                continue
            groups.setdefault(_site_key(props), []).append(feature)

        for key, members in groups.items():
            first = members[0].get("properties") or {}
            shapes = [shape(m["geometry"]) for m in members]
            pos = _position(unary_union(shapes), points.match(first))
            lat, lng = float(pos.y), float(pos.x)

            state = self._locator.state_for(lat, lng)
            if state is None:
                self.last_skip_counts["state_pip_miss"] += 1
                continue
            if state_filter is not None and state not in state_filter:
                self.last_skip_counts["filtered_out"] += 1
                continue
            if len(members) > 1:
                self.last_skip_counts["merged_records"] += len(members) - 1

            legacy: dict = {}
            old_id = _legacy_external_id(first)
            if old_id is not None and old_id != key:
                old = shapes[0].centroid
                legacy = {
                    "legacy_external_id": old_id,
                    "legacy_point": (float(old.y), float(old.x)),
                }
            yield Candidate(
                source=self.SOURCE_NAME,
                source_external_id=key,
                source_dataset_version=self._version,
                name=_site_name(first),
                latitude=lat,
                longitude=lng,
                coord_quality=CoordQuality.BUILDING_POLYGON,
                category=RestrictionTag.FEDERAL_PROPERTY,
                state=state,
                extra={"component": first.get("SITEREPORTINGCOMPONENT") or first.get("component")},
                **legacy,
            )

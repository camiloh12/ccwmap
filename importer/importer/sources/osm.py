"""OpenStreetMap venues via the Overpass API -> Candidate stream.

Per-state auto-scope: the source asks the state-law table which categories have
an `osm`-filtered cell for each requested state and queries Overpass only for
those. For the pilot (TX/FL/PA) that resolves to BAR_ALCOHOL in TX and FL; PA
generates no query at all. This keeps load off the free, shared Overpass API and
matches OMISSIONS.md (worship/sports/healthcare have no categorical prohibition
in the pilot states, so they are never queried).

License: ODbL (share-alike) — the only pilot source so licensed. The ODbL dump
(stages/odbl_dump.py) publishes the derived columns of source='osm' rows.
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
from importer.state_laws import StateLawTable


class OsmSource(Source):
    SOURCE_NAME: ClassVar[str] = "osm"

    def __init__(
        self,
        *,
        cache_dir: Path,
        state_locator: StateLocator,
        state_laws: StateLawTable,
        states: list[str],
        dataset_version: str,
        area_selector_template: str,
        category_tags: dict[str, list[str]],
        overpass_url: str = "",
        timeout: float = 240.0,
    ) -> None:
        self._cache_dir = cache_dir
        self._locator = state_locator
        self._state_laws = state_laws
        self._states = list(states)
        self._version = dataset_version
        self._area_template = area_selector_template
        self._category_tags = category_tags
        self._overpass_url = overpass_url
        self._timeout = timeout
        self.last_skip_counts: Counter[str] = Counter()
        # Reverse map "amenity=bar" -> BAR_ALCOHOL for classifying returned elements.
        self._tag_to_category: dict[str, RestrictionTag] = {}
        for cat_name, tags in category_tags.items():
            cat = RestrictionTag(cat_name)
            for tag in tags:
                self._tag_to_category[tag] = cat

    def build_query_plan(self, states: list[str]) -> dict[str, list[str]]:
        """state -> ordered union of OSM tag filters to query for that state.

        States with no auto-scoped category (e.g. PA) are omitted entirely.
        """
        plan: dict[str, list[str]] = {}
        for state in states:
            tags: list[str] = []
            for category in sorted(
                self._state_laws.osm_categories_for_state(state), key=lambda c: c.value
            ):
                cat_tags = self._category_tags.get(category.value)
                if not cat_tags:
                    # Auto-scope picked a category we have no Overpass tags for.
                    # Surface it; never silently default.
                    self.last_skip_counts[f"no_tag_map:{category.value}"] += 1
                    continue
                tags.extend(cat_tags)
            if tags:
                plan[state] = tags
        return plan

    def _build_query(self, state: str, tags: list[str]) -> str:
        area = self._area_template.format(state=state)
        clauses = []
        for tag in tags:
            key, _, value = tag.partition("=")
            if value:
                clauses.append(f'  nwr["{key}"="{value}"](area.a);')
            else:
                # Bare key (no "=value") -> Overpass key-existence filter.
                clauses.append(f'  nwr["{key}"](area.a);')
        body = "\n".join(clauses)
        # 180s is the Overpass *server-side* timeout; the httpx client timeout
        # (self._timeout, default 240s) is deliberately higher so a server-side
        # timeout surfaces as an Overpass error before the HTTP client aborts.
        return (
            "[out:json][timeout:180];\n"
            f"area{area}->.a;\n"
            "(\n"
            f"{body}\n"
            ");\n"
            "out center tags;\n"
        )

    def fetch(self, *, refetch: bool = False) -> None:
        plan = self.build_query_plan(self._states)
        if plan and not self._overpass_url:
            raise RuntimeError(
                "osm overpass_url not configured; set sources.osm.overpass_url in config.yaml"
            )
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        with httpx.Client(timeout=self._timeout, follow_redirects=True) as client:
            for state, tags in plan.items():
                dest = self._cache_dir / f"{state}.json"
                if dest.exists() and not refetch:
                    continue
                query = self._build_query(state, tags)
                r = client.post(self._overpass_url, content=query.encode("utf-8"))
                r.raise_for_status()
                dest.write_bytes(r.content)

    def _element_coords(self, el: dict) -> tuple[float, float] | None:
        if "lat" in el and "lon" in el:
            return float(el["lat"]), float(el["lon"])
        center = el.get("center")
        if center and "lat" in center and "lon" in center:
            return float(center["lat"]), float(center["lon"])
        return None

    def _category_for(self, tags: dict) -> RestrictionTag | None:
        for key, value in tags.items():
            cat = self._tag_to_category.get(f"{key}={value}")
            if cat is not None:
                return cat
        return None

    def iter_candidates(self, state_filter: set[str] | None) -> Iterator[Candidate]:
        self.last_skip_counts = Counter()
        states = sorted(state_filter) if state_filter else list(self._states)
        plan = self.build_query_plan(states)
        for state in plan:
            path = self._cache_dir / f"{state}.json"
            if not path.exists():
                self.last_skip_counts["missing_cache"] += 1
                continue
            data = json.loads(path.read_text(encoding="utf-8"))
            for el in data.get("elements", []):
                el_type = el.get("type")
                el_id = el.get("id")
                if el_type not in ("node", "way", "relation") or el_id is None:
                    self.last_skip_counts["malformed_element"] += 1
                    continue
                tags = el.get("tags") or {}
                name = (tags.get("name") or "").strip()
                if not name:
                    self.last_skip_counts["missing_name"] += 1
                    continue
                category = self._category_for(tags)
                if category is None:
                    self.last_skip_counts["no_category_tag"] += 1
                    continue
                coords = self._element_coords(el)
                if coords is None:
                    self.last_skip_counts["missing_coords"] += 1
                    continue
                lat, lng = coords
                if self._locator.state_for(lat, lng) != state:
                    self.last_skip_counts["coord_state_mismatch"] += 1
                    continue
                quality = (
                    CoordQuality.PRECISE
                    if el_type == "node"
                    else CoordQuality.BUILDING_POLYGON
                )
                yield Candidate(
                    source=self.SOURCE_NAME,
                    source_external_id=f"{el_type}/{el_id}",
                    source_dataset_version=self._version,
                    name=name,
                    latitude=lat,
                    longitude=lng,
                    coord_quality=quality,
                    category=category,
                    state=state,
                    extra={},
                )

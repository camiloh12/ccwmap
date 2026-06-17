"""Load and query the maintained state-law lookup table."""

from __future__ import annotations

from datetime import date
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator

from importer.restriction_tag import RestrictionTag


Status = Literal["ALLOWED", "UNCERTAIN", "NO_GUN"]
Confidence = Literal["high", "medium", "low"]


class StateLawCell(BaseModel):
    """One row in `states.yaml`."""

    model_config = ConfigDict(frozen=True)

    state: str = Field(pattern=r"^(US|[A-Z]{2})$")
    category: RestrictionTag
    default_status: Status
    confidence: Confidence
    conditions: list[str] = Field(default_factory=list)
    citation: str
    last_verified_date: date
    source_filter: list[str] | None = None
    notes: str | None = None

    @field_validator("category", mode="before")
    @classmethod
    def _coerce_category(cls, v: str | RestrictionTag) -> RestrictionTag:
        return RestrictionTag(v) if isinstance(v, str) else v


class StateLawTable(BaseModel):
    rows: list[StateLawCell]

    def lookup(self, state: str, category: RestrictionTag) -> StateLawCell | None:
        for row in self.rows:
            if row.state == state and row.category is category:
                return row
        for row in self.rows:
            if row.state == "US" and row.category is category:
                return row
        return None

    def osm_categories_for_state(self, state: str) -> set[RestrictionTag]:
        """Categories whose effective cell for `state` is OSM-filtered.

        Uses the same state->US fallback as lookup(), so a state-specific cell
        shadows the US cell exactly as classification will later resolve it.
        Drives the OSM source's per-state Overpass query plan: we never query a
        (state, category) combination that will not become a pin.
        """
        cats: set[RestrictionTag] = set()
        for category in {row.category for row in self.rows}:
            cell = self.lookup(state, category)
            if cell and cell.source_filter and "osm" in cell.source_filter:
                cats.add(category)
        return cats


def load_state_laws(path: Path) -> StateLawTable:
    raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    if not isinstance(raw, list):
        raise ValueError(f"{path} must be a YAML list of rows; got {type(raw).__name__}")
    rows = [StateLawCell.model_validate(item) for item in raw]
    return StateLawTable(rows=rows)

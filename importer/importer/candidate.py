"""The common intermediate format produced by every source module."""

from __future__ import annotations

from enum import Enum

from pydantic import BaseModel, ConfigDict, Field

from importer.restriction_tag import RestrictionTag


class CoordQuality(str, Enum):
    PRECISE = "precise"
    ADDRESS_CENTROID = "address_centroid"
    BUILDING_POLYGON = "building_polygon"


class Candidate(BaseModel):
    """One pin under consideration, pre-classification.

    Sources emit Candidates with `category` set to their best guess. The
    `apply_state_law` stage then enriches each Candidate with status, citation,
    confidence, and verified_date pulled from the (state, category) row in
    `states.yaml`. Candidates whose (state, category) has no row are dropped
    and surfaced in the dry-run report.
    """

    model_config = ConfigDict(frozen=True)

    source: str
    source_external_id: str
    source_dataset_version: str
    name: str = Field(min_length=1)
    latitude: float = Field(ge=-90.0, le=90.0)
    longitude: float = Field(ge=-180.0, le=180.0)
    coord_quality: CoordQuality
    category: RestrictionTag
    state: str = Field(pattern=r"^[A-Z]{2}$")
    extra: dict = Field(default_factory=dict)

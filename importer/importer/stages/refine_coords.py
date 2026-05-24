"""Coordinate refinement — Phase 2 pass-through.

Phase 4+ replaces this with an Overpass query per (state, category) bbox plus
a per-Candidate nearest-polygon snap. The signature is locked so callers do
not have to change when the implementation lands.
"""

from __future__ import annotations

from collections.abc import Iterable, Iterator

from importer.candidate import Candidate


def refine_coords(candidates: Iterable[Candidate]) -> Iterator[Candidate]:
    yield from candidates

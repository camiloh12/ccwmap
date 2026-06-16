"""Per-candidate normalization: trim, truncate names to the DB constraint."""

from __future__ import annotations

from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field

from importer.candidate import Candidate
from importer.stages._titlecase import smart_title_case

# Mirrors the `CHECK char_length(name) <= 60` constraint on public.pins.name.
PIN_NAME_MAX_LENGTH = 60


@dataclass
class NormalizeStats:
    truncations: int = 0
    # Capped sample of (original, truncated) pairs for the report.
    examples: list[tuple[str, str]] = field(default_factory=list)
    _example_cap: int = 5


def normalize(
    candidates: Iterable[Candidate],
    *,
    stats: NormalizeStats,
) -> Iterator[Candidate]:
    for c in candidates:
        new_name = c.name.strip()
        # Re-case only all-caps source labels (no lowercase letter present);
        # already-mixed-case names (OSM, HIFLD, recomposed GSA) are left as-is.
        if new_name and not any(ch.islower() for ch in new_name):
            new_name = smart_title_case(new_name)
        if len(new_name) > PIN_NAME_MAX_LENGTH:
            truncated = new_name[:PIN_NAME_MAX_LENGTH]
            stats.truncations += 1
            if len(stats.examples) < stats._example_cap:
                stats.examples.append((new_name, truncated))
            new_name = truncated
        yield c.model_copy(update={"name": new_name})

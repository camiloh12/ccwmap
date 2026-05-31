"""Match each Candidate to a StateLawCell, drop those with no match."""

from __future__ import annotations

from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field

from pydantic import BaseModel, ConfigDict

from importer.candidate import Candidate
from importer.state_laws import StateLawCell, StateLawTable


class ClassifiedCandidate(BaseModel):
    """A Candidate plus the StateLawCell that classified it."""

    model_config = ConfigDict(frozen=True)

    candidate: Candidate
    cell: StateLawCell


@dataclass
class ApplyStateLawStats:
    classified: int = 0
    dropped_no_cell: int = 0
    # (state, category_name) pairs that had no row — surface in report.
    missing_cells: set[tuple[str, str]] = field(default_factory=set)


def apply_state_law(
    candidates: Iterable[Candidate],
    *,
    table: StateLawTable,
    stats: ApplyStateLawStats,
) -> Iterator[ClassifiedCandidate]:
    for c in candidates:
        cell = table.lookup(c.state, c.category)
        if cell is None or (cell.source_filter and c.source not in cell.source_filter):
            stats.dropped_no_cell += 1
            stats.missing_cells.add((c.state, c.category.name))
            continue
        stats.classified += 1
        yield ClassifiedCandidate(candidate=c, cell=cell)

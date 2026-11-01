"""Match each Candidate to a StateLawCell, drop those with no match."""

from __future__ import annotations

from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field

from pydantic import BaseModel, ConfigDict, model_validator

from importer.candidate import Candidate
from importer.state_laws import StateLawCell, StateLawTable


CONFIDENCE_RANK: dict[str, int] = {"low": 0, "medium": 1, "high": 2}


class ClassifiedCandidate(BaseModel):
    """A Candidate plus the StateLawCell that classified it."""

    model_config = ConfigDict(frozen=True)

    candidate: Candidate
    cell: StateLawCell

    @property
    def confidence(self) -> str:
        """The override if set, else the cell's. An override may only lower."""
        override = self.candidate.confidence_override
        if override is None:
            return self.cell.confidence
        if CONFIDENCE_RANK[override] > CONFIDENCE_RANK[self.cell.confidence]:
            raise ValueError(
                f"confidence override {override!r} may only lower the cell's "
                f"{self.cell.confidence!r} confidence "
                f"({self.candidate.source}/{self.candidate.source_external_id})"
            )
        return override

    @model_validator(mode="after")
    def _check_override(self) -> "ClassifiedCandidate":
        self.confidence  # raises if the override outranks the cell
        return self


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

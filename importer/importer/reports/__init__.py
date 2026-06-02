"""Report generation for dry-run and apply modes."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from importer.stages.diff import DiffResult


@dataclass
class SourceResult:
    """Per-source counts. `classified` is pre-dedup; diff buckets are post-dedup."""

    source: str
    candidates_fetched: int
    candidates_after_state_filter: int
    classified: int
    dropped_no_cell: int
    missing_cells: list[tuple[str, str]]
    name_truncations: int
    diff: DiffResult
    geocode_matched: int | None = None
    geocode_missed: int | None = None


@dataclass
class DedupReport:
    dropped_total: int = 0
    within_source_dups: int = 0
    drops_by_pair: dict[tuple[str, str], int] = field(default_factory=dict)


@dataclass
class PipelineResult:
    mode: str  # 'dry-run' or 'apply'
    started_at: datetime
    completed_at: datetime | None
    states: list[str]
    sources: list[SourceResult]
    dedup: DedupReport
    errors: list[str] = field(default_factory=list)

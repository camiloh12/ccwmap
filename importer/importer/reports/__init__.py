"""Report generation for dry-run and apply modes."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime

from importer.stages.diff import DiffResult


@dataclass
class PipelineResult:
    """Everything a report needs to render. Produced by importer.pipeline."""

    mode: str  # 'dry-run' or 'apply'
    started_at: datetime
    completed_at: datetime | None
    source: str
    states: list[str]
    candidates_fetched: int
    candidates_after_state_filter: int
    classified: int
    dropped_no_cell: int
    missing_cells: list[tuple[str, str]]
    name_truncations: int
    diff: DiffResult
    errors: list[str] = field(default_factory=list)

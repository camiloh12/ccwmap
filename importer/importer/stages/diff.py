"""Classify each ClassifiedCandidate against the existing Supabase pins table."""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass, field

from pydantic import BaseModel, ConfigDict

from importer.stages.apply_state_law import ClassifiedCandidate
from importer.supabase_client import ExistingPinRow


class DiffResult(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True, frozen=True)

    inserts: list[ClassifiedCandidate]
    updates: list[ClassifiedCandidate]
    skips: list[ClassifiedCandidate]   # user_modified rows we leave alone
    orphans: list[ExistingPinRow]      # in DB, not in current run


@dataclass
class DiffStats:
    inserts: int = 0
    updates: int = 0
    skips: int = 0
    orphans: int = 0


def diff_candidates(
    classified: Iterable[ClassifiedCandidate],
    *,
    existing: list[ExistingPinRow],
    stats: DiffStats,
) -> DiffResult:
    by_eid = {row.source_external_id: row for row in existing if row.source_external_id}
    seen_eids: set[str] = set()

    inserts: list[ClassifiedCandidate] = []
    updates: list[ClassifiedCandidate] = []
    skips: list[ClassifiedCandidate] = []

    for cc in classified:
        eid = cc.candidate.source_external_id
        seen_eids.add(eid)
        existing_row = by_eid.get(eid)
        if existing_row is None:
            inserts.append(cc)
            stats.inserts += 1
        elif existing_row.user_modified:
            skips.append(cc)
            stats.skips += 1
        else:
            updates.append(cc)
            stats.updates += 1

    orphans = [
        row
        for eid, row in by_eid.items()
        if eid not in seen_eids
    ]
    stats.orphans = len(orphans)

    return DiffResult(inserts=inserts, updates=updates, skips=skips, orphans=orphans)

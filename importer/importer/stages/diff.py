"""Classify each ClassifiedCandidate against the source's existing pins.

Pass 1 matches a candidate to the pin carrying its own source_external_id:
an update, or a skip when a user corrected that pin. Pass 2 re-keys pins
whose id scheme changed: a candidate carrying a legacy id takes over the pin
with that id when the pin sits within REKEY_MAX_M of where the old code put
the record. Closest pairs go first, so the order a source yields records in
doesn't decide which record inherits a shared old id. Every other candidate
is an insert. In-scope pins neither pass claimed are orphans: their record
is gone, or lost cross-source dedup.
"""

from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass

from pydantic import BaseModel, ConfigDict, Field

from importer.geo.distance import meters_between
from importer.stages.apply_state_law import ClassifiedCandidate
from importer.supabase_client import ExistingPinRow

# A legacy pin is re-keyed only this close to the record's old position;
# farther means the old id now belongs to a different record.
REKEY_MAX_M = 50.0


class Rekey(BaseModel):
    """An existing pin taking a new source_external_id; its UUID survives."""

    model_config = ConfigDict(frozen=True)

    pin_id: str
    old_external_id: str
    new_external_id: str
    user_modified: bool
    classified: ClassifiedCandidate


class DiffResult(BaseModel):
    model_config = ConfigDict(arbitrary_types_allowed=True, frozen=True)

    inserts: list[ClassifiedCandidate]
    updates: list[ClassifiedCandidate]
    skips: list[ClassifiedCandidate]   # user_modified rows we leave alone
    orphans: list[ExistingPinRow]      # in scope, claimed by no candidate
    rekeys: list[Rekey] = Field(default_factory=list)
    # Legacy pins that had candidates but none within REKEY_MAX_M. Those
    # candidates were inserted, and the old pin is left as an orphan.
    rekey_too_far: int = 0


@dataclass
class DiffStats:
    inserts: int = 0
    updates: int = 0
    skips: int = 0
    orphans: int = 0
    rekeys: int = 0
    rekey_too_far: int = 0


def diff_candidates(
    classified: Iterable[ClassifiedCandidate],
    *,
    existing: list[ExistingPinRow],
    stats: DiffStats,
    in_scope: list[ExistingPinRow] | None = None,
) -> DiffResult:
    """`existing`: every pin of the source. `in_scope`: the pins this run may
    orphan (default: all of `existing`)."""
    by_eid = {row.source_external_id: row for row in existing if row.source_external_id}
    claimed: set[str] = set()
    updates: list[ClassifiedCandidate] = []
    skips: list[ClassifiedCandidate] = []
    pending: list[ClassifiedCandidate] = []

    # Pass 1: the candidate's own id.
    for cc in classified:
        row = by_eid.get(cc.candidate.source_external_id)
        if row is None or row.id in claimed:
            pending.append(cc)
            continue
        claimed.add(row.id)
        (skips if row.user_modified else updates).append(cc)

    # Pass 2: legacy ids, closest candidate-pin pairs first.
    pairs: list[tuple[float, int, ExistingPinRow]] = []
    for i, cc in enumerate(pending):
        c = cc.candidate
        if c.legacy_external_id is None or c.legacy_point is None:
            continue
        row = by_eid.get(c.legacy_external_id)
        if row is None or row.id in claimed:
            continue
        lat, lng = c.legacy_point
        pairs.append((meters_between(lat, lng, row.latitude, row.longitude), i, row))

    matched: dict[int, Rekey] = {}
    for dist, i, row in sorted(pairs, key=lambda p: (p[0], p[1])):
        if dist > REKEY_MAX_M or i in matched or row.id in claimed:
            continue
        claimed.add(row.id)
        cc = pending[i]
        matched[i] = Rekey(
            pin_id=row.id,
            old_external_id=row.source_external_id,
            new_external_id=cc.candidate.source_external_id,
            user_modified=row.user_modified,
            classified=cc,
        )
    too_far = {row.id for _, _, row in pairs if row.id not in claimed}

    rekeys = [matched[i] for i in sorted(matched)]
    inserts = [cc for i, cc in enumerate(pending) if i not in matched]
    scope = existing if in_scope is None else in_scope
    orphans = [row for row in scope if row.id not in claimed]

    stats.inserts = len(inserts)
    stats.updates = len(updates)
    stats.skips = len(skips)
    stats.orphans = len(orphans)
    stats.rekeys = len(rekeys)
    stats.rekey_too_far = len(too_far)
    return DiffResult(
        inserts=inserts, updates=updates, skips=skips, orphans=orphans,
        rekeys=rekeys, rekey_too_far=len(too_far),
    )

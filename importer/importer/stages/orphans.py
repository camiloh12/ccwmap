"""Which orphans an apply deletes, keeps or marks, and the per-source cap.

An orphan is a system pin, inside the run's states, that no record claimed:
the record left the dataset, or lost cross-source dedup. A plain apply marks
orphans (source_orphaned_at). With --delete-orphans it deletes them, except
pins a user corrected, which are kept and marked. Deletions per source are
capped so a truncated download can't wipe a layer.
"""

from __future__ import annotations

from collections.abc import Collection, Iterable
from dataclasses import dataclass, field

from importer.geo.states import StateLocator
from importer.supabase_client import ExistingPinRow

MIN_DELETE_CAP = 50
DELETE_CAP_PCT = 5


class OrphanCapExceeded(RuntimeError):
    """A source would delete more orphans than its cap; nothing was written."""


def default_cap(in_scope_count: int) -> int:
    """max(50, 5% of the source's in-scope pins)."""
    return max(MIN_DELETE_CAP, in_scope_count * DELETE_CAP_PCT // 100)


def scope_to_states(
    rows: Iterable[ExistingPinRow],
    *,
    states: set[str] | None,
    locator: StateLocator | None,
) -> list[ExistingPinRow]:
    """The pins a run may orphan: those inside its states. Pins have no state
    column, so the polygons the sources use decide. A pin outside every
    polygon is never in scope for a state-filtered run."""
    rows = list(rows)
    if states is None or not rows:
        return rows
    if locator is None:
        raise ValueError("a state_locator is required to scope orphans to states")
    return [r for r in rows if locator.state_for(r.latitude, r.longitude) in states]


@dataclass(frozen=True)
class OrphanPlan:
    delete: list[ExistingPinRow] = field(default_factory=list)
    keep: list[ExistingPinRow] = field(default_factory=list)  # user-corrected: marked, never deleted
    mark: list[ExistingPinRow] = field(default_factory=list)
    # Source saw the record but could not use it: marked, never deleted, outside the cap.
    unusable: list[ExistingPinRow] = field(default_factory=list)
    cap: int = MIN_DELETE_CAP

    @property
    def breached(self) -> bool:
        return len(self.delete) > self.cap

    @property
    def marked_count(self) -> int:
        """Pins whose source_orphaned_at the apply sets (import_runs.orphans_marked)."""
        return len(self.keep) + len(self.mark) + len(self.unusable)

    def actions(self) -> list[tuple[ExistingPinRow, str]]:
        return (
            [(r, "delete") for r in self.delete]
            + [(r, "keep") for r in self.keep]
            + [(r, "mark") for r in self.mark]
            + [(r, "unusable_kept") for r in self.unusable]
        )


def plan_orphans(
    orphans: Iterable[ExistingPinRow],
    *,
    in_scope_count: int,
    delete: bool,
    cap: int | None = None,
    unusable_keys: Collection[str] = frozenset(),
) -> OrphanPlan:
    """`delete=False`: mark every orphan. `delete=True`: delete the ones no
    user corrected and keep (mark) the rest. A pin no user corrected whose
    source_external_id is in `unusable_keys` (the source saw the record but
    could not use it) goes to `unusable` instead: marked, never deleted.
    `cap` overrides default_cap()."""
    limit = default_cap(in_scope_count) if cap is None else cap
    kept: list[ExistingPinRow] = []  # user-corrected
    unusable: list[ExistingPinRow] = []
    rest: list[ExistingPinRow] = []
    for o in orphans:
        if o.user_modified:
            kept.append(o)
        elif o.source_external_id in unusable_keys:
            unusable.append(o)
        else:
            rest.append(o)
    if not delete:
        return OrphanPlan(mark=kept + rest, unusable=unusable, cap=limit)
    return OrphanPlan(delete=rest, keep=kept, unusable=unusable, cap=limit)

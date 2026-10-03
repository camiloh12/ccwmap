"""Render a PipelineResult as a JSON sidecar."""

from __future__ import annotations

import json

from importer.reports import PipelineResult


def _source(s) -> dict:
    plan = s.orphan_plan
    actions = {row.id: action for row, action in plan.actions()}
    return {
        "source": s.source,
        "counts": {
            "candidates_fetched": s.candidates_fetched,
            "classified": s.classified,
            "dropped_no_cell": s.dropped_no_cell,
            "name_truncations": s.name_truncations,
            "geocode_matched": s.geocode_matched,
            "geocode_missed": s.geocode_missed,
            "inserts": len(s.diff.inserts),
            "updates": len(s.diff.updates),
            "skips": len(s.diff.skips),
            "rekeys": len(s.diff.rekeys),
            "rekey_too_far": s.diff.rekey_too_far,
            "orphans": len(s.diff.orphans),
            "orphans_deleted": len(plan.delete),
            "orphans_kept_user_corrected": len(plan.keep),
            "orphans_marked": len(plan.mark),
            "orphan_delete_cap": plan.cap,
            "orphan_cap_breached": plan.breached,
        },
        "skip_counts": dict(sorted(s.skip_counts.items())),
        "missing_cells": [list(p) for p in s.missing_cells],
        "rekeys": [
            {
                "pin_id": rk.pin_id,
                "old_external_id": rk.old_external_id,
                "new_external_id": rk.new_external_id,
                "user_modified": rk.user_modified,
            }
            for rk in s.diff.rekeys
        ],
        # Every orphan with what the run did (or, in a dry-run, would do) to it:
        # the audit trail for deletions, which can't be undone.
        "orphans": [
            {
                "id": row.id,
                "source_external_id": row.source_external_id,
                "name": row.name,
                "action": actions.get(row.id),
            }
            for row in s.diff.orphans
        ],
    }


def render_json(r: PipelineResult) -> str:
    payload = {
        "mode": r.mode,
        "states": r.states,
        "started_at": r.started_at.isoformat(),
        "completed_at": r.completed_at.isoformat() if r.completed_at else None,
        "dedup": {
            "dropped_total": r.dedup.dropped_total,
            "within_source_dups": r.dedup.within_source_dups,
            "drops_by_pair": [
                {"winner": w, "loser": l, "count": n}
                for (w, l), n in sorted(r.dedup.drops_by_pair.items())
            ],
        },
        "sources": [_source(s) for s in r.sources],
        "errors": r.errors,
    }
    return json.dumps(payload, indent=2, sort_keys=True)

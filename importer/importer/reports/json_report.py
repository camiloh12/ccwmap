"""Render a PipelineResult as a JSON sidecar."""

from __future__ import annotations

import json

from importer.reports import PipelineResult


def render_json(r: PipelineResult) -> str:
    payload = {
        "mode": r.mode,
        "source": r.source,
        "states": r.states,
        "started_at": r.started_at.isoformat(),
        "completed_at": r.completed_at.isoformat() if r.completed_at else None,
        "counts": {
            "candidates_fetched": r.candidates_fetched,
            "candidates_after_state_filter": r.candidates_after_state_filter,
            "classified": r.classified,
            "dropped_no_cell": r.dropped_no_cell,
            "name_truncations": r.name_truncations,
            "inserts": len(r.diff.inserts),
            "updates": len(r.diff.updates),
            "skips": len(r.diff.skips),
            "orphans": len(r.diff.orphans),
        },
        "missing_cells": [list(p) for p in r.missing_cells],
        "orphans": [
            {"source_external_id": row.source_external_id, "name": row.name}
            for row in r.diff.orphans
        ],
        "errors": r.errors,
    }
    return json.dumps(payload, indent=2, sort_keys=True)

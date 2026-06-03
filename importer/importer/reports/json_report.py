"""Render a PipelineResult as a JSON sidecar."""

from __future__ import annotations

import json

from importer.reports import PipelineResult


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
        "sources": [
            {
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
                    "orphans": len(s.diff.orphans),
                },
                "missing_cells": [list(p) for p in s.missing_cells],
                "orphans": [
                    {"source_external_id": row.source_external_id, "name": row.name}
                    for row in s.diff.orphans
                ],
            }
            for s in r.sources
        ],
        "errors": r.errors,
    }
    return json.dumps(payload, indent=2, sort_keys=True)

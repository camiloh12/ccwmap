"""Render a PipelineResult as a human-readable Markdown report."""

from __future__ import annotations

from importer.reports import PipelineResult


def render_markdown(r: PipelineResult) -> str:
    lines: list[str] = []
    title = "dry-run report" if r.mode == "dry-run" else "apply report"
    lines.append(f"# Importer {title}")
    lines.append("")
    lines.append(f"- Source: **{r.source}**")
    lines.append(f"- States: **{', '.join(r.states)}**")
    lines.append(f"- Started: {r.started_at.isoformat()}")
    if r.completed_at is not None:
        lines.append(f"- Completed: {r.completed_at.isoformat()}")
    lines.append("")

    lines.append("## Counts")
    lines.append("")
    lines.append(f"- Candidates fetched: **{r.candidates_fetched}**")
    lines.append(f"- After state filter: **{r.candidates_after_state_filter}**")
    lines.append(f"- Classified by state-law table: **{r.classified}**")
    lines.append(f"- Dropped (no state-law cell): **{r.dropped_no_cell}**")
    lines.append(f"- Name truncations: **{r.name_truncations}**")
    lines.append(f"- INSERT: **{len(r.diff.inserts)}**")
    lines.append(f"- UPDATE: **{len(r.diff.updates)}**")
    lines.append(f"- SKIP (user-modified): **{len(r.diff.skips)}**")
    lines.append(f"- Orphan: **{len(r.diff.orphans)}**")
    lines.append("")

    if r.missing_cells:
        lines.append("## Needs research")
        lines.append("")
        lines.append("These (state, category) pairs had no row in `data/state_laws/states.yaml` and were dropped. Add cells before the next run if these should be classified.")
        lines.append("")
        for state, category in sorted(r.missing_cells):
            lines.append(f"- ({state}, {category})")
        lines.append("")

    if r.diff.orphans:
        lines.append("## Orphans (in DB, not in current source)")
        lines.append("")
        lines.append("Pins whose `(source, source_external_id)` is no longer in the upstream dataset. They are NOT auto-deleted; review and decide.")
        lines.append("")
        for row in r.diff.orphans[:50]:
            lines.append(f"- `{row.source_external_id}` — {row.name}")
        if len(r.diff.orphans) > 50:
            lines.append(f"- … and {len(r.diff.orphans) - 50} more.")
        lines.append("")

    if r.errors:
        lines.append("## Errors")
        lines.append("")
        for err in r.errors:
            lines.append(f"- {err}")
        lines.append("")

    return "\n".join(lines)

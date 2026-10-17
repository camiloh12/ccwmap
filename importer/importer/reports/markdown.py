"""Render a PipelineResult as a human-readable Markdown report."""

from __future__ import annotations

from importer.reports import PipelineResult, SourceResult


def _source_block(s: SourceResult, *, dry_run: bool) -> list[str]:
    lines = [f"### Source: `{s.source}`", ""]
    lines.append(f"- Candidates fetched: **{s.candidates_fetched}**")
    lines.append(f"- Classified by state-law table: **{s.classified}**")
    lines.append(f"- Dropped (no state-law cell): **{s.dropped_no_cell}**")
    lines.append(f"- Name truncations: **{s.name_truncations}**")
    if s.geocode_matched is not None or s.geocode_missed is not None:
        lines.append(f"- Geocoded (address centroid): **{s.geocode_matched or 0}**")
        lines.append(f"- Geocode misses (dropped): **{s.geocode_missed or 0}**")
    plan = s.orphan_plan
    lines.append(f"- INSERT: **{len(s.diff.inserts)}**")
    lines.append(f"- UPDATE: **{len(s.diff.updates)}**")
    lines.append(f"- Re-key: **{len(s.diff.rekeys)}**")
    if s.diff.rekey_too_far:
        lines.append(
            f"- Re-key too far (inserted; old pin left as an orphan): **{s.diff.rekey_too_far}**"
        )
    lines.append(f"- SKIP (user-modified): **{len(s.diff.skips)}**")
    if dry_run:
        lines.append(
            f"- Orphan: **{len(s.diff.orphans)}**: an apply with `--delete-orphans` would "
            f"delete **{len(plan.delete)}** and keep **{len(plan.keep)}** user-corrected "
            f"(a plain apply marks all of them)"
        )
    else:
        lines.append(
            f"- Orphan: **{len(s.diff.orphans)}** (deleted **{len(plan.delete)}**, "
            f"kept, user-corrected **{len(plan.keep)}**, marked **{len(plan.mark)}**)"
        )
    if plan.breached:
        lines.append(
            f"- **Orphan delete cap breached: {len(plan.delete)} deletions > cap {plan.cap}**"
        )
    if s.skip_counts:
        skipped = ", ".join(f"`{k}` {v}" for k, v in sorted(s.skip_counts.items()))
        lines.append(f"- Skipped at source: {skipped}")
    lines.append("")
    if s.missing_cells:
        lines.append("**Needs research** (no `states.yaml` cell, dropped):")
        for state, category in sorted(s.missing_cells):
            lines.append(f"- ({state}, {category})")
        lines.append("")
    if s.diff.orphans:
        actions = {row.id: action for row, action in plan.actions()}
        lines.append("**Orphans** (system pins in scope that no record claimed):")
        for row in s.diff.orphans[:50]:
            suffix = f" ({actions[row.id]})" if row.id in actions else ""
            lines.append(f"- `{row.source_external_id}` — {row.name}{suffix}")
        if len(s.diff.orphans) > 50:
            lines.append(f"- … and {len(s.diff.orphans) - 50} more (full list in the JSON report).")
        lines.append("")
    return lines


def render_markdown(r: PipelineResult) -> str:
    title = "dry-run report" if r.mode == "dry-run" else "apply report"
    lines = [f"# Importer {title}", ""]
    lines.append(f"- Sources: **{', '.join(s.source for s in r.sources)}**")
    lines.append(f"- States: **{', '.join(r.states)}**")
    lines.append(f"- Started: {r.started_at.isoformat()}")
    if r.completed_at is not None:
        lines.append(f"- Completed: {r.completed_at.isoformat()}")
    lines.append("")

    lines.append("## Cross-source dedup")
    lines.append("")
    lines.append(f"- Dropped (cross-source): **{r.dedup.dropped_total}**")
    lines.append(f"- Within-source duplicate ids dropped: **{r.dedup.within_source_dups}**")
    for (winner, loser), n in sorted(r.dedup.drops_by_pair.items()):
        lines.append(f"- `{loser}` dropped in favor of `{winner}`: **{n}**")
    lines.append("")

    for s in r.sources:
        lines.append("## " + s.source)
        lines.append("")
        lines.extend(_source_block(s, dry_run=r.mode == "dry-run"))

    if r.odbl_dump_url:
        lines.append("## ODbL dump")
        lines.append("")
        lines.append(f"- OpenStreetMap-derived database published: {r.odbl_dump_url}")
        lines.append("")

    if r.errors:
        lines.append("## Errors")
        lines.append("")
        for err in r.errors:
            lines.append(f"- {err}")
        lines.append("")
    return "\n".join(lines)

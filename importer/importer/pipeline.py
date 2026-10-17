"""End-to-end orchestration of all pipeline stages, across multiple sources."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from importer.geo.states import StateLocator
from importer.reports import DedupReport, PipelineResult, SourceResult
from importer.sources.base import Source
from importer.stages.apply import apply_to_supabase
from importer.stages.apply_state_law import ApplyStateLawStats, apply_state_law
from importer.stages.dedup import dedup
from importer.stages.diff import DiffStats, diff_candidates
from importer.stages.normalize import NormalizeStats, normalize
from importer.stages.odbl_dump import generate_and_upload
from importer.stages.orphans import OrphanCapExceeded, plan_orphans, scope_to_states
from importer.stages.refine_coords import refine_coords
from importer.state_laws import StateLawTable
from importer.supabase_client import SupabaseClient


def run_pipeline(
    *,
    sources: list[Source],
    state_laws: StateLawTable,
    client: SupabaseClient,
    states: list[str],
    mode: str,
    system_user_id: str,
    refetch: bool = False,
    state_locator: StateLocator | None = None,
    delete_orphans: bool = False,
    orphan_delete_cap: int | None = None,
) -> PipelineResult:
    """Fetch, classify and dedup every source, diff each against its system
    pins, then (apply mode) write.

    Orphans are a source's system pins inside the run's states (located with
    `state_locator`) that no candidate claimed. An apply marks them; with
    `delete_orphans` it deletes the ones no user corrected. A dry-run plans
    them the way `delete_orphans` would. Every source's delete cap is checked
    before anything is written, so one breach stops the whole apply.
    """
    if delete_orphans and mode != "apply":
        raise ValueError("delete_orphans is apply-only")
    started_at = datetime.now(timezone.utc)
    state_set = set(states) if states else None

    # Phase A: per-source fetch -> normalize -> refine -> classify.
    per_source: list[dict] = []
    all_classified = []
    for source in sources:
        source.fetch(refetch=refetch)
        raw = list(source.iter_candidates(state_filter=state_set))
        norm_stats = NormalizeStats()
        normalized = list(normalize(raw, stats=norm_stats))
        refined = list(refine_coords(normalized))
        asl_stats = ApplyStateLawStats()
        classified = list(apply_state_law(refined, table=state_laws, stats=asl_stats))
        all_classified.extend(classified)
        skip = getattr(source, "last_skip_counts", {})
        per_source.append({
            "source": source.SOURCE_NAME,
            "fetched": len(raw),
            "asl": asl_stats,
            "norm": norm_stats,
            "skips": dict(skip),
            "geocode_miss": int(skip.get("geocode_miss", 0)) if source.SOURCE_NAME == "gsa" else None,
        })

    # Phase B: one cross-source dedup pass against all user pins.
    existing_user_pins = client.select_user_pins()
    dedup_out = dedup(all_classified, existing_user_pins=existing_user_pins)
    survivors_by_source: dict[str, list] = {}
    for cc in dedup_out.survivors:
        survivors_by_source.setdefault(cc.candidate.source, []).append(cc)

    # Phase C1: diff every source and plan its orphans. Nothing is written yet.
    plan_deletes = mode == "dry-run" or delete_orphans
    source_results: list[SourceResult] = []
    for ps in per_source:
        name = ps["source"]
        survivors = survivors_by_source.get(name, [])
        existing = client.select_system_pins(name)
        in_scope = scope_to_states(existing, states=state_set, locator=state_locator)
        diff_result = diff_candidates(
            survivors, existing=existing, in_scope=in_scope, stats=DiffStats()
        )
        orphan_plan = plan_orphans(
            diff_result.orphans, in_scope_count=len(in_scope),
            delete=plan_deletes, cap=orphan_delete_cap,
        )
        asl: ApplyStateLawStats = ps["asl"]
        geocode_matched = None
        if name == "gsa":
            geocode_matched = sum(
                1 for cc in survivors
                if cc.candidate.coord_quality.value == "address_centroid"
            )
        source_results.append(SourceResult(
            source=name,
            candidates_fetched=ps["fetched"],
            candidates_after_state_filter=ps["fetched"],
            classified=asl.classified,
            dropped_no_cell=asl.dropped_no_cell,
            missing_cells=sorted(asl.missing_cells),
            name_truncations=ps["norm"].truncations,
            diff=diff_result,
            geocode_matched=geocode_matched,
            geocode_missed=ps["geocode_miss"],
            orphan_plan=orphan_plan,
            skip_counts=ps["skips"],
        ))

    # Phase C2: delete caps, for every source before any write: a truncated
    # download must not wipe a layer.
    breaches = [
        f"{sr.source}: {len(sr.orphan_plan.delete)} orphan deletions exceed "
        f"the cap of {sr.orphan_plan.cap}"
        for sr in source_results
        if sr.orphan_plan.breached
    ]
    if breaches and mode == "apply":
        raise OrphanCapExceeded("; ".join(breaches) + "; nothing was written")
    errors = [f"{b}; an apply with --delete-orphans would stop" for b in breaches]

    # Phase C3: writes.
    if mode == "apply":
        for sr in source_results:
            apply_to_supabase(
                sr.diff, client=client, system_user_id=system_user_id,
                orphan_plan=sr.orphan_plan,
            )

    # Phase D: ODbL dump (apply mode only, and only when OSM rows actually landed).
    odbl_dump_url = None
    if mode == "apply":
        osm_applied = sum(
            len(sr.diff.inserts) + len(sr.diff.updates)
            for sr in source_results
            if sr.source == "osm"
        )
        if osm_applied > 0:
            odbl_dump_url = generate_and_upload(client=client, out_dir=Path.cwd())

    return PipelineResult(
        mode=mode,
        started_at=started_at,
        completed_at=datetime.now(timezone.utc),
        states=sorted(state_set) if state_set else [],
        sources=source_results,
        dedup=DedupReport(
            dropped_total=dedup_out.dropped_total,
            within_source_dups=dedup_out.within_source_dups,
            drops_by_pair=dedup_out.drops_by_pair,
        ),
        errors=errors,
        odbl_dump_url=odbl_dump_url,
    )

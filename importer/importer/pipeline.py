"""End-to-end orchestration of all pipeline stages, across multiple sources."""

from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from importer.reports import DedupReport, PipelineResult, SourceResult
from importer.sources.base import Source
from importer.stages.apply import apply_to_supabase
from importer.stages.apply_state_law import ApplyStateLawStats, apply_state_law
from importer.stages.dedup import dedup
from importer.stages.diff import DiffStats, diff_candidates
from importer.stages.normalize import NormalizeStats, normalize
from importer.stages.odbl_dump import generate_and_upload
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
) -> PipelineResult:
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
            "geocode_miss": int(skip.get("geocode_miss", 0)) if source.SOURCE_NAME == "gsa" else None,
        })

    # Phase B: one cross-source dedup pass against all user pins.
    existing_user_pins = client.select_user_pins()
    dedup_out = dedup(all_classified, existing_user_pins=existing_user_pins)
    survivors_by_source: dict[str, list] = {}
    for cc in dedup_out.survivors:
        survivors_by_source.setdefault(cc.candidate.source, []).append(cc)

    # Phase C: per-source diff + apply on the survivors.
    source_results: list[SourceResult] = []
    for ps in per_source:
        name = ps["source"]
        survivors = survivors_by_source.get(name, [])
        diff_stats = DiffStats()
        eids = [cc.candidate.source_external_id for cc in survivors]
        existing = client.select_pins_by_keys(name, eids)
        diff_result = diff_candidates(survivors, existing=existing, stats=diff_stats)
        if mode == "apply":
            apply_to_supabase(diff_result, client=client, system_user_id=system_user_id, source=name)
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
        ))

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
        odbl_dump_url=odbl_dump_url,
    )

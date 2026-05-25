"""End-to-end orchestration of all pipeline stages."""

from __future__ import annotations

from datetime import datetime, timezone

from importer.reports import PipelineResult
from importer.sources.base import Source
from importer.stages.apply import apply_to_supabase
from importer.stages.apply_state_law import ApplyStateLawStats, apply_state_law
from importer.stages.dedup import dedup
from importer.stages.diff import DiffStats, diff_candidates
from importer.stages.normalize import NormalizeStats, normalize
from importer.stages.refine_coords import refine_coords
from importer.state_laws import StateLawTable
from importer.supabase_client import SupabaseClient


def run_pipeline(
    *,
    source: Source,
    state_laws: StateLawTable,
    client: SupabaseClient,
    states: list[str],
    mode: str,
    system_user_id: str,
    refetch: bool = False,
) -> PipelineResult:
    started_at = datetime.now(timezone.utc)
    state_set = set(states) if states else None

    source.fetch(refetch=refetch)

    # 1. Source → Candidates
    raw_candidates = list(source.iter_candidates(state_filter=state_set))
    fetched = len(raw_candidates)
    after_filter = fetched  # state_filter already applied inside the source

    # 2. Normalize names
    norm_stats = NormalizeStats()
    normalized = list(normalize(raw_candidates, stats=norm_stats))

    # 3. Refine coordinates (Phase 2 pass-through)
    refined = list(refine_coords(normalized))

    # 4. Apply state law (drop unclassifiable)
    asl_stats = ApplyStateLawStats()
    classified = list(apply_state_law(refined, table=state_laws, stats=asl_stats))

    # 5. Dedup (Phase 2 pass-through)
    deduped = list(dedup(classified, existing_user_pins=[]))

    # 6. Diff against Supabase
    diff_stats = DiffStats()
    external_ids = [cc.candidate.source_external_id for cc in deduped]
    existing = client.select_pins_by_keys(source.SOURCE_NAME, external_ids)
    diff_result = diff_candidates(deduped, existing=existing, stats=diff_stats)

    # 7. Apply (no-op in dry-run)
    if mode == "apply":
        apply_to_supabase(
            diff_result,
            client=client,
            system_user_id=system_user_id,
            source=source.SOURCE_NAME,
        )

    completed_at = datetime.now(timezone.utc)
    return PipelineResult(
        mode=mode,
        started_at=started_at,
        completed_at=completed_at,
        source=source.SOURCE_NAME,
        states=sorted(state_set) if state_set else [],
        candidates_fetched=fetched,
        candidates_after_state_filter=after_filter,
        classified=asl_stats.classified,
        dropped_no_cell=asl_stats.dropped_no_cell,
        missing_cells=sorted(asl_stats.missing_cells),
        name_truncations=norm_stats.truncations,
        diff=diff_result,
    )

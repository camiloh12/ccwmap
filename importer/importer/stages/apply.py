"""Convert diff output into Supabase writes (service-role)."""

from __future__ import annotations

from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import DiffResult
from importer.stages.orphans import OrphanPlan, plan_orphans
from importer.supabase_client import SupabaseClient, SupabaseUpsertRow


# Default flags per source category. HIFLD courthouses are public buildings
# with security screening; signage is irrelevant (carry is statutorily
# prohibited regardless of posting), but the spec convention is to default
# has_posted_signage=False since the importer cannot verify it externally.
_HIFLD_COURTS_DEFAULTS = {
    "has_security_screening": True,
    "has_posted_signage": False,
}


def _status_int(cell_status: str) -> int:
    return {"ALLOWED": 0, "UNCERTAIN": 1, "NO_GUN": 2}[cell_status]


def _to_upsert_row(
    cc: ClassifiedCandidate, *, system_user_id: str
) -> SupabaseUpsertRow:
    defaults = _HIFLD_COURTS_DEFAULTS if cc.candidate.source == "hifld_courts" else {
        "has_security_screening": False,
        "has_posted_signage": False,
    }
    return SupabaseUpsertRow(
        source=cc.candidate.source,
        source_external_id=cc.candidate.source_external_id,
        source_dataset_version=cc.candidate.source_dataset_version,
        name=cc.candidate.name,
        latitude=cc.candidate.latitude,
        longitude=cc.candidate.longitude,
        status=_status_int(cc.cell.default_status),
        restriction_tag=cc.candidate.category.value,
        has_security_screening=defaults["has_security_screening"],
        has_posted_signage=defaults["has_posted_signage"],
        created_by=system_user_id,
        confidence=cc.cell.confidence,
        legal_citation=cc.cell.citation,
        legal_citation_verified_date=cc.cell.last_verified_date.isoformat(),
    )


def apply_to_supabase(
    diff: DiffResult,
    *,
    client: SupabaseClient,
    system_user_id: str,
    orphan_plan: OrphanPlan | None = None,
) -> None:
    """Write one source's diff.

    Re-keys go first, so the upsert (keyed on source + source_external_id)
    refreshes re-keyed pins instead of inserting duplicates. A user-corrected
    pin is re-keyed but not refreshed: its edits stay. Orphans follow
    `orphan_plan` (default: mark them all).
    """
    for rk in diff.rekeys:
        client.patch_external_id(rk.pin_id, rk.new_external_id)

    refreshed = diff.inserts + diff.updates + [
        rk.classified for rk in diff.rekeys if not rk.user_modified
    ]
    rows = [_to_upsert_row(cc, system_user_id=system_user_id) for cc in refreshed]
    if rows:
        client.upsert_pins(rows)

    plan = orphan_plan or plan_orphans(diff.orphans, in_scope_count=0, delete=False)
    to_mark = [row.id for row in plan.keep + plan.mark]
    if plan.delete:
        wanted = [row.id for row in plan.delete]
        deleted = set(client.delete_pins(wanted))
        # Corrected by a user after the diff, so the delete skipped it: mark it.
        to_mark += [pid for pid in wanted if pid not in deleted]
    if to_mark:
        client.mark_orphans(to_mark)

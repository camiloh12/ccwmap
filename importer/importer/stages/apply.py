"""Convert diff output into Supabase writes (service-role)."""

from __future__ import annotations

from uuid import uuid4

from importer.stages.apply_state_law import ClassifiedCandidate
from importer.stages.diff import DiffResult
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
        id=str(uuid4()),  # stable per-row identity at insert; updates upsert by (source, source_external_id)
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
    source: str,
) -> None:
    rows = [
        _to_upsert_row(cc, system_user_id=system_user_id)
        for cc in diff.inserts + diff.updates
    ]
    if rows:
        client.upsert_pins(rows)

    orphan_eids = [
        row.source_external_id
        for row in diff.orphans
        if row.source_external_id is not None
    ]
    if orphan_eids:
        client.mark_orphans(source, orphan_eids)

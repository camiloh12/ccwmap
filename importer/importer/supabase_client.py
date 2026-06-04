"""Thin wrapper around Supabase Postgrest using the service-role key."""

from __future__ import annotations

from typing import Any

import httpx
from pydantic import BaseModel, ConfigDict


class ExistingPinRow(BaseModel):
    model_config = ConfigDict(frozen=True)

    id: str
    source: str
    source_external_id: str | None
    name: str
    latitude: float
    longitude: float
    status: int
    restriction_tag: str | None
    user_modified: bool
    source_dataset_version: str | None


class SupabaseUpsertRow(BaseModel):
    model_config = ConfigDict(frozen=True)

    # NOTE: id intentionally omitted — pins.id has a gen_random_uuid() default;
    # sending a fresh id would rewrite the PK of existing rows on merge-duplicates upsert.
    source: str
    source_external_id: str
    source_dataset_version: str
    name: str
    latitude: float
    longitude: float
    status: int
    restriction_tag: str
    has_security_screening: bool
    has_posted_signage: bool
    created_by: str
    confidence: str
    legal_citation: str
    legal_citation_verified_date: str  # ISO 8601 date
    imported_at: str | None = None     # set by server default `now()` when null
    source_orphaned_at: None = None    # always null on upsert; orphan-marking is a separate stage


class SupabaseClient:
    """All HTTP traffic goes through this wrapper so we have one place to add
    retry logic, structured logging, and rate-limiting later."""

    SELECT_COLUMNS = (
        "id,source,source_external_id,name,latitude,longitude,"
        "status,restriction_tag,user_modified,source_dataset_version"
    )

    # Max external-ids per `in.(...)` request. A single request inlines every id
    # into the URL query, so large sources (GSA emits ~10k) would otherwise blow
    # past httpx's URL-component cap and the Supabase gateway's URL limit. 200
    # ids keeps each URL well under 8 KB.
    ID_CHUNK_SIZE = 200

    def __init__(
        self,
        *,
        url: str,
        service_role_key: str,
        system_user_id: str,
        timeout: float = 30.0,
    ) -> None:
        self._base = url.rstrip("/") + "/rest/v1"
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        }
        self._system_user_id = system_user_id
        self._client = httpx.Client(timeout=timeout)

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "SupabaseClient":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        self.close()

    def select_pins_by_keys(
        self, source: str, external_ids: list[str]
    ) -> list[ExistingPinRow]:
        if not external_ids:
            return []
        out: list[ExistingPinRow] = []
        for i in range(0, len(external_ids), self.ID_CHUNK_SIZE):
            chunk = external_ids[i : i + self.ID_CHUNK_SIZE]
            # Postgrest `in.(...)` requires quoted strings for text columns.
            in_list = ",".join(f'"{eid}"' for eid in chunk)
            params = {
                "select": self.SELECT_COLUMNS,
                "source": f"eq.{source}",
                "source_external_id": f"in.({in_list})",
            }
            r = self._client.get(
                f"{self._base}/pins", headers=self._headers, params=params
            )
            r.raise_for_status()
            out.extend(ExistingPinRow.model_validate(row) for row in r.json())
        return out

    def select_user_pins(self) -> list[ExistingPinRow]:
        """All user-created pins — dedup must never clobber these.

        Note: returns up to Postgrest's default page size (1000 rows). Adequate
        at current scale (~hundreds of user pins); add a Range-header pager if
        user-created pins ever exceed that.
        """
        params = {"select": self.SELECT_COLUMNS, "source": "eq.user"}
        r = self._client.get(f"{self._base}/pins", headers=self._headers, params=params)
        r.raise_for_status()
        return [ExistingPinRow.model_validate(row) for row in r.json()]

    def upsert_pins(
        self, rows: list[SupabaseUpsertRow], *, batch_size: int = 500
    ) -> None:
        if not rows:
            return
        headers = dict(self._headers)
        # Postgrest upsert via Prefer: resolution=merge-duplicates +
        # on_conflict query param naming the unique-ish key columns.
        headers["Prefer"] = "return=minimal,resolution=merge-duplicates"
        url = f"{self._base}/pins?on_conflict=source,source_external_id"
        for i in range(0, len(rows), batch_size):
            batch = [r.model_dump(mode="json", exclude_none=True) for r in rows[i : i + batch_size]]
            r = self._client.post(url, headers=headers, json=batch)
            r.raise_for_status()

    def insert_import_run(self, *, mode: str, source_filter: str) -> str:
        payload = {"mode": mode, "source_filter": source_filter}
        r = self._client.post(
            f"{self._base}/import_runs", headers=self._headers, json=payload
        )
        r.raise_for_status()
        return r.json()[0]["run_id"]

    def update_import_run(
        self,
        *,
        run_id: str,
        candidates_processed: int,
        inserts: int,
        updates: int,
        skips: int,
        orphans_marked: int,
        errors_json: dict[str, Any] | None,
        report_artifact_url: str | None,
    ) -> None:
        payload: dict[str, Any] = {
            "completed_at": "now()",
            "candidates_processed": candidates_processed,
            "inserts": inserts,
            "updates": updates,
            "skips": skips,
            "orphans_marked": orphans_marked,
            "errors_json": errors_json,
            "report_artifact_url": report_artifact_url,
        }
        headers = dict(self._headers)
        headers["Prefer"] = "return=minimal"
        r = self._client.patch(
            f"{self._base}/import_runs?run_id=eq.{run_id}",
            headers=headers,
            json=payload,
        )
        r.raise_for_status()

    def mark_orphans(self, source: str, external_ids: list[str]) -> None:
        if not external_ids:
            return
        headers = dict(self._headers)
        headers["Prefer"] = "return=minimal"
        for i in range(0, len(external_ids), self.ID_CHUNK_SIZE):
            chunk = external_ids[i : i + self.ID_CHUNK_SIZE]
            in_list = ",".join(f'"{eid}"' for eid in chunk)
            r = self._client.patch(
                f"{self._base}/pins?source=eq.{source}"
                f"&source_external_id=in.({in_list})",
                headers=headers,
                json={"source_orphaned_at": "now()"},
            )
            r.raise_for_status()

"""Thin wrapper around Supabase Postgrest using the service-role key."""

from __future__ import annotations

from typing import Any

import httpx
from pydantic import BaseModel, ConfigDict


class OsmDumpRow(BaseModel):
    model_config = ConfigDict(frozen=True)

    source_external_id: str
    name: str
    latitude: float
    longitude: float


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
    source_orphaned_at: None = None    # sent as null on every upsert (see upsert_pins)


class SupabaseClient:
    """All HTTP traffic goes through this wrapper so we have one place to add
    retry logic, structured logging, and rate-limiting later."""

    SELECT_COLUMNS = (
        "id,source,source_external_id,name,latitude,longitude,"
        "status,restriction_tag,user_modified,source_dataset_version"
    )

    # Pin UUIDs per `in.(...)` request: 36 chars plus an encoded comma each,
    # so 100 ids keep a URL near 4 KB.
    UUID_CHUNK_SIZE = 100
    PAGE_SIZE = 1000

    def __init__(
        self,
        *,
        url: str,
        service_role_key: str,
        system_user_id: str,
        timeout: float = 30.0,
    ) -> None:
        self._project_url = url.rstrip("/")
        self._storage_base = self._project_url + "/storage/v1"
        self._base = self._project_url + "/rest/v1"
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

    def select_system_pins(self, source: str) -> list[ExistingPinRow]:
        """Every pin of `source` owned by the system user, i.e. every pin the
        importer wrote for it. Paged with a Range header; ordered by id so
        pages don't shift between requests."""
        out: list[ExistingPinRow] = []
        offset = 0
        while True:
            headers = dict(self._headers)
            headers["Range-Unit"] = "items"
            headers["Range"] = f"{offset}-{offset + self.PAGE_SIZE - 1}"
            params = {
                "select": self.SELECT_COLUMNS,
                "source": f"eq.{source}",
                "created_by": f"eq.{self._system_user_id}",
                "order": "id",
            }
            r = self._client.get(f"{self._base}/pins", headers=headers, params=params)
            r.raise_for_status()
            rows = r.json()
            out.extend(ExistingPinRow.model_validate(row) for row in rows)
            if len(rows) < self.PAGE_SIZE:
                return out
            offset += self.PAGE_SIZE

    def patch_external_id(self, pin_id: str, new_external_id: str) -> None:
        """Re-key one pin in place: its UUID and any user edits survive. A
        service-role write never sets user_modified (013)."""
        r = self._client.patch(
            f"{self._base}/pins",
            headers=self._headers,  # return=representation: count the rows changed
            params={"id": f"eq.{pin_id}", "select": "id"},
            json={"source_external_id": new_external_id, "source_orphaned_at": None},
        )
        r.raise_for_status()
        if not r.json():
            raise RuntimeError(f"re-key of pin {pin_id} changed no row; was it deleted mid-run?")

    def delete_pins(self, pin_ids: list[str]) -> list[str]:
        """Delete system-owned pins no user corrected; return the ids deleted.

        A pin a user corrected after the diff is left alone (the caller marks
        it instead). The record_pin_deletion trigger writes the tombstones; the
        delete rate limit skips service_role (008 §6c).
        """
        deleted: list[str] = []
        for i in range(0, len(pin_ids), self.UUID_CHUNK_SIZE):
            chunk = pin_ids[i : i + self.UUID_CHUNK_SIZE]
            r = self._client.delete(
                f"{self._base}/pins",
                headers=self._headers,  # return=representation: the ids deleted
                params={
                    "id": f"in.({','.join(chunk)})",
                    "user_modified": "eq.false",
                    "created_by": f"eq.{self._system_user_id}",
                    "select": "id",
                },
            )
            r.raise_for_status()
            deleted.extend(row["id"] for row in r.json())
        return deleted

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
            # exclude_none drops imported_at (server default on insert) but would
            # also drop source_orphaned_at; send it explicitly so a record that
            # comes back is no longer marked orphaned.
            batch = [
                {**r.model_dump(mode="json", exclude_none=True), "source_orphaned_at": None}
                for r in rows[i : i + batch_size]
            ]
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

    def mark_orphans(self, pin_ids: list[str]) -> None:
        """Set source_orphaned_at = now() on these pins."""
        headers = dict(self._headers)
        headers["Prefer"] = "return=minimal"
        for i in range(0, len(pin_ids), self.UUID_CHUNK_SIZE):
            chunk = pin_ids[i : i + self.UUID_CHUNK_SIZE]
            r = self._client.patch(
                f"{self._base}/pins",
                headers=headers,
                params={"id": f"in.({','.join(chunk)})"},
                json={"source_orphaned_at": "now()"},
            )
            r.raise_for_status()

    def select_osm_pins_for_dump(self) -> list["OsmDumpRow"]:
        """All source='osm' rows, derived columns only (for the ODbL dump)."""
        out: list[OsmDumpRow] = []
        offset = 0
        page = 1000
        while True:
            headers = dict(self._headers)
            headers["Range-Unit"] = "items"
            headers["Range"] = f"{offset}-{offset + page - 1}"
            params = {
                "select": "source_external_id,name,latitude,longitude",
                "source": "eq.osm",
            }
            r = self._client.get(f"{self._base}/pins", headers=headers, params=params)
            r.raise_for_status()
            rows = r.json()
            out.extend(OsmDumpRow.model_validate(row) for row in rows)
            if len(rows) < page:
                break
            offset += page
        return out

    def public_object_url(self, bucket: str, path: str) -> str:
        return f"{self._storage_base}/object/public/{bucket}/{path}"

    def ensure_public_bucket(self, bucket: str) -> None:
        headers = {
            "apikey": self._headers["apikey"],
            "Authorization": self._headers["Authorization"],
            "Content-Type": "application/json",
        }
        r = self._client.post(
            f"{self._storage_base}/bucket",
            headers=headers,
            json={"id": bucket, "name": bucket, "public": True},
        )
        # 200/201 = created; 409 (or 400 "already exists") = idempotent success.
        if r.status_code in (200, 201, 409):
            return
        if r.status_code == 400 and "exist" in r.text.lower():
            return
        r.raise_for_status()

    def upload_object(
        self, *, bucket: str, path: str, data: bytes, content_type: str
    ) -> None:
        headers = {
            "apikey": self._headers["apikey"],
            "Authorization": self._headers["Authorization"],
            "Content-Type": content_type,
            "x-upsert": "true",
        }
        r = self._client.post(
            f"{self._storage_base}/object/{bucket}/{path}",
            headers=headers,
            content=data,
        )
        r.raise_for_status()

    def list_object_names(self, bucket: str) -> list[str]:
        headers = {
            "apikey": self._headers["apikey"],
            "Authorization": self._headers["Authorization"],
            "Content-Type": "application/json",
        }
        r = self._client.post(
            f"{self._storage_base}/object/list/{bucket}",
            headers=headers,
            json={"prefix": "", "limit": 1000, "offset": 0},
        )
        r.raise_for_status()
        return [obj["name"] for obj in r.json()]

    def delete_objects(self, bucket: str, paths: list[str]) -> None:
        if not paths:
            return
        headers = {
            "apikey": self._headers["apikey"],
            "Authorization": self._headers["Authorization"],
            "Content-Type": "application/json",
        }
        r = self._client.request(
            "DELETE",
            f"{self._storage_base}/object/{bucket}",
            headers=headers,
            json={"prefixes": paths},
        )
        r.raise_for_status()

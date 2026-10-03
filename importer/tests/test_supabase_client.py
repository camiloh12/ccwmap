import json

import httpx
import pytest
from pytest_httpx import HTTPXMock

from importer.supabase_client import (
    ExistingPinRow,
    SupabaseClient,
    SupabaseUpsertRow,
)


@pytest.fixture()
def client() -> SupabaseClient:
    return SupabaseClient(
        url="https://example.supabase.co",
        service_role_key="srk-test",
        system_user_id="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
    )


SYS = "81775f8b-1a6a-47d6-b793-e9ab7e38634e"


def _pin_json(i: int, **kw) -> dict:
    row = {
        "id": f"00000000-0000-0000-0000-{i:012d}", "source": "gsa",
        "source_external_id": f"E{i}", "name": f"P{i}", "latitude": 30.0,
        "longitude": -97.0, "status": 2, "restriction_tag": "FEDERAL_PROPERTY",
        "user_modified": False, "source_dataset_version": "v",
    }
    row.update(kw)
    return row


def _upsert_row(eid: str) -> SupabaseUpsertRow:
    return SupabaseUpsertRow(
        source="gsa", source_external_id=eid, source_dataset_version="v",
        name="P", latitude=30.0, longitude=-97.0, status=2,
        restriction_tag="FEDERAL_PROPERTY", has_security_screening=False,
        has_posted_signage=False, created_by=SYS, confidence="high",
        legal_citation="18 USC §930(a)", legal_citation_verified_date="2026-05-31",
    )


def test_select_system_pins_pages_until_a_short_page(client, httpx_mock):
    httpx_mock.add_response(method="GET", match_headers={"Range": "0-999"},
                            json=[_pin_json(i) for i in range(1000)])
    httpx_mock.add_response(method="GET", match_headers={"Range": "1000-1999"},
                            json=[_pin_json(1000 + i) for i in range(5)])
    rows = client.select_system_pins("gsa")
    assert len(rows) == 1005
    url = str(httpx_mock.get_requests()[0].url)
    assert "source=eq.gsa" in url
    assert f"created_by=eq.{SYS}" in url
    assert "order=id" in url


def test_patch_external_id_rekeys_one_pin_and_clears_the_orphan_mark(client, httpx_mock):
    httpx_mock.add_response(method="PATCH", json=[{"id": "p1"}])
    client.patch_external_id("p1", "13-14-14000592")
    req = httpx_mock.get_requests()[0]
    assert "id=eq.p1" in str(req.url)
    assert json.loads(req.content) == {
        "source_external_id": "13-14-14000592", "source_orphaned_at": None,
    }


def test_patch_external_id_fails_loudly_when_no_row_changed(client, httpx_mock):
    httpx_mock.add_response(method="PATCH", json=[])
    with pytest.raises(RuntimeError, match="p1"):
        client.patch_external_id("p1", "X")


def test_delete_pins_only_deletes_uncorrected_system_pins(client, httpx_mock):
    httpx_mock.add_response(method="DELETE", json=[{"id": "a"}])
    assert client.delete_pins(["a", "b"]) == ["a"]
    url = str(httpx_mock.get_requests()[0].url)
    assert "id=in.%28a%2Cb%29" in url
    assert "user_modified=eq.false" in url
    assert f"created_by=eq.{SYS}" in url


def test_delete_pins_chunks_and_skips_empty(client, httpx_mock):
    assert client.delete_pins([]) == []
    httpx_mock.add_response(method="DELETE", json=[])
    client.delete_pins([f"00000000-0000-0000-0000-{i:012d}" for i in range(250)])
    reqs = httpx_mock.get_requests()
    assert len(reqs) == 3
    assert all(len(str(r.url)) < 8000 for r in reqs)


def test_mark_orphans_marks_by_pin_id_in_chunks(client, httpx_mock):
    httpx_mock.add_response(method="PATCH", status_code=204)
    client.mark_orphans([f"00000000-0000-0000-0000-{i:012d}" for i in range(250)])
    reqs = httpx_mock.get_requests()
    assert len(reqs) == 3
    assert all(len(str(r.url)) < 8000 for r in reqs)
    assert "id=in.%2800000000-0000-0000-0000-000000000000%2C" in str(reqs[0].url)
    assert json.loads(reqs[0].content) == {"source_orphaned_at": "now()"}


def test_upsert_pins_clears_the_orphan_mark(client, httpx_mock):
    # A record marked orphaned in an earlier run that reappears must be un-marked.
    httpx_mock.add_response(method="POST", status_code=201, json=[])
    client.upsert_pins([_upsert_row("E1")])
    body = json.loads(httpx_mock.get_requests()[0].content)
    assert body[0]["source_orphaned_at"] is None
    assert "imported_at" not in body[0]  # server default on insert, untouched on update


def test_upsert_pins_batches_at_500(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    rows = [
        SupabaseUpsertRow(
            source="hifld_courts",
            source_external_id=f"E{i}",
            source_dataset_version="HIFLD-2026-05",
            name=f"P{i}",
            latitude=29.0,
            longitude=-95.0,
            status=2,
            restriction_tag="STATE_LOCAL_GOVT",
            has_security_screening=True,
            has_posted_signage=False,
            created_by="81775f8b-1a6a-47d6-b793-e9ab7e38634e",
            confidence="high",
            legal_citation="18 USC 930(a)",
            legal_citation_verified_date="2026-05-01",
        )
        for i in range(1200)
    ]
    httpx_mock.add_response(
        method="POST",
        url="https://example.supabase.co/rest/v1/pins?on_conflict=source%2Csource_external_id",
        json=[],
        status_code=201,
    )

    client.upsert_pins(rows)

    # 1200 rows / 500 batch = 3 requests
    requests = httpx_mock.get_requests()
    assert len(requests) == 3


def test_insert_and_update_import_run_returns_uuid(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    httpx_mock.add_response(
        method="POST",
        url="https://example.supabase.co/rest/v1/import_runs",
        json=[{"run_id": "11111111-1111-1111-1111-111111111111"}],
        status_code=201,
    )
    httpx_mock.add_response(
        method="PATCH",
        url="https://example.supabase.co/rest/v1/import_runs?run_id=eq.11111111-1111-1111-1111-111111111111",
        json=[],
        status_code=204,
    )

    run_id = client.insert_import_run(mode="dry-run", source_filter="hifld_courts")
    assert run_id == "11111111-1111-1111-1111-111111111111"

    client.update_import_run(
        run_id=run_id,
        candidates_processed=10,
        inserts=8,
        updates=1,
        skips=1,
        orphans_marked=0,
        errors_json=None,
        report_artifact_url=None,
    )


def test_select_user_pins_filters_source_user(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    httpx_mock.add_response(
        method="GET",
        json=[{
            "id": "00000000-0000-0000-0000-0000000000aa",
            "source": "user", "source_external_id": None,
            "name": "My Pin", "latitude": 30.0, "longitude": -97.0,
            "status": 2, "restriction_tag": "FEDERAL_PROPERTY",
            "user_modified": True, "source_dataset_version": None,
        }],
    )
    rows = client.select_user_pins()
    assert len(rows) == 1
    assert rows[0].source == "user"
    assert "source=eq.user" in str(httpx_mock.get_requests()[0].url)


# ---------------------------------------------------------------------------
# Storage methods + OSM dump reader (Task 6)
# ---------------------------------------------------------------------------

from importer.supabase_client import OsmDumpRow


def test_select_osm_pins_for_dump_parses(client, httpx_mock):
    httpx_mock.add_response(
        method="GET",
        json=[
            {"source_external_id": "node/1001", "name": "The Houston Tap",
             "latitude": 29.76, "longitude": -95.37},
        ],
    )
    rows = client.select_osm_pins_for_dump()
    assert rows == [OsmDumpRow(source_external_id="node/1001",
                               name="The Houston Tap", latitude=29.76, longitude=-95.37)]
    assert "source=eq.osm" in str(httpx_mock.get_requests()[0].url)


def test_ensure_public_bucket_treats_existing_as_success(client, httpx_mock):
    httpx_mock.add_response(
        method="POST",
        url="https://example.supabase.co/storage/v1/bucket",
        status_code=409,
        json={"error": "Duplicate", "message": "already exists"},
    )
    client.ensure_public_bucket("odbl-dumps")  # must not raise


def test_upload_object_posts_with_upsert(client, httpx_mock):
    httpx_mock.add_response(
        method="POST",
        url="https://example.supabase.co/storage/v1/object/odbl-dumps/dump-2026-06-16.csv.gz",
        status_code=200,
        json={"Key": "odbl-dumps/dump-2026-06-16.csv.gz"},
    )
    client.upload_object(
        bucket="odbl-dumps", path="dump-2026-06-16.csv.gz",
        data=b"\x1f\x8b", content_type="application/gzip",
    )
    req = httpx_mock.get_requests()[0]
    assert req.headers.get("x-upsert") == "true"
    assert req.content == b"\x1f\x8b"


def test_public_object_url():
    from importer.supabase_client import SupabaseClient
    c = SupabaseClient(url="https://example.supabase.co", service_role_key="k",
                       system_user_id="u")
    assert c.public_object_url("odbl-dumps", "dump-2026-06-16.csv.gz") == (
        "https://example.supabase.co/storage/v1/object/public/odbl-dumps/dump-2026-06-16.csv.gz"
    )


def test_delete_objects_sends_prefixes(client, httpx_mock):
    httpx_mock.add_response(
        method="DELETE",
        url="https://example.supabase.co/storage/v1/object/odbl-dumps",
        status_code=200, json=[],
    )
    client.delete_objects("odbl-dumps", ["dump-2026-01-01.csv.gz"])
    req = httpx_mock.get_requests()[0]
    assert b"dump-2026-01-01.csv.gz" in req.content

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


def test_select_pins_by_keys_returns_parsed_rows(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    httpx_mock.add_response(
        method="GET",
        url="https://example.supabase.co/rest/v1/pins?select=id,source,source_external_id,name,latitude,longitude,status,restriction_tag,user_modified,source_dataset_version&source=eq.hifld_courts&source_external_id=in.%28%22A%22%2C%22B%22%29",
        json=[
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "source": "hifld_courts",
                "source_external_id": "A",
                "name": "Old A",
                "latitude": 29.0,
                "longitude": -95.0,
                "status": 2,
                "restriction_tag": "STATE_LOCAL_GOVT",
                "user_modified": False,
                "source_dataset_version": "HIFLD-2026-04",
            }
        ],
    )
    rows = client.select_pins_by_keys("hifld_courts", ["A", "B"])
    assert len(rows) == 1
    assert isinstance(rows[0], ExistingPinRow)
    assert rows[0].source_external_id == "A"


def test_select_pins_by_keys_chunks_large_id_lists(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    # One reusable response per chunk; each returns a single row so we can also
    # prove the chunks are concatenated rather than overwritten.
    httpx_mock.add_response(
        method="GET",
        json=[
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "source": "gsa",
                "source_external_id": "RPUID-0",
                "name": "Federal Building",
                "latitude": 30.0,
                "longitude": -97.0,
                "status": 2,
                "restriction_tag": "FEDERAL_PROPERTY",
                "user_modified": False,
                "source_dataset_version": "FRPP-FY24",
            }
        ],
    )
    ids = [f"RPUID-{i}" for i in range(450)]
    rows = client.select_pins_by_keys("gsa", ids)

    requests = httpx_mock.get_requests()
    # 450 ids / 200 per chunk -> 3 requests; rows concatenated across them.
    assert len(requests) == 3
    assert len(rows) == 3
    # Every id is covered exactly once, and no single URL approaches the limit.
    all_urls = "".join(str(r.url) for r in requests)
    for r in requests:
        assert len(str(r.url)) < 8000
    # ids are not percent-encoded (the surrounding quotes/commas are), so each
    # appears verbatim in exactly one chunk's URL.
    for eid in ids:
        assert eid in all_urls


def test_mark_orphans_chunks_large_id_lists(
    client: SupabaseClient, httpx_mock: HTTPXMock
) -> None:
    httpx_mock.add_response(method="PATCH", json=[], status_code=204)
    ids = [f"RPUID-{i}" for i in range(450)]
    client.mark_orphans("gsa", ids)

    requests = httpx_mock.get_requests()
    assert len(requests) == 3
    for r in requests:
        assert len(str(r.url)) < 8000


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

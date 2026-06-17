import gzip
from datetime import date
from pathlib import Path

from importer.stages.odbl_dump import generate_and_upload
from importer.supabase_client import OsmDumpRow


class FakeClient:
    def __init__(self, rows, existing_objects=None):
        self._rows = rows
        self._objects = existing_objects or []
        self.uploaded = []
        self.deleted = []
        self.ensured = []

    def select_osm_pins_for_dump(self):
        return self._rows

    def ensure_public_bucket(self, bucket):
        self.ensured.append(bucket)

    def upload_object(self, *, bucket, path, data, content_type):
        self.uploaded.append((bucket, path, data, content_type))

    def list_object_names(self, bucket):
        return list(self._objects)

    def delete_objects(self, bucket, paths):
        self.deleted.extend(paths)

    def public_object_url(self, bucket, path):
        return f"https://example.supabase.co/storage/v1/object/public/{bucket}/{path}"


def test_returns_none_when_no_osm_rows(tmp_path):
    client = FakeClient(rows=[])
    assert generate_and_upload(client=client, out_dir=tmp_path) is None
    assert client.uploaded == []


def test_writes_gz_with_header_and_uploads(tmp_path):
    rows = [
        OsmDumpRow(source_external_id="node/1001", name="The Houston Tap",
                   latitude=29.76, longitude=-95.37),
        OsmDumpRow(source_external_id="way/2002", name="Downtown Pub House",
                   latitude=29.761, longitude=-95.37),
    ]
    client = FakeClient(rows=rows)
    url = generate_and_upload(client=client, out_dir=tmp_path, today=date(2026, 6, 16))

    expected_name = "dump-2026-06-16.csv.gz"
    assert url.endswith(expected_name)
    written = tmp_path / expected_name
    text = gzip.decompress(written.read_bytes()).decode("utf-8")
    assert text.startswith("#")                       # ODbL license header
    assert "Open Database License" in text
    assert "osm_type,osm_id,name,latitude,longitude" in text
    assert "node,1001,The Houston Tap,29.76,-95.37" in text
    assert "way,2002,Downtown Pub House,29.761,-95.37" in text

    assert client.ensured == ["odbl-dumps"]
    bucket, path, data, ctype = client.uploaded[0]
    assert (bucket, path, ctype) == ("odbl-dumps", expected_name, "application/gzip")
    assert data == written.read_bytes()


def test_prunes_dumps_older_than_90_days(tmp_path):
    rows = [OsmDumpRow(source_external_id="node/1", name="A", latitude=29.0, longitude=-95.0)]
    client = FakeClient(
        rows=rows,
        existing_objects=[
            "dump-2026-01-01.csv.gz",   # >90 days before 2026-06-16 -> pruned
            "dump-2026-06-10.csv.gz",   # within 90 days -> kept
            "not-a-dump.txt",           # ignored
        ],
    )
    generate_and_upload(client=client, out_dir=tmp_path, today=date(2026, 6, 16))
    assert client.deleted == ["dump-2026-01-01.csv.gz"]

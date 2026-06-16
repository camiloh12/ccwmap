"""ODbL share-alike dump for OSM-sourced pins (spec §6.3-6.5).

Publishes the *derived database* — the OSM-derived columns of source='osm' rows
(osm_type, osm_id, name, latitude, longitude). It deliberately EXCLUDES our work
product (status, restriction tag, citation, confidence), which is not OSM-derived.
Anyone can re-derive our classification from these ids against OpenStreetMap.

Wired into pipeline Phase D (apply mode only). Generates a dated, gzip'd CSV,
uploads it to a public Supabase Storage bucket, and prunes dumps > 90 days old.
"""

from __future__ import annotations

import csv
import gzip
import io
import logging
import re
from datetime import date, timedelta
from pathlib import Path
from typing import Protocol

logger = logging.getLogger(__name__)

_PRUNE_AFTER_DAYS = 90
_DUMP_RE = re.compile(r"^dump-(\d{4})-(\d{2})-(\d{2})\.csv\.gz$")

_LICENSE_HEADER = (
    "# CCW Map — OpenStreetMap-derived venue database (ODbL share-alike).\n"
    "# Source: OpenStreetMap contributors. License: Open Database License (ODbL) v1.0.\n"
    "# https://opendatacommons.org/licenses/odbl/1-0/\n"
    "# Contains only OSM-derived columns; legal classifications are excluded.\n"
)


class _DumpClient(Protocol):
    def select_osm_pins_for_dump(self) -> list: ...
    def ensure_public_bucket(self, bucket: str) -> None: ...
    def upload_object(self, *, bucket: str, path: str, data: bytes, content_type: str) -> None: ...
    def list_object_names(self, bucket: str) -> list[str]: ...
    def delete_objects(self, bucket: str, paths: list[str]) -> None: ...
    def public_object_url(self, bucket: str, path: str) -> str: ...


def generate_and_upload(
    *,
    client: _DumpClient,
    out_dir: Path,
    bucket: str = "odbl-dumps",
    today: date | None = None,
) -> str | None:
    """Build + upload the dated ODbL dump. Returns its public URL, or None if no
    OSM rows exist."""
    rows = client.select_osm_pins_for_dump()
    if not rows:
        logger.info("odbl_dump: no OSM rows; nothing to dump.")
        return None

    today = today or date.today()
    filename = f"dump-{today.isoformat()}.csv.gz"

    buf = io.StringIO()
    buf.write(_LICENSE_HEADER)
    writer = csv.writer(buf)
    writer.writerow(["osm_type", "osm_id", "name", "latitude", "longitude"])
    for row in rows:
        osm_type, _, osm_id = row.source_external_id.partition("/")
        writer.writerow([osm_type, osm_id, row.name, row.latitude, row.longitude])
    data = gzip.compress(buf.getvalue().encode("utf-8"))

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / filename).write_bytes(data)

    client.ensure_public_bucket(bucket)
    client.upload_object(bucket=bucket, path=filename, data=data, content_type="application/gzip")
    _prune(client, bucket, today)

    url = client.public_object_url(bucket, filename)
    logger.info("odbl_dump: uploaded %d OSM rows to %s", len(rows), url)
    return url


def _prune(client: _DumpClient, bucket: str, today: date) -> None:
    cutoff = today - timedelta(days=_PRUNE_AFTER_DAYS)
    stale: list[str] = []
    for name in client.list_object_names(bucket):
        m = _DUMP_RE.match(name)
        if not m:
            continue
        dumped = date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if dumped < cutoff:
            stale.append(name)
    if stale:
        client.delete_objects(bucket, stale)
        logger.info("odbl_dump: pruned %d dumps older than %d days", len(stale), _PRUNE_AFTER_DAYS)

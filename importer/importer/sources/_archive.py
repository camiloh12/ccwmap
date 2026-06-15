"""Shared fetch helpers for sources whose upstream files ship as zips / xlsx.

The Phase 5 sources (nces, ipeds, faa) read public datasets distributed as a
``.zip`` wrapping an ``.xlsx`` or CSV(s). These helpers download the archive and
normalize the one member each source needs into a plain UTF-8 CSV at the source's
cache path, so every source's ``iter_candidates`` can stay a simple
``csv.DictReader`` over that path. Keeping the archive handling here avoids
repeating zip/xlsx plumbing across three nearly-identical ``fetch`` methods.
"""

from __future__ import annotations

import csv
import io
import zipfile
from collections.abc import Callable
from pathlib import Path

import httpx
import openpyxl


def download(url: str, *, timeout: float = 300.0) -> bytes:
    with httpx.Client(timeout=timeout, follow_redirects=True) as client:
        r = client.get(url)
        r.raise_for_status()
        return r.content


def extract_member(
    zip_bytes: bytes, dest: Path, *, match: Callable[[str], bool]
) -> None:
    """Write the first zip member whose basename satisfies `match` to dest verbatim."""
    zf = zipfile.ZipFile(io.BytesIO(zip_bytes))
    member = next(n for n in zf.namelist() if match(n.rsplit("/", 1)[-1]))
    dest.write_bytes(zf.read(member))


def extract_member_as_utf8(
    zip_bytes: bytes, dest: Path, *, match: Callable[[str], bool]
) -> None:
    """Extract the matching member and rewrite it as UTF-8 (cp1252 fallback)."""
    zf = zipfile.ZipFile(io.BytesIO(zip_bytes))
    member = next(n for n in zf.namelist() if match(n.rsplit("/", 1)[-1]))
    raw = zf.read(member)
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("cp1252")
    dest.write_text(text, encoding="utf-8")


def xlsx_bytes_to_csv(xlsx_bytes: bytes, dest: Path) -> None:
    """Flatten the active sheet of a bare .xlsx to a CSV at dest."""
    wb = openpyxl.load_workbook(io.BytesIO(xlsx_bytes), read_only=True, data_only=True)
    try:
        ws = wb.active
        with open(dest, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            for row in ws.iter_rows(values_only=True):
                writer.writerow(["" if v is None else v for v in row])
    finally:
        wb.close()


def xlsx_in_zip_to_csv(zip_bytes: bytes, dest: Path) -> None:
    """Find the single .xlsx inside a zip and flatten it to a CSV at dest."""
    zf = zipfile.ZipFile(io.BytesIO(zip_bytes))
    member = next(n for n in zf.namelist() if n.lower().endswith(".xlsx"))
    xlsx_bytes_to_csv(zf.read(member), dest)

"""Rebuild data/geo/us_states_500k.geojson from the Census cartographic boundary file.

Usage (from importer/): uv run --with pyshp python scripts/make_state_boundaries.py --year 2025
"""

from __future__ import annotations

import argparse
import json
import tempfile
import zipfile
from pathlib import Path

import httpx
import shapefile  # pyshp

from importer.geo.states import US_STATES_AND_DC

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OUT_PATH = REPO_ROOT / "data" / "geo" / "us_states_500k.geojson"
URL = "https://www2.census.gov/geo/tiger/GENZ{year}/shp/cb_{year}_us_state_500k.zip"


def _round(coords):
    if isinstance(coords[0], (int, float)):
        return [round(c, 6) for c in coords]
    return [_round(c) for c in coords]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--year", type=int, required=True)
    args = parser.parse_args(argv)

    stem = f"cb_{args.year}_us_state_500k"
    with tempfile.TemporaryDirectory() as tmp:
        resp = httpx.get(URL.format(year=args.year), timeout=120, follow_redirects=True)
        resp.raise_for_status()
        zpath = Path(tmp) / f"{stem}.zip"
        zpath.write_bytes(resp.content)
        with zipfile.ZipFile(zpath) as zf:
            zf.extractall(tmp)
        features = []
        with shapefile.Reader(str(Path(tmp) / f"{stem}.shp")) as reader:
            for sr in reader.shapeRecords():
                rec = sr.record.as_dict()
                if rec["STUSPS"] not in US_STATES_AND_DC:
                    continue
                geom = dict(sr.shape.__geo_interface__)
                geom["coordinates"] = _round(geom["coordinates"])
                features.append({
                    "type": "Feature",
                    "properties": {"STUSPS": rec["STUSPS"], "NAME": rec["NAME"]},
                    "geometry": geom,
                })

    if len(features) != 51:
        print(f"expected 51 features, kept {len(features)}; not writing")
        return 1
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    text = json.dumps({"type": "FeatureCollection", "features": features}, separators=(",", ":"))
    OUT_PATH.write_text(text + "\n", encoding="utf-8")
    print(f"{len(features)} features, {OUT_PATH.stat().st_size} bytes -> {OUT_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

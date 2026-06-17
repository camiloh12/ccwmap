"""One-off: build assets/geo/world_minus_us.geojson — a single dissolved
polygon of all NON-US land within a North-America bounding box, used as a
fill mask so the low-zoom density heatmap doesn't bleed onto Canada/Mexico/
Cuba/etc. Natural Earth is public domain; no attribution required.

Run from the repo root (uses the importer's venv which already has shapely):
    cd importer && pip install requests shapely    # if not already present
    cd .. && python tool/generate_land_mask.py
"""
import json
import os
import requests
from shapely.geometry import shape, mapping, box
from shapely.ops import unary_union

# Natural Earth 1:50m Admin-0 countries (public domain).
URL = (
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/"
    "master/geojson/ne_50m_admin_0_countries.geojson"
)
# Only foreign land reachable from the app's continental-US viewport matters.
NA_BBOX = box(-170.0, 5.0, -50.0, 75.0)
OUT_PATH = os.path.join("assets", "geo", "world_minus_us.geojson")
SIMPLIFY_TOLERANCE_DEG = 0.01  # ~1 km; small file, border fidelity near metros


def main() -> None:
    print(f"Downloading {URL} ...")
    resp = requests.get(URL, timeout=180)
    resp.raise_for_status()  # fail loudly on a non-200 instead of a cryptic JSON error
    data = resp.json()

    geoms = []
    for feature in data["features"]:
        props = feature["properties"]
        name = props.get("SOVEREIGNT") or props.get("ADMIN") or ""
        if name == "United States of America":
            continue  # leave a US-shaped hole so the glow shows over the US
        geom = shape(feature["geometry"]).intersection(NA_BBOX)
        if not geom.is_empty:
            geoms.append(geom)

    merged = unary_union(geoms).simplify(
        SIMPLIFY_TOLERANCE_DEG, preserve_topology=True
    )

    out = {
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "properties": {
                    "note": "Non-US land mask. Natural Earth 1:50m (public domain).",
                },
                "geometry": mapping(merged),
            }
        ],
    }

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as fh:
        json.dump(out, fh)
    size_kb = os.path.getsize(OUT_PATH) / 1024
    print(f"Wrote {OUT_PATH} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()

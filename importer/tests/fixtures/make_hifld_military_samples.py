"""Regenerate the MIRTA fixtures. Run from importer/:

    uv run python tests/fixtures/make_hifld_military_samples.py

Writes hifld_military_sample.geojson (layer 1, boundaries) and
hifld_military_points_sample.geojson (layer 0, DoD site points). Field names
and value shapes match the live service: lower-case state codes on most
records, SDSID null on 202 boundaries, MIRTALOCATIONSIDPK a single space.
"""

import json
from pathlib import Path

HERE = Path(__file__).parent
ZERO = "00000000-0000-0000-0000-000000000000"


def square(w, s, e, n):
    return [[[w, s], [e, s], [e, n], [w, n], [w, s]]]


def polygon(w, s, e, n):
    return {"type": "Polygon", "coordinates": square(w, s, e, n)}


def multipolygon(*boxes):
    return {"type": "MultiPolygon", "coordinates": [square(*b) for b in boxes]}


def boundary(sdsid, name, state, geometry, status="act"):
    return {
        "type": "Feature",
        "properties": {
            "SDSID": sdsid,
            "SITENAME": name,
            "STATENAMECODE": state,
            "SITEOPERATIONALSTATUS": status,
            "SITEREPORTINGCOMPONENT": "usa",
            "MIRTALOCATIONSIDPK": " ",
        },
        "geometry": geometry,
    }


def site(sdsid, name, state, lng, lat):
    return {
        "type": "Feature",
        "properties": {"SDSID": sdsid, "SITENAME": name, "STATENAMECODE": state},
        "geometry": {"type": "Point", "coordinates": [lng, lat]},
    }


BOUNDARIES = [
    boundary("MIL-TX-1", "Fort Cavazos", "tx", polygon(-97.79, 31.13, -97.77, 31.15)),
    boundary("MIL-FL-1", "NAS Jacksonville", "fl", multipolygon((-81.68, 30.22, -81.66, 30.24))),
    boundary("MIL-PA-1", "Carlisle Barracks", "pa", polygon(-77.19, 40.20, -77.17, 40.22)),
    boundary("MIL-CA-1", "Camp Pendleton", "ca", polygon(-117.40, 33.30, -117.38, 33.32)),
    boundary("MIL-NULL", "No Geometry Base", "tx", None),
    # No SDSID: keyed by state + name. The old code gave all of these the id " ".
    boundary(None, "NG Camp Mabry", "tx", polygon(-97.77, 30.31, -97.75, 30.33)),
    # All-zero SDSID: also keyed by state + name.
    boundary(ZERO, "Camp Blanding", "fl", polygon(-81.99, 29.95, -81.97, 29.97)),
    # One installation split across two records: merged into one candidate.
    boundary(None, "NG Camp Swift", "tx", polygon(-97.30, 30.27, -97.28, 30.29)),
    boundary(None, "NG Camp Swift", "tx", polygon(-97.26, 30.25, -97.25, 30.26)),
    # Multi-part base whose DoD point is on the small part (JBSA: Lackland, not Camp Bullis).
    boundary("MIL-TX-JBSA", "Joint Base San Antonio", "tx",
             multipolygon((-98.60, 29.65, -98.50, 29.75), (-98.63, 29.37, -98.61, 29.39))),
    # Multi-part base whose point is ~8 km off and whose area centroid misses both parts.
    boundary("MIL-FL-JAX", "Jacksonville IAP (ANG)", "fl",
             multipolygon((-81.70, 30.48, -81.68, 30.50), (-81.50, 30.48, -81.49, 30.49))),
    boundary("MIL-TX-CLOSED", "Closed Depot", "tx", polygon(-97.10, 31.50, -97.08, 31.52), status="clsd"),
    boundary("MIL-PA-CARE", "Caretaker Depot", "pa", polygon(-76.90, 40.27, -76.88, 40.29), status="care"),
]

POINTS = [
    site("MIL-TX-1", "Fort Cavazos", "tx", -97.775, 31.145),             # on the base
    site("MIL-FL-1", "NAS Jacksonville", "fl", -81.65969, 30.23),         # ~30 m east of the boundary
    site(None, "NG  Camp Mabry", "TX", -97.755, 30.325),                   # state + name match
    site("MIL-TX-JBSA", "Joint Base San Antonio", "tx", -98.62, 29.38),   # on the small part
    site("MIL-FL-JAX", "Jacksonville IAP (ANG)", "fl", -81.60, 30.49),    # off the base
    site("MIL-CA-9", "Unrelated Site", "ca", -117.0, 33.0),
]


def _write(name, features):
    (HERE / name).write_text(
        json.dumps({"type": "FeatureCollection", "features": features}, indent=1) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    _write("hifld_military_sample.geojson", BOUNDARIES)
    _write("hifld_military_points_sample.geojson", POINTS)

"""Regenerate gsa_frpp_sample.xlsx. Run from importer/:

    uv run python tests/fixtures/make_gsa_frpp_sample.py

The real FRPP file has 117 columns; the fixture carries only the ones
GsaSource reads. Agency and bureau codes are strings, as in the real file.
"""

from pathlib import Path

import openpyxl

HEADER = (
    "Real Property Unique Identifier", "Real Property Type", "Real Property Use",
    "Street Address", "City Name", "State Name", "Zip Code", "Latitude", "Longitude",
    "Installation Name", "Reporting Agency Code", "Reporting Bureau Code", "Asset Status",
)

OK = "Current Mission Need"

ROWS = [
    ("RPUID-TX-1", "Building", "Office", "100 Main St", "Austin", "TEXAS", "78701", 30.2672, -97.7431, "Federal Office Building", "47", "00", OK),
    ("RPUID-TX-2", "Building", "Courthouse", "200 Geocode Ave", "Houston", "TEXAS", "77002", None, None, "US Courthouse Houston", "47", "00", OK),
    ("RPUID-CA-1", "Building", "Office", "1 Bay St", "San Francisco", "CALIFORNIA", "94105", 37.79, -122.4, "SF Federal Building", "47", "00", OK),
    ("RPUID-TX-3", "Land", "Vacant", "Rural Rd", "Marfa", "TEXAS", "79843", None, None, "Vacant Federal Land", "47", "00", OK),
    ("RPUID-TX-4", "Building", "Office", None, "Dallas", "TEXAS", "75201", None, None, "No Address Building", "47", "00", OK),
    ("RPUID-TX-5", "Building", "Office", "1 Bad Coord Rd", "Portland Mills", "TEXAS", "75001", 43.0392538, -87.9031992, "Mislocated Federal Building", "47", "00", OK),
    ("RPUID-TX-6", "Building", "Office", "500 Commerce St", "Dallas", "TEXAS", "75201", 32.7767, -96.797, "DALLAS, TX", "47", "00", OK),
    ("RPUID-TX-7", "Building", "Warehouses", "1234 Main Street", "Austin", "TEXAS", "78704", 30.25, -97.75, "1234 Main Street", "47", "00", OK),
    # One property id under two agencies: two buildings, two pins.
    ("RPUID-TX-DUP", "Building", "Office", "10 Alamo Plaza", "San Antonio", "TEXAS", "78205", 29.4241, -98.4936, "San Antonio Federal Center", "13", "14", OK),
    ("RPUID-TX-DUP", "Building", "Office", "20 Broadway", "Lubbock", "TEXAS", "79401", 33.5779, -101.8552, "Lubbock Federal Building", "14", "10", "Determination to Dispose"),
    # No longer federal property.
    ("RPUID-TX-GONE", "Building", "Office", "30 Austin Ave", "Waco", "TEXAS", "76701", 31.5493, -97.1467, "Former Federal Building", "47", "00", "Disposed"),
    # Blank bureau code: no stable identity.
    ("RPUID-TX-NOBUREAU", "Building", "Office", "40 Broadway", "Tyler", "TEXAS", "75701", 32.3513, -95.3011, "Tyler Federal Building", "47", None, OK),
    # One property id, no coordinates: each row must get its own geocode.
    ("RPUID-TX-GEO", "Building", "Office", "50 Smith St", "Houston", "TEXAS", "77002", None, None, "Houston Annex A", "13", "14", OK),
    ("RPUID-TX-GEO", "Building", "Office", "60 Fannin St", "Houston", "TEXAS", "77002", None, None, "Houston Annex B", "14", "10", OK),
]


def main() -> None:
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.append(HEADER)
    for row in ROWS:
        ws.append(row)
    wb.save(Path(__file__).with_name("gsa_frpp_sample.xlsx"))


if __name__ == "__main__":
    main()

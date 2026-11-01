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
    "Number of Federal Employees", "Legal Interest Indicator",
)

OK = "Current Mission Need"

ROWS = [
    ("RPUID-TX-1", "Building", "Office", "100 Main St", "Austin", "TEXAS", "78701", 30.2672, -97.7431, "Federal Office Building", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-2", "Building", "Courthouse", "200 Geocode Ave", "Houston", "TEXAS", "77002", None, None, "US Courthouse Houston", "47", "00", OK, None, "Owned"),
    ("RPUID-CA-1", "Building", "Office", "1 Bay St", "San Francisco", "CALIFORNIA", "94105", 37.79, -122.4, "SF Federal Building", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-3", "Land", "Vacant", "Rural Rd", "Marfa", "TEXAS", "79843", None, None, "Vacant Federal Land", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-4", "Building", "Office", None, "Dallas", "TEXAS", "75201", None, None, "No Address Building", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-5", "Building", "Office", "1 Bad Coord Rd", "Portland Mills", "TEXAS", "75001", 43.0392538, -87.9031992, "Mislocated Federal Building", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-6", "Building", "Office", "500 Commerce St", "Dallas", "TEXAS", "75201", 32.7767, -96.797, "DALLAS, TX", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-7", "Building", "Warehouses", "1234 Main Street", "Austin", "TEXAS", "78704", 30.25, -97.75, "1234 Main Street", "47", "00", OK, "3", "Owned"),
    # One property id under two agencies: two buildings, two pins.
    ("RPUID-TX-DUP", "Building", "Office", "10 Alamo Plaza", "San Antonio", "TEXAS", "78205", 29.4241, -98.4936, "San Antonio Federal Center", "13", "14", OK, None, "Owned"),
    ("RPUID-TX-DUP", "Building", "Office", "20 Broadway", "Lubbock", "TEXAS", "79401", 33.5779, -101.8552, "Lubbock Federal Building", "14", "10", "Determination to Dispose", None, "Owned"),
    # No longer federal property.
    ("RPUID-TX-GONE", "Building", "Office", "30 Austin Ave", "Waco", "TEXAS", "76701", 31.5493, -97.1467, "Former Federal Building", "47", "00", "Disposed", None, "Owned"),
    # Blank bureau code: no stable identity.
    ("RPUID-TX-NOBUREAU", "Building", "Office", "40 Broadway", "Tyler", "TEXAS", "75701", 32.3513, -95.3011, "Tyler Federal Building", "47", None, OK, None, "Owned"),
    # One property id, no coordinates: each row must get its own geocode.
    ("RPUID-TX-GEO", "Building", "Office", "50 Smith St", "Houston", "TEXAS", "77002", None, None, "Houston Annex A", "13", "14", OK, None, "Owned"),
    ("RPUID-TX-GEO", "Building", "Office", "60 Fannin St", "Houston", "TEXAS", "77002", None, None, "Houston Annex B", "14", "10", OK, None, "Owned"),
    # Use and employee filter rows.
    ("RPUID-TX-HOUSING", "Building", "Family Housing", "1 Housing Ln", "Austin", "TEXAS", "78701", 43.0392538, -87.9031992, "Federal Housing", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-PO", "Building", "Post Office", "2 Mail St", "Austin", "TEXAS", "78701", 30.2700, -97.7400, "Austin Post Office", "47", "00", OK, "40", "Owned"),
    ("RPUID-TX-ZERO", "Building", "Office", "3 Empty St", "Austin", "TEXAS", "78701", 30.2710, -97.7410, "Empty Federal Office", "47", "00", OK, "0", "Owned"),
    ("RPUID-TX-UPPER", "Building", "OFFICE", "4 Caps St", "Austin", "TEXAS", "78701", 30.2720, -97.7420, "Caps Federal Office", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-WH-STAFFED", "Building", "Warehouses", "5 Depot Rd", "Austin", "TEXAS", "78701", 30.2730, -97.7430, "Staffed Federal Depot", "47", "00", OK, "1,951", "Owned"),
    ("RPUID-TX-WH-BLANK", "Building", "Warehouses", "6 Depot Rd", "Austin", "TEXAS", "78701", 30.2740, -97.7440, "Unstaffed Federal Depot", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-SPACEPORT", "Building", "Spaceport", "7 Launch Rd", "Austin", "TEXAS", "78701", 30.2750, -97.7450, "Federal Spaceport", "47", "00", OK, "12", "Owned"),
    ("RPUID-TX-NOGEO", "Building", "Office", "8 Nowhere Rd", "Austin", "TEXAS", "78701", None, None, "Ungeocodable Federal Office", "47", "00", OK, None, "Owned"),
    ("RPUID-TX-NONAME", "Building", "Office", "9 Blank St", "Austin", "TEXAS", "78701", 30.2760, -97.7460, None, "47", "00", OK, None, "Owned"),
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

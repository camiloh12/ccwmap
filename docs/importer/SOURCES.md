# Importer source datasets

Running roster of upstream datasets the importer reads, their licenses, and
our compliance posture.

| Source | Module | License | Coverage | Status |
|---|---|---|---|---|
| HIFLD Courthouses | `importer/importer/sources/hifld_courts.py` | Public domain (DHS HIFLD Open) | Federal/state/local courthouses, US-wide | Phase 2 (live in staging) |
| GSA FRPP | `importer/importer/sources/gsa.py` | Public domain (US Gov) | Federal owned/leased buildings (`Real Property Type == Building`) | Phase 4 (built + live-validated; staging apply pending) |
| HIFLD Military (MIRTA) | `importer/importer/sources/hifld_military.py` | Public domain (US Gov / DoD DISDI) | Military installation boundaries (polygon centroids) | Phase 4 (built + live-validated; staging apply pending) |
| NCES K-12 | (not yet) | Public domain (US Gov) | K-12 public + private | Phase 5 |
| IPEDS | (not yet) | Public domain (US Gov) | Colleges, universities | Phase 5 |
| FAA NPIAS | (not yet) | Public domain (US Gov) | Public-use airports | Phase 5 |
| HIFLD Hospitals | (not yet) | Public domain | Hospitals | Phase 5 |
| OSM (Overpass) | (not yet) | **ODbL — share-alike** | Bars, places of worship, etc. | Phase 6 |

## License notes

- **Public-domain sources** (NCES, IPEDS, FAA, GSA, HIFLD, USPS) carry no attribution requirement. We attribute them in this file for honesty but the app does not display per-pin source links for them.
- **GSA FRPP format + scope.** The public dataset is a single-sheet **`.xlsx`** (FY24 release is ~145 MB / ~308k rows), streamed read-only with openpyxl — not a CSV. State is filtered on the UPPERCASE `State Name` column (the `State Code` column is FIPS-numeric); the pin name comes from `Installation Name`. Only `Real Property Type == Building` is imported (Structures and Land are not "federal facilities" under 18 USC 930). Latitude/Longitude are present on ~97% of rows, so geocoding is a rare fallback.
- **GSA FRPP geocoding.** The few FRPP rows without coordinates are geocoded from their street address via the [US Census batch geocoder](https://geocoding.geo.census.gov/geocoder/) (`benchmark=Public_AR_Current`) — public domain, no API key, US-only. Rows the geocoder cannot match are dropped (never coordinate-faked) and counted in the dry-run report.
- **HIFLD Military → USACE MIRTA.** The legacy HIFLD Open hub was deactivated 2025-08-26. The military source now reads the USACE-owned MIRTA (Military Installations, Ranges, and Training Areas) feature service — "DoD Sites – Boundaries" (layer 1), polygon boundaries reduced to their centroid. Fields are UPPERCASE (`SITENAME`, stable GUID `SDSID`, `SITEREPORTINGCOMPONENT`). The pinned config URL is the layer's `/query?...&f=geojson` endpoint, which returns the full layer in one request (maxRecordCount 1000 > 825 features).
- **ODbL sources** (OSM) carry a share-alike obligation. Pre-populated OSM pins display "Data: OpenStreetMap (ODbL)" in the pin detail dialog (Phase 4 UI work) and a daily-regenerated `dump-YYYY-MM-DD.csv.gz` of OSM-derived rows is published to a public Supabase Storage bucket (Phase 6 work).
- The work product we contribute — the state-law classifications applied on top of source pins — is dedicated to the public domain under CC0 (see [`data/state_laws/LICENSE`](../../data/state_laws/LICENSE)).

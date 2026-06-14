# Importer source datasets

Running roster of upstream datasets the importer reads, their licenses, and
our compliance posture.

| Source | Module | License | Coverage | Status |
|---|---|---|---|---|
| HIFLD Courthouses | `importer/importer/sources/hifld_courts.py` | Public domain (DHS HIFLD Open) | Federal/state/local courthouses, US-wide | Phase 2 (live in staging) |
| GSA FRPP | `importer/importer/sources/gsa.py` | Public domain (US Gov) | Federal owned/leased buildings (`Real Property Type == Building`) | Phase 4 (built + live-validated; staging apply pending) |
| HIFLD Military (MIRTA) | `importer/importer/sources/hifld_military.py` | Public domain (US Gov / DoD DISDI) | Military installation boundaries (polygon centroids) | Phase 4 (built + live-validated; staging apply pending) |
| NCES K-12 | `importer/importer/sources/nces.py` | Public domain (US Gov) | K-12 **public** schools (EDGE geocode + CCD status) | Phase 5 (built) |
| IPEDS | `importer/importer/sources/ipeds.py` | Public domain (US Gov) | Colleges, universities (HD directory) | Phase 5 (built) |
| FAA commercial-service | `importer/importer/sources/faa.py` | Public domain (US Gov) | Commercial-service airports (TSA-screened secured area) | Phase 5 (built) |
| HIFLD Hospitals | (not yet) | Public domain | Hospitals | Phase 5 |
| OSM (Overpass) | (not yet) | **ODbL — share-alike** | Bars, places of worship, etc. | Phase 6 |

## License notes

- **Public-domain sources** (NCES, IPEDS, FAA, GSA, HIFLD, USPS) carry no attribution requirement. We attribute them in this file for honesty but the app does not display per-pin source links for them.
- **GSA FRPP format + scope.** The public dataset is a single-sheet **`.xlsx`** (FY24 release is ~145 MB / ~308k rows), streamed read-only with openpyxl — not a CSV. State is filtered on the UPPERCASE `State Name` column (the `State Code` column is FIPS-numeric); the pin name comes from `Installation Name`. Only `Real Property Type == Building` is imported (Structures and Land are not "federal facilities" under 18 USC 930). Latitude/Longitude are present on ~97% of rows, so geocoding is a rare fallback.
- **GSA FRPP geocoding.** The few FRPP rows without coordinates are geocoded from their street address via the [US Census batch geocoder](https://geocoding.geo.census.gov/geocoder/) (`benchmark=Public_AR_Current`) — public domain, no API key, US-only. Rows the geocoder cannot match are dropped (never coordinate-faked) and counted in the dry-run report.
- **HIFLD Military → USACE MIRTA.** The legacy HIFLD Open hub was deactivated 2025-08-26. The military source now reads the USACE-owned MIRTA (Military Installations, Ranges, and Training Areas) feature service — "DoD Sites – Boundaries" (layer 1), polygon boundaries reduced to their centroid. Fields are UPPERCASE (`SITENAME`, stable GUID `SDSID`, `SITEREPORTINGCOMPONENT`). The pinned config URL is the layer's `/query?...&f=geojson` endpoint, which returns the full layer in one request (maxRecordCount 1000 > 825 features).
- **NCES K-12 (public schools).** Two CSVs joined on `NCESSCH`: the EDGE public-school geocode file (name, state, LAT/LON — the coordinate driver) + the CCD Common Core of Data directory file (`SY_STATUS` operational filter, so closed campuses are excluded). Public schools only — private schools are not included. All candidates carry **native coordinates** (no Census geocoding or coordinate refinement).
- **IPEDS colleges.** Single IPEDS HD ("Directory information") CSV — no join; `UNITID` is the stable per-institution id (`INSTNM`, `STABBR`, `LATITUDE`, `LONGITUD`, `CYACTIVE`). Category `COLLEGE_UNIVERSITY`. Only FL has a `COLLEGE_UNIVERSITY` state-law cell; TX and PA candidates are emitted but drop at `apply_state_law` — these appear as "missing cells" in dry-run output. See `docs/importer/OMISSIONS.md` for the researched rationale. **Native coordinates** — no geocoding.
- **FAA commercial-service airports.** Two CSVs joined on airport location id (`LOCID` in the commercial-service list ↔ `ARPT_ID` in FAA NASR APT data): the commercial-service list (`LOCID`, `STATE`, `AIRPORT_NAME`, `SERVICE_LEVEL`) provides the name and the NASR file (`LAT_DECIMAL`, `LONG_DECIMAL`) provides coordinates. Only the commercial-service subset is imported — these airports have TSA screening and a federal secured-area prohibition (`AIRPORT_SECURE`). General-aviation and other NPIAS public-use airports without commercial service are excluded. Category `AIRPORT_SECURE` (federal-uniform `US` cell). **Native coordinates** — no geocoding.
- **ODbL sources** (OSM) carry a share-alike obligation. Pre-populated OSM pins display "Data: OpenStreetMap (ODbL)" in the pin detail dialog (Phase 4 UI work) and a daily-regenerated `dump-YYYY-MM-DD.csv.gz` of OSM-derived rows is published to a public Supabase Storage bucket (Phase 6 work).
- The work product we contribute — the state-law classifications applied on top of source pins — is dedicated to the public domain under CC0 (see [`data/state_laws/LICENSE`](../../data/state_laws/LICENSE)).

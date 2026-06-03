# Importer source datasets

Running roster of upstream datasets the importer reads, their licenses, and
our compliance posture.

| Source | Module | License | Coverage | Status |
|---|---|---|---|---|
| HIFLD Courthouses | `importer/importer/sources/hifld_courts.py` | Public domain (DHS HIFLD Open) | Federal/state/local courthouses, US-wide | Phase 2 (live in staging) |
| GSA FRPP | `importer/importer/sources/gsa.py` | Public domain (US Gov) | Federal owned/leased property | Phase 4 (built; staging apply pending) |
| HIFLD Military | `importer/importer/sources/hifld_military.py` | Public domain | Military installations | Phase 4 (built; staging apply pending) |
| NCES K-12 | (not yet) | Public domain (US Gov) | K-12 public + private | Phase 5 |
| IPEDS | (not yet) | Public domain (US Gov) | Colleges, universities | Phase 5 |
| FAA NPIAS | (not yet) | Public domain (US Gov) | Public-use airports | Phase 5 |
| HIFLD Hospitals | (not yet) | Public domain | Hospitals | Phase 5 |
| OSM (Overpass) | (not yet) | **ODbL — share-alike** | Bars, places of worship, etc. | Phase 6 |

## License notes

- **Public-domain sources** (NCES, IPEDS, FAA, GSA, HIFLD, USPS) carry no attribution requirement. We attribute them in this file for honesty but the app does not display per-pin source links for them.
- **GSA FRPP geocoding.** FRPP rows without coordinates are geocoded from their street address via the [US Census batch geocoder](https://geocoding.geo.census.gov/geocoder/) (`benchmark=Public_AR_Current`) — public domain, no API key, US-only. Rows the geocoder cannot match are dropped (never coordinate-faked) and counted in the dry-run report.
- **ODbL sources** (OSM) carry a share-alike obligation. Pre-populated OSM pins display "Data: OpenStreetMap (ODbL)" in the pin detail dialog (Phase 4 UI work) and a daily-regenerated `dump-YYYY-MM-DD.csv.gz` of OSM-derived rows is published to a public Supabase Storage bucket (Phase 6 work).
- The work product we contribute — the state-law classifications applied on top of source pins — is dedicated to the public domain under CC0 (see [`data/state_laws/LICENSE`](../../data/state_laws/LICENSE)).

# Importer source datasets

Running roster of upstream datasets the importer reads, their licenses, and
our compliance posture.

| Source | Module | License | Coverage | Status |
|---|---|---|---|---|
| HIFLD Courthouses | `importer/importer/sources/hifld_courts.py` | Public domain (DHS HIFLD Open) | Federal/state/local courthouses, US-wide | Phase 2 (live in staging) |
| NCES K-12 | (not yet) | Public domain (US Gov) | K-12 public + private | Phase 4 |
| IPEDS | (not yet) | Public domain (US Gov) | Colleges, universities | Phase 5 |
| FAA NPIAS | (not yet) | Public domain (US Gov) | Public-use airports | Phase 5 |
| GSA FRPP | (not yet) | Public domain (US Gov) | Federal owned/leased property | Phase 4 |
| HIFLD Hospitals | (not yet) | Public domain | Hospitals | Phase 5 |
| HIFLD Military | (not yet) | Public domain | Military installations | Phase 4 |
| OSM (Overpass) | (not yet) | **ODbL — share-alike** | Bars, places of worship, etc. | Phase 6 |

## License notes

- **Public-domain sources** (NCES, IPEDS, FAA, GSA, HIFLD, USPS) carry no attribution requirement. We attribute them in this file for honesty but the app does not display per-pin source links for them.
- **ODbL sources** (OSM) carry a share-alike obligation. Pre-populated OSM pins display "Data: OpenStreetMap (ODbL)" in the pin detail dialog (Phase 4 UI work) and a daily-regenerated `dump-YYYY-MM-DD.csv.gz` of OSM-derived rows is published to a public Supabase Storage bucket (Phase 6 work).
- The work product we contribute — the state-law classifications applied on top of source pins — is dedicated to the public domain under CC0 (see [`data/state_laws/LICENSE`](../../data/state_laws/LICENSE)).

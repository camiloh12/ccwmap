# Feeback for Importer

## Positive

* Pin density is good and clustering looks fine.

## Negative

* For any zoom action or pan of the map, any pin that was already rendered gets rendered again and causes "jump" or blip (rendered -> goes away for a split second -> rendered again), which is slightly jarring
* There is a pin labeled ALLEGHENY NATIONAL FOREST but it is in the middle of Milwaukee.
* Some pins are just the name of a city (e.g. ST PETERSBURG, FL; TAMPA, FL).
* Some pin labels are just the address of the building (e.g. 10200 49TH STREET BUILDING; 9450 kOGER Boulevard), not what the building is or its name.
* Overall I don't like that some of the labels are all CAPS (low priority).

## Disposition (2026-06-05)

Root-caused against the live FRPP cache + app code.

1. **Render blip on zoom/pan** — app-side. `map_screen.dart` removes+re-adds the
   `pins-source` GeoJSON source and rebuilds layers on every viewport refresh.
   Fix: update source data in place via `setGeoJsonSource`. **Being fixed.**
2. **ALLEGHENY NATIONAL FOREST in Milwaukee** — data bug. One FRPP row has a
   corrupt coord `(43.04, -87.90)` while its `State Name` is PENNSYLVANIA; we
   trusted the lat/lng column without checking it matches the state. 45/9,836
   rows have out-of-state coords (incl. two `(0,0)` null-island rows). Fix:
   point-in-polygon validate coord vs claimed state in `gsa.py`. **Being fixed.**
3. **City-name labels** (`TAMPA, FL` — 43 rows) and 4. **address labels**
   (`9450 Koger Boulevard` — 298 rows) — `Installation Name` used verbatim. Fix:
   detect degenerate names, compose `{Real Property Use} — {City}, {ST}`.
   **Being fixed.**
5. **All-caps labels** — DEFERRED (low priority, per owner). Needs a smart
   title-case pass in the importer `normalize` stage with an acronym
   preserve-list (US, VA, SBA, FBI, IRS, NFH, St, Mc, …). Revisit after 1–4 land
   and the staging map is re-reviewed.
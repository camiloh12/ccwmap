# iOS POI Tap Fix — Implementation Plan

## Problem

On iOS, tapping a POI label (e.g. a restaurant name on the MapTiler base map) opens an edit
dialog for the nearest existing pin instead of a create-pin dialog with the POI name.

**Root cause:** `queryRenderedFeatures` on iOS does not return features from base map symbol
layers. `_detectPoiAtPoint` returns null, so the tap falls through to PRIORITY 3 (nearest-pin
proximity search), which opens an edit dialog.

Base map POI labels DO render visually on iOS — this is confirmed by diagnostic testing.
The problem is purely about tap detection.

---

## Chosen Approach: MapTiler Reverse Geocoding (Option 1)

When `queryRenderedFeatures` fails on iOS, call MapTiler's reverse geocoding API at the tap
coordinates. Filter the result to confirm it is a POI type and visually close to where the
user tapped, then open a create dialog with the returned name.

---

## Implementation

### New file: `lib/data/datasources/maptiler_geocoding_client.dart`

A thin HTTP client wrapping MapTiler's reverse geocoding endpoint:

```
GET https://api.maptiler.com/geocoding/{lng},{lat}.json?key={API_KEY}
```

- Returns a `GeocodingResult` with `name`, `lat`, `lng`, `placeType`
- Returns `null` on network error, timeout, or non-POI result
- Timeout: 5 seconds

**POI type detection:** Accept a result as a POI if:
- `place_type` array contains `"poi"`, OR
- Feature properties contain an `amenity`, `tourism`, `leisure`, or `shop` key

### Modified: `_detectPoiAtPoint` in `lib/presentation/screens/map_screen.dart`

Current flow:
1. `queryRenderedFeatures` on specific POI layer IDs
2. `queryRenderedFeatures` on all layers

New flow — add step 3, **iOS only** (`!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS`):

3. Call `MaptilerGeocodingClient.reverseGeocode(lat, lng, apiKey)`
4. If result is null → return null (fall through to PRIORITY 3)
5. If result is not a POI type → return null
6. Convert result POI coordinates to screen pixels via `mapController.toScreenLocation(LatLng(poiLat, poiLng))`
7. Calculate pixel distance between tap point and POI screen position
8. If pixel distance > 60px → return null (POI anchor too far from tap)
9. Return `{'name': name, 'lat': lat, 'lng': lng}`

The 60px threshold covers the geographic anchor zone of most POI labels at typical zoom
levels. Labels extend further visually but their anchor point is at one end.

---

## Key Decisions

**Why MapTiler and not Nominatim?**
MapTiler API key is already loaded from `.env` and used for map tiles. Same data source,
commercial SLA, no usage policy friction. Nominatim requires a custom `User-Agent` header
and enforces a 1 req/s limit — more friction for a mobile app.

**Why iOS only?**
Android already works via `queryRenderedFeatures`. The geocoding call adds ~200-500ms
latency per tap, so it is skipped on platforms where it is not needed.

**Where does the API key come from?**
`dotenv.env['MAPTILER_API_KEY']` — already loaded at startup. The map screen already reads
it in `_getMapStyleUrl()`. Read it the same way in `_detectPoiAtPoint`.

**No DI changes needed.**
The geocoding client can be instantiated inline or as a stateless utility class. No changes
to `main.dart` or the provider tree.

**What if the API key is missing?**
Skip the geocoding call and fall through to PRIORITY 3. No crash.

**What if MapTiler is down or slow?**
5-second timeout. On timeout or any error → return null → fall through to PRIORITY 3.
Same behavior as today, no regression.

---

## Files to Change

| File | Change |
|---|---|
| `lib/data/datasources/maptiler_geocoding_client.dart` | **New** — reverse geocoding HTTP client |
| `lib/presentation/screens/map_screen.dart` | Add iOS geocoding fallback in `_detectPoiAtPoint` |

No changes to `main.dart`, `pubspec.yaml` (http already a dependency), or test files
unless unit tests are added for the new client.

---

## Known Limitation

If a user taps empty space within 60px (screen) of a POI's anchor point, the geocoding API
will return that POI and open a create dialog. This is unavoidable without `queryRenderedFeatures`
working for base map layers on iOS. It is a much better failure mode than the current
behavior (opening an edit dialog for a distant unrelated pin).

---

## Background: What Was Tried and Removed

A previous attempt re-added the Overpass API to fetch POI data and render a custom symbol
layer on iOS. This was removed because:
- Overpass data never loaded at runtime (`pois:0`)
- Base map POI labels already render visually on iOS without a custom layer
- The Overpass layer was dead code adding complexity with no benefit

The Overpass source files still exist in `lib/data/` and `lib/domain/` but are not wired
into the app. They can be deleted or reused if the Overpass approach is ever revisited.

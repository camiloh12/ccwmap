# Phase 7 Stage A — Pre-Import UI Release (design)

**Date:** 2026-06-19
**Status:** Approved design; pending implementation plan
**Parent:** `docs/superpowers/specs/2026-06-19-phase7-prod-import-rollout-design.md` (§2, Stage A)

## Purpose

Stage A is the app release that must ship **before** the production pre-populate import (Stage B). It adds the two user-facing surfaces that the import depends on:

1. A **"verify locally" caveat** so the flood of ~20,550 red NO_GUN system pins lands with its hedge already visible.
2. **ODbL attribution** for the OSM-derived pins, reachable by everyone including guests.

Both are powered by provenance data that **already exists** on the server and in the local schema but is currently discarded in the Dart domain layer. Stage A is therefore primarily a **client-side vertical slice**: thread that data up through domain → mapper → dialog, then render two UI surfaces. **No migration, no RPC change, no importer change.**

## Scope boundaries

- **In scope:** provenance fields on the domain model; mapper/parser threading (including a latent-bug fix); the pin caveat block; per-pin OSM/ODbL credit; a global About/Legal screen + an always-visible map attribution badge.
- **Out of scope (deferred):** surfacing `user_modified` to the client so the UI can acknowledge community edits (would require adding `user_modified` to the `get_pins_in_view` RPC — a migration). The caveat does not need it (see §4). National-rollout concerns. Any importer/Stage-B work.

---

## §1 — Data plumbing (the vertical slice)

### Current state (verified 2026-06-19)

The provenance data is present everywhere **except** the Dart domain layer:

- `get_pins_in_view` (migration 008) **returns** `source`, `source_external_id`, `confidence`, `legal_citation`, `legal_citation_verified_date` for individual pins.
- The local Drift `pins` table **has** all those columns (`lib/data/database/database.dart`).
- But `PinMetadata` carries **none** of them, and `PinMapper.toEntity` **hardcodes `source: 'user'`** and nulls the rest. Its own comment admits Phase 1 intended callers to overwrite `source` from the RPC row "when provenance is known" — `ViewportPinsManager` never does. **Result: every system pin is currently mis-cached locally as `source='user'` with null provenance.** Stage A fixes this latent bug as a side effect.

### Changes

1. **`lib/domain/models/pin_metadata.dart`** — add five fields, all defaulting to the user-pin values:
   - `String source` (default `'user'`)
   - `String? sourceExternalId`
   - `String? confidence`
   - `String? legalCitation`
   - `String? legalCitationVerifiedDate`

   Update the constructor, `copyWith`, `toJson`/`fromJson`, `==`, and `hashCode`.

2. **`GetPinsInViewRow.parse`** (in `lib/data/datasources/supabase_remote_data_source.dart`) — populate the new `PinMetadata` fields from the RPC row columns.

3. **`lib/data/mappers/pin_mapper.dart`**
   - `toEntity` — write `source`, `sourceExternalId`, `confidence`, `legalCitation`, `legalCitationVerifiedDate`, and `userModified` **from `pin.metadata`** instead of hardcoding `source: 'user'`.
   - `fromEntity` — read those columns back into `PinMetadata`.
   - `toCachedEntity` — now inherits the fix (it delegates to `toEntity`); the stale "callers should overwrite source" comment is removed.

4. **`lib/data/mappers/supabase_pin_mapper.dart`** — carry the same five fields DTO↔domain so `MyPinsSync` round-trips them (user pins stay `'user'`/null; harmless and consistent).

**Design note:** provenance lives on `PinMetadata` (not a new value object) because it already holds origin/audit data (`createdBy`, `createdAt`, `votes`). Keeping it together avoids a parallel object threaded through the same call sites.

---

## §2 — The caveat (pin provenance block)

### Trigger

The block renders when `pin.metadata.source != 'user'`. User-created pins are unchanged.

### Content

Phrased around **origin**, never the current status, so it stays coherent even after a community member edits the pin (see §4):

- **Always:** the legal citation + verified date, plus a "verify locally" hedge.
  > *This location was auto-classified from public records ([source]) under [legal_citation] (verified [date]). Laws and posted signage change — verify locally before relying on this.*
- **Escalated for `confidence == 'medium'` / UNCERTAIN** (the OSM bars):
  > *This venue may restrict carry under [legal_citation], but we could not confirm it meets the legal threshold. Treat as uncertain and verify locally.*

A small helper maps `(source, confidence)` → the copy and a visual treatment (e.g. an amber info banner; stronger wording/icon for medium). `source` codes map to friendly labels (`nces` → "school records (NCES)", `gsa` → "federal property (GSA)", `osm` → "OpenStreetMap", etc.).

### Wiring

`PinDialog` (`lib/presentation/widgets/pin_dialog.dart`) gains optional provenance params (`source`, `confidence`, `legalCitation`, `legalCitationVerifiedDate`, `sourceExternalId`). The tap path already produces a domain `Pin` (read from local DB via `fromEntity`), so once §1 lands, `map_screen.dart` passes `pin.metadata.*` into the dialog. No new data fetch.

---

## §3 — ODbL attribution (two surfaces)

### 3a. Per-pin OSM credit (folds into the §2 block)

For `source == 'osm'` pins, the provenance block appends:
> *© OpenStreetMap contributors (ODbL).*

with a tappable deep link to `https://www.openstreetmap.org/{source_external_id}` — `source_external_id` is `node/<id>` / `way/<id>` / `relation/<id>` (verified: e.g. `node/10015332611`), which maps directly onto the OSM URL path. Guest-reachable since anyone can tap a pin.

### 3b. Global About/Legal screen

New screen `lib/presentation/screens/about_legal_screen.dart`:
- OpenStreetMap contributors credit + ODbL license link + the public `odbl-dumps` bucket URL (the derived-database dump).
- MapTiler basemap credit.
- App version line.

Reached by **everyone** via a new **always-visible map attribution badge** — a small `Positioned` "© OSM · MapTiler" label at a bottom corner of the map in `map_screen.dart` (standard map-attribution UX; visible to guests, who today have no menu). Tapping it pushes the About/Legal screen. The screen is also linked from `SettingsScreen` for signed-in users.

---

## §4 — Behavior under community edits

This is the crowd-edit interaction, resolved against existing infrastructure:

- **Importer never overwrites a user-edited pin** — already implemented. The `set_user_modified` trigger (008) sets `user_modified=true` on any non-`service_role` UPDATE; the importer's diff stage (`importer/importer/stages/diff.py:51-53`) buckets `user_modified` rows as **SKIP**. No Stage A work. *(The importer writes as `service_role`, which the trigger excludes, so its own updates never set the flag.)*
- **The caveat persists through edits — an edit is not a legal confirmation.** A user fixing a name has not verified the statute. They also *cannot* alter `source`/`confidence`/`legal_citation` (008 §8 REVOKEs UPDATE on those from `authenticated`), so the pin stays demonstrably system-derived and the `source`-keyed trigger still fires.
- **Status-change coherence:** a user may flip a system NO_GUN → ALLOWED (status is editable and the change sticks via §4 protection). Because the §2 copy is phrased around origin (not current status), it remains coherent ("was auto-classified … verify locally") rather than contradicting a user-corrected status.
- **No `user_modified` on the client.** The RPC does not return it and the caveat does not need it. Acknowledging edits in-UI ("edited by a community member") is deferred (would require an RPC/migration change).

---

## §5 — Testing

- **Domain:** `PinMetadata` new fields, `copyWith`, JSON round-trip, equality/hashCode.
- **Mappers:** `PinMapper` round-trip preserves all five provenance fields; an explicit regression test that `toEntity`/`toCachedEntity` preserves a non-`'user'` source (proves the hardcoded-`'user'` bug is fixed). `SupabasePinMapper` round-trip.
- **Parser:** `GetPinsInViewRow.parse` populates provenance from a representative RPC row.
- **Widget:** `PinDialog` shows the block for a system pin and hides it for a user pin; escalated copy appears for `confidence == 'medium'`; the OSM credit + deep link appears only for `source == 'osm'`.
- **Screen/UI:** About/Legal screen smoke test; the map attribution badge is present and navigates.

Target counts follow the project's existing coverage rules (domain/mappers 100%).

---

## §6 — Release

Ship §1–§3 together as **v0.7.0** (minor bump from v0.6.0) via the existing GIT_FLOW (`release/v*` → TestFlight + Play Internal → promote with a `v*.*.*` tag). After the public-store release, **wait for adoption** before Stage B's Task 7 (the prod apply) runs — per the parent rollout spec's hard gate.

## §7 — Open questions (for the plan)

- Exact friendly-label strings per `source` code.
- Visual treatment of the caveat block (banner color/icon) and whether the OSM link opens in-app webview vs external browser.
- Map attribution badge exact placement/styling vs the existing MapLibre attribution control (avoid duplication).

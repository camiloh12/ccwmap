# Market-Driven Recommendations Design

**Date:** 2026-05-02
**Status:** Draft — to be split into per-feature implementation plans

## Background

May 2026 competitive market research surfaced a corrected strategic picture:

- **Posted!** is the dominant incumbent (~18k anti-gun + ~13k pro-2A pins, $0.99 paid, 4.6 stars) but visibly calcified — last marketing update ~2019.
- **Texas3006.com** shut down in early 2026 citing privacy-compliance debt. Its full ~32k-pin dataset was inherited by **TX Carry Compass** (Pablo Fernandez, iOS, launched 2026-03-25, 1 rating, no marketing footprint).
- Texas is **~7%** of the national permit-holder population (1.5M of 21.46M per CPRC 2024) — not the 25-30% earlier framing claimed. Florida (~11.5%) is the largest single state.
- Texas signage is, however, **legally distinctive** — Penal Code 30.05/30.06/30.07/51% require specific statutory wording, 1-inch block letters, English+Spanish placement at every entrance. Non-compliant "No Guns" signs carry zero criminal weight for LTC holders. Only TX, KS, IL share this "exact-language-or-meaningless" regime. So Texas matters disproportionately to a *signage-mapping* app for legal-regime reasons, not market-size reasons.
- Validated patterns that worked in this niche: photo-of-sign attachment (trust-defining), "legal reference" framing (survives Apple review + reduces review-bombing), one-time purchase or free (subscription pivots destroy trust), pro-2A friendly listings alongside no-gun, freshness signals on stale pins, anonymous browse + auth-required write.
- Validated obstacles that killed competitors: solo-dev burnout + privacy-compliance debt (Texas3006), App Store firearm policy, cold-start data density, political review-bombing, lifetime-purchase → subscription betrayal.

The honest GTM is **national crowd-sourced density with photos and freshness as differentiators against Posted!**, treating Texas-specific signage as table-stakes, not the wedge.

## Scope

This spec covers eight recommendations from the May 2026 research, ordered by leverage. Each section is intentionally **plan-able independently** — no feature here depends on another being shipped first. The plan author is free to sequence them differently, but cross-feature dependencies are called out explicitly in each section's "Dependencies" line.

Out of scope for this spec: voting/thumbs gamification (researched and rejected — Conceal Friendly tried it without breakout); subscription monetization (rejected — CCW/ryan.ccw cautionary tale); insurance-bundle plays (capital-intensive, regulated).

## Constraints (apply to all features)

- Solo-dev sustainability — every feature must be sized so a single operator can run it indefinitely. Texas3006's death from compliance debt is a reference case.
- Apple App Store review — framing must lean "legal compliance / safety," never politicized.
- Anonymous browse, auth-required write — already implemented; do not regress.
- Offline-first remains the architectural default; sync via SyncManager + sync_queue.
- Schema migrations bump `AppDatabase.schemaVersion` in `lib/data/database/database.dart` and add an `onUpgrade` branch.
- Supabase migrations in `supabase/migrations/` follow the existing numbered convention.
- All new domain models, mappers, and validators must be 100% unit-tested (per `docs/dev/TESTING_GUIDELINES.md`).

---

## Feature 1 — Photo-of-Sign Attachment

**Leverage:** Highest. Trust-defining differentiator vs. Posted! and TX Carry Compass. A pin without a photo is a rumor; a pin with a photo of the placard is evidence.

**Why this matters now:** USA Carry / TexasCHL forum threads explicitly call out photos as the trust-defining feature. Posted!'s lack of consistent photos is one of the few things the older competitor isn't already doing well. TX Carry Compass inherited Texas3006's photo set but only had ~12 photos approved at the time of launch.

### User-facing behavior

- When creating or editing a pin, the user can attach exactly one photo (camera capture or gallery pick).
- Photos are optional — pins can still be created without one.
- Pin detail dialog displays the photo (if present) with a tap-to-zoom modal.
- A "verified by photo" badge appears on pin markers in the map list view to signal data quality at a glance.
- Editing a pin allows replacing or removing the photo.
- When a pin is deleted, its photo is deleted from remote storage on next sync.

### Technical scope

- `PinMetadata.photoUri` already exists as a `String?` field (see `lib/domain/models/pin_metadata.dart:6`) and is wired through Drift (`database.dart:28`) — verify the full read/write path is intact.
- New: Supabase Storage bucket `pin-photos` with RLS policies (any authenticated user can upload to their own folder; anyone can read).
- New: `lib/data/datasources/photo_storage_client.dart` — thin Supabase Storage wrapper.
- New: `lib/data/repositories/photo_repository_impl.dart` + interface — coordinates camera/gallery → resize → strip EXIF → upload → return URL.
- Modified: pin create/edit dialog widgets to include a photo picker affordance.
- Modified: pin marker layer to render a "verified" badge when `photoUri != null`.
- Pub dependencies: `image_picker` (already implicit candidate), `image` (resize/strip EXIF). Verify version compatibility with Flutter 3.41.7.
- Web build: photo upload supported but degraded UX (gallery only, no camera). Document explicitly.

### Open design questions (resolve before plan)

1. **EXIF GPS verification.** Reject upload if photo's EXIF lat/lng > 60m from pin coordinates? Or soft-warn and let user confirm? *Privacy implication:* if we keep EXIF for verification, we must strip it before public storage.
2. **Strip-then-verify ordering.** Verify EXIF GPS client-side before strip → upload only stripped image. Confirm this is the design.
3. **Storage cost trajectory.** Supabase free tier is 1GB. At 500KB resized photo × N pins, we fund ~2,000 photos for free. Define the cost trigger that forces a paid tier and document the projection.
4. **Moderation.** Three options: (a) every photo through queue before publishing, (b) auto-publish + reactive moderation via existing `pin_reports`, (c) sample-based queue. Solo-dev sustainability favors (b).
5. **Image dimensions.** Target max-edge 1280px? 1600px? Document.
6. **Failure UX.** If upload fails after pin is already saved locally, what's the recovery path? Retry queue? Mark pin as photo-pending?
7. **Web upload.** Does web build allow upload, or read-only? If allowed, pure browser File API, no native picker.
8. **Photo deletion semantics.** When pin is deleted, when is photo deleted? Immediately on delete-sync? Retention period?

### Acceptance criteria

- A signed-in user on Android can create a pin, attach a photo, and see it on the pin's detail dialog after sync.
- A second device signed into a different account sees the photo after sync.
- Deleting the pin removes the photo from Supabase Storage within one sync cycle.
- Web build either supports gallery upload or shows a clear "photos not supported on web — use mobile" message.
- Test coverage: photo repository 100%, EXIF utility 100%, dialog widget smoke test.

**Effort:** Medium. Largest-by-volume of the listed features.
**Dependencies:** None. Should ship before #2 because freshness UX assumes photos exist.

---

## Feature 2 — Freshness Signals & Report-Stale Flow

**Leverage:** High. When competing on national crowd density, stale data is the hidden killer. Posted!'s biggest weakness is that no pin shows a "last verified" date. TX Carry Compass calls this "freshness signals."

**Why this matters now:** Repositioning to national crowd-density GTM (since Texas wedge weakened) makes data-quality signaling more important than feature breadth.

### User-facing behavior

- Every pin in the detail dialog shows a "last verified: N months ago" line.
- Pins not verified in 18 months render with a faded marker color and a "verify?" badge.
- Users can tap "Confirm still accurate" on any pin to update its `lastVerified` timestamp.
- Users can tap "Report as outdated" — extends the existing `pin_reports` flow with a new report category.
- A report that an existing pin is outdated does NOT remove it; it flags it for the next viewer to verify.

### Technical scope

- New: `PinMetadata.lastVerified: DateTime?` field. When null, fall back to `createdAt`.
- Schema migration: add `lastVerified` integer (ms-since-epoch) column to `pins` table; bump `schemaVersion` to 3.
- Supabase migration: add `last_verified TIMESTAMPTZ` column with default `created_at` for backfill; trigger updates `last_modified` on `last_verified` change.
- Domain: `Pin.confirmAccurate()` returns a new Pin with `lastVerified = now()` and `lastModified = now()`.
- Mapper updates: entity ↔ domain ↔ DTO all carry `lastVerified`.
- Existing `pin_reports` table (from SP-2) — add an `outdated` value to the report category enum or as a free-text reason; pick whichever the existing schema supports without migration. Confirm by reading `supabase/migrations/`.
- UI: pin detail dialog adds two buttons ("Confirm accurate" / "Report outdated") and a freshness line.
- Map layer: 18-month-old pins get a CSS-equivalent fade (e.g., 50% opacity).

### Open design questions (resolve before plan)

1. **Threshold.** 18 months as the staleness cutoff — is that right? Survey forum threads for sentiment.
2. **Confirm-accurate auth.** Requires sign-in (consistent with write-requires-auth) or anonymous (low friction)? Recommend sign-in.
3. **Map-layer fade implementation.** GeoJSON property → expression in MapLibre paint properties? Confirm the MapLibre Flutter SDK supports the needed expression.
4. **Backfill.** When migration runs, set `lastVerified = createdAt` for all existing pins. Confirm.
5. **Report category for "outdated".** Reuse existing enum or add new value? Implication for moderation-email Edge Function.

### Acceptance criteria

- A pin created today shows "verified today."
- After advancing system clock 18 months in test, the same pin renders faded and shows the "verify?" badge.
- "Confirm accurate" updates `lastVerified` and the badge disappears.
- "Report outdated" submits a row to `pin_reports` and surfaces in the moderation-email digest (existing flow).
- Test coverage: domain logic 100%, threshold computation 100%, schema migration tested with a v2→v3 fixture.

**Effort:** Small-to-medium. Mostly schema + UI, small surface area.
**Dependencies:** None directly, but UX is more compelling shipped after Feature 1 (photos give users something to verify against).

---

## Feature 3 — `GUN_FRIENDLY` Status

**Leverage:** Medium-high. Doubles standalone value: app becomes useful for finding supportive businesses, not just avoiding bad ones. Posted!'s "13k pro-2A alternatives" is half its value prop and explicitly weakest in their dataset.

**Why this matters now:** Cross-state GTM benefits from a both-sides directory. Single-sided directories die per the research.

### User-facing behavior

- New marker color (suggest blue or green-with-icon) for `GUN_FRIENDLY` pins.
- Status cycle in `next()` extended: ALLOWED → UNCERTAIN → NO_GUN → GUN_FRIENDLY → ALLOWED.
- Pin filter UI gains a fourth checkbox.
- A `GUN_FRIENDLY` pin does NOT require a `restrictionTag` (the existing NO_GUN-requires-tag rule does not apply).

### Technical scope

- `PinStatus` enum (`lib/domain/models/pin_status.dart:1`) gains `GUN_FRIENDLY` as the 4th value (colorCode 3).
- Update `displayName`, `next()`, `fromColorCode()`.
- `Pin` constructor business rule unchanged — only NO_GUN requires a restriction tag.
- Marker rendering in `lib/presentation/screens/map_screen.dart` — add color mapping for code 3.
- Pin dialog widgets — extend status selector to four options.
- Filter UI — add fourth toggle.
- Tests — extend `pin_status_test.dart`, `pin_test.dart`, mapper tests.
- No schema migration needed — `status` is already an integer column with no enum constraint at DB level.
- Supabase: confirm no CHECK constraint on `status` that bounds it to 0-2. If there is, drop it.

### Open design questions (resolve before plan)

1. **Color choice.** Existing palette is red/yellow/green for NO_GUN/UNCERTAIN/ALLOWED. GUN_FRIENDLY needs to be visually distinct. Blue? Gold-star overlay on the green?
2. **`next()` cycle ordering.** Above suggests inserting after NO_GUN — confirm with UX intent. Alternative: ALLOWED → GUN_FRIENDLY → UNCERTAIN → NO_GUN.
3. **Existing pin migration.** No data migration needed (existing pins keep their status), but document this in the plan.

### Acceptance criteria

- Cycling through pin statuses on long-press reaches `GUN_FRIENDLY`.
- Map renders the new status with a distinct color.
- Filter toggle shows/hides `GUN_FRIENDLY` pins.
- Sync round-trips a `GUN_FRIENDLY` pin between two devices.
- Test coverage: enum 100%, mapper 100%, dialog smoke test.

**Effort:** Small.
**Dependencies:** None.

---

## Feature 4 — Texas Restriction Tags (30.05 / 30.06 / 30.07 / 51%)

**Leverage:** Medium. Table-stakes for serious Texas users, not the GTM wedge (since wedge thesis weakened). Worth shipping because the existing `RestrictionTag` enum supports adding values without schema changes.

**Why this matters now:** Texas's signage regime is legally distinctive — non-compliant signs are unenforceable. A pin tagged generically as "Private Property" loses critical legal information that a Texas LTC holder needs.

### User-facing behavior

- When the user is creating a NO_GUN pin AND the pin location is within Texas state boundaries, the restriction-tag picker offers the four Texas-specific tags as a separate group.
- Tag names: "Texas 30.05 (Trespass Notice)", "Texas 30.06 (LTC Concealed)", "Texas 30.07 (LTC Open)", "Texas 51% (Alcohol)".
- Outside Texas, these tags are not offered.
- Existing pins with generic `PRIVATE_PROPERTY` tag are unaffected.

### Technical scope

- `RestrictionTag` enum (`lib/domain/models/restriction_tag.dart:1`) gains four new values: `TX_30_05`, `TX_30_06`, `TX_30_07`, `TX_51_PERCENT`.
- Update `displayName` for each.
- New: `lib/domain/validators/state_boundary_validator.dart` (or extend existing `location_validator.dart`) with a `isInTexas(lat, lng)` method using a coarse bounding box (Texas: lat 25.84–36.50, lng -106.65 to -93.51).
- Pin dialog widgets — when status is NO_GUN AND location is in Texas, show the TX tag group above the generic group.
- No DB schema changes — `restriction_tag` is already a nullable text column.
- Mapper handling — the generic mapper just persists the string `name`, so new enum values flow through without changes.

### Open design questions (resolve before plan)

1. **Bounding box vs. polygon.** Bounding box includes a sliver of OK / NM / LA / AR. Acceptable for v1 (the TX tags simply don't apply in those slivers, and existing US-boundary check covers the larger geography). If precision matters, ship the polygon later.
2. **In-pin display.** Should a TX-tagged pin show the statutory text in the detail dialog? Helpful for users; legal-disclaimer-implication review needed.
3. **Marketing.** Do we make a noise about "Texas LTC compliant" in the App Store description, or quietly ship?

### Acceptance criteria

- A user creating a NO_GUN pin in Austin sees the Texas tag group in the picker.
- A user creating a NO_GUN pin in Denver does not.
- An existing pin with `PRIVATE_PROPERTY` tag continues to display correctly.
- Test coverage: enum extension 100%, validator 100%, dialog widget smoke test.

**Effort:** Small.
**Dependencies:** None.

---

## Feature 5 — Sustainable Solo-Dev Architecture Audit (Doc)

**Leverage:** High meta-value, low implementation cost. Texas3006 died from compliance/operational debt. Codifying constraints prevents drift.

**Why this matters now:** Adding photo storage, freshness signals, and (later) geofence alerts each adds operational surface area. The audit doc is the gate that prevents accumulating Texas3006-style debt.

### Deliverable

A new file `docs/dev/SOLO_DEV_CONSTRAINTS.md` capturing:

1. **Cost ceilings** — monthly Supabase + Resend + Apple/Play developer fees with current trajectory and trigger thresholds for paid-tier upgrade.
2. **Storage rules** — never store photos in Postgres; always Supabase Storage. Document max retention, max size per upload, total quota.
3. **PII inventory** — what user data we hold (auth email, signed-in user ID on pins), retention, deletion-account flow reference.
4. **Moderation throughput budget** — how many reports per week one moderator (the user) can handle. Inform feature design (e.g., favor reactive moderation over upfront queues).
5. **External dependencies** — third-party services used and what happens if any goes dark (MapTiler, Supabase, Resend).
6. **"Don't add" list** — features explicitly rejected and why (subscription model, ads, voting, insurance bundles).
7. **Compliance-debt tripwire** — list of conditions that would force a privacy-related rewrite (e.g., adding photo upload triggers EXIF-strip + retention review).

### Acceptance criteria

- Doc exists, is referenced from CLAUDE.md and README, and is reviewed before any new feature that adds operational surface area.

**Effort:** Small (doc only).
**Dependencies:** None — should ship first or in parallel with any of the code features.

---

## Feature 6 — Geofence Proximity Alerts

**Leverage:** Medium. Repeated forum mentions as "killer feature on long road trips." Carry Alerts and Texas3006 both shipped it. Heavy lift relative to the others — defer until photo + freshness ship.

**Why this matters now:** Differentiator vs. Posted!, but only after the data-quality story (photos + freshness) is established.

### User-facing behavior

- Settings screen gains a "Proximity Alerts" section — opt-in, off by default.
- When enabled, the app uses background location to monitor proximity to NO_GUN pins.
- When the user enters a configurable radius (default 50m) of a NO_GUN pin, fire a local notification with the pin name and restriction tag.
- Per-pin cooldown (default 1 hour) prevents repeat-fire on the same pin.
- Daily cap (default 3 alerts/day) prevents notification fatigue.
- Settings allow tuning radius (25m–200m), cooldown (15m–24h), daily cap (1–10).
- Initial release uses `whenInUse` location only — full background `always` permission added in a follow-up.

### Technical scope

- Pub dependencies: `flutter_local_notifications`, a geofence package (evaluate `geofencing_api`, `flutter_geofence`, or platform-channel direct).
- New: `lib/data/services/geofence_service.dart` — registers/deregisters geofences as pins load.
- New: `lib/presentation/screens/settings_screen.dart` (or extend existing) — alerts section.
- New: `lib/data/repositories/notification_preferences_repository.dart` — persisted via shared_preferences or Drift.
- iOS: `Info.plist` adds `NSLocationWhenInUseUsageDescription` (already present?), `NSLocationAlwaysAndWhenInUseUsageDescription` (only when feature ships at "always"), `UIBackgroundModes` for location.
- Android: `AndroidManifest.xml` adds `ACCESS_BACKGROUND_LOCATION` and `POST_NOTIFICATIONS`. Permission request flow for Android 13+ POST_NOTIFICATIONS.
- Web: feature is unavailable; settings UI hides on web.

### Open design questions (resolve before plan)

1. **Geofence package selection.** Native iOS region monitoring caps at 20 simultaneous regions per app. Android has higher limits but battery cost. Strategy: register only the N closest NO_GUN pins to user's current location, refresh on significant location change. Defines a "rolling geofence" pattern. Confirm package supports this.
2. **`whenInUse` vs `always`.** Initial release uses `whenInUse` only — alerts only fire when app is foreground or recently backgrounded. Document this is degraded UX.
3. **NO_GUN-only or all statuses.** Initial release alerts on NO_GUN only. GUN_FRIENDLY alerts as a v2.
4. **iOS background-task budget.** Apple's app-lifecycle changes (UIScene + background-task throttling) — review for impact.
5. **Battery messaging.** Settings UI must include a battery-impact note; lacking this is a Texas3006 review pain-point.
6. **Per-pin opt-out.** Should a user be able to silence alerts for a specific pin (e.g., their workplace)? Defer to v2.

### Acceptance criteria

- User enables alerts in settings.
- User walks within 50m of a NO_GUN pin → notification fires within 30s.
- Walking past the same pin again within 1h → no second notification.
- After 3 alerts in a day → no further alerts until midnight local time.
- Disabling alerts deregisters all geofences within one app cycle.
- Test coverage: notification preferences repo 100%, geofence service unit-tested with mocked platform calls.

**Effort:** Medium-large.
**Dependencies:** None hard, but UX is most useful after Features 1–4 are in. Schedule last.

---

## Feature 7 — Reciprocity Overlay (Public-Domain Data)

**Leverage:** Medium-low. Lets CCW Map substitute for a second app install (USCCA, Workman CCW). But repositioning to national-crowd-density GTM makes this less central than the data-quality features.

**Why this matters now:** Captures the user who arrives looking for "a CCW app" — the category leader is reciprocity, not GFZ mapping. Adding reciprocity makes CCW Map a single-app substitute for the install they were going to make anyway. Reciprocity data is public-domain (state AGs publish it) so no licensing cost.

### User-facing behavior

- New top-level "Reciprocity" tab or screen (icon: shield + map).
- User selects their issuing state (or "permitless / constitutional carry" toggle).
- App displays a US map color-coded: green = honors, yellow = partial/restrictions apply, red = does not honor.
- Tapping a state shows the specific reciprocity rules and any Texas-style signage notes.
- Data lives in a static JSON asset bundled with the app — no live API.
- An app-update cadence refreshes the data; users see a "data current as of YYYY-MM" footer.

### Technical scope

- New: `assets/data/reciprocity.json` — flat list of {issuingState, recognizedStates, restrictions}. Source: Crime Prevention Research Center, Handgunlaw.us, state AG sites.
- New: `lib/data/datasources/reciprocity_local_source.dart` — loads + parses JSON.
- New: `lib/domain/models/reciprocity_record.dart` — domain model.
- New: `lib/presentation/screens/reciprocity_screen.dart` — US choropleth, state picker.
- Routing: add a tab/drawer entry.
- Build pipeline: `assets/data/` declared in `pubspec.yaml`.
- Optional: a maintenance script to regenerate JSON from a structured source.

### Open design questions (resolve before plan)

1. **Choropleth widget choice.** SVG-based (flutter_svg + custom paint) vs. MapLibre with a US-states geojson layer. MapLibre keeps the rendering stack singular.
2. **Disclaimer.** "Not legal advice" footer; legal review on wording.
3. **Update cadence.** Quarterly app-bundle refresh? Push static asset via Supabase Storage + version check? Bundle-with-app is simpler and avoids runtime dependency.
4. **Reciprocity-only competitors are paid** (USCCA $30+/mo). We're free. Does that warrant a "supports CCW Map" donation prompt? Defer.
5. **Does this conflict with App Store framing?** Reciprocity apps like USCCA are accepted; framing as "legal information" is safe.

### Acceptance criteria

- User opens reciprocity screen, picks Texas as issuing state, sees a colored US map.
- Tapping Florida shows reciprocity status for a Texas LTC holder.
- Static data source loads under 200ms on a mid-range Android device.
- Disclaimer and "data current as of" footer always visible.
- Test coverage: data source 100%, model 100%, UI smoke test.

**Effort:** Medium.
**Dependencies:** None.

---

## Feature 8 — Store-Listing Copy Revision

**Leverage:** Low effort, real impact. Reduces App Store review risk and political review-bombing.

**Why this matters now:** Posted! has held 4.6 stars across a decade with carefully neutral copy. Politicized framing visibly hurt Gun Free Zone (mostly negative reviews). The current store listing should be audited against this pattern.

### Deliverable

A revised set of store-listing copy for both Apple App Store and Google Play, plus Markdown checklist of "do / don't" phrasings, saved to `store-assets/STORE_LISTING_COPY.md`.

Lead phrasings:
- "Stay legally compliant when you carry."
- "Know before you go."
- "Plan trips with confidence."
- Mention specifically: offline-first, free, no ads, no tracking, anonymous browsing.

Avoid:
- Politicized language ("anti-gun," "the left," "constitutional rights" as marketing claims).
- Absolutist monetization claims ("free forever," "no ads ever") — see existing memory `feedback_no_absolutist_monetization_claims.md`.
- Claims about specific legal outcomes ("avoid arrest," "stay out of jail").

### Acceptance criteria

- Doc exists, references the validated patterns from research, and is applied to both store listings on next release.
- Apple App Store keywords field is reviewed for political terms and adjusted.

**Effort:** Small (doc + listing edits).
**Dependencies:** None.

---

## Sequencing recommendation

This is a recommendation only — the implementer is free to reorder.

1. **Feature 5 (Constraints doc)** — gates everything else; small.
2. **Feature 8 (Store copy)** — small; ships independently of release cadence.
3. **Feature 3 (`GUN_FRIENDLY` status)** — small; quick win that visibly improves the app.
4. **Feature 4 (Texas tags)** — small; quick win for Texas users.
5. **Feature 1 (Photos)** — medium; requires brainstorming pass on the open questions.
6. **Feature 2 (Freshness signals)** — small-to-medium; best UX after photos exist.
7. **Feature 7 (Reciprocity overlay)** — medium; broadens GTM but doesn't improve existing UX.
8. **Feature 6 (Geofence alerts)** — medium-large; defer until data-quality story is established.

## What is NOT in this spec

- Voting, thumbs-up/down, or other gamification (rejected).
- Any subscription monetization (rejected).
- Insurance/membership tie-in (rejected — capital-intensive, regulated).
- Broad `always`-location alerts (initial geofence release is `whenInUse` only).
- Server-side photo moderation pipeline beyond extending existing `pin_reports`.
- Multi-photo per pin (single-photo only for v1).
- Pin commenting / notes from other users (existing `notes` field is creator-only).

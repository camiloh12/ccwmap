# Apple App Store listing

> Paste these into App Store Connect → App Information / Pricing & Availability / Version-specific fields.

## Name (max 30 chars)
> CCW Map: Concealed Carry

`24 chars`

## Subtitle (max 30 chars)
> Crowd-sourced GFZ map

`21 chars`

## Promotional text (max 170 chars — editable without app review)
> Free, ad-free map of where you can and can't legally carry. New: tap a posted business to mark it in 3 taps. No tracking. Built by a CCW permit holder.

`152 chars`

## Description (max 4000 chars)

```
CCW Map is a free, crowd-sourced map of gun-free zones across the United States.
Concealed-carry permit holders mark restricted places — federal property, schools,
posted businesses, secure airport areas — and everyone benefits.

No ads. No tracking. No account required to view the map.

KEY FEATURES

• Crowd-sourced gun-free-zone map covering all 50 states
• Three-color carry status: green (allowed), yellow (uncertain), red (no carry)
• Detailed restriction tags: federal, state/local government, K-12, airport, posted business
• Works offline — caches the map and your nearby pins
• Tap any point of interest to mark it
• US-boundary validated
• Optional account for adding pins; viewing requires no account

WHO IT'S FOR

• CCW / concealed-carry permit holders looking up sensitive places before traveling
• New permit holders learning the rules in their state
• Carriers in states with complex sensitive-place laws (CA, NY, NJ, IL, MA)
• Texas LTC holders tracking 30.06 / 30.07 / 51% signs
• Anyone who wants to know whether a business is posted before walking in

HOW IT WORKS

1. Open the app — no account needed
2. Browse the map; pins are color-coded by carry status
3. Tap a pin to see the restriction details
4. Sign in to add or correct a pin

PRIVACY

• No analytics SDKs. No ad pixels. No third-party trackers.
• No location history collection.
• No selling user data — there is no user data to sell.
• Account is only required to add or edit pins.

STATE COVERAGE

Handles federal and state restriction categories: GFSZA, 18 USC 930 federal facilities,
Texas 30.06 / 30.07 / 51%, California PC 626.9 + SB 2 sensitive places, New York CCIA,
Illinois 430 ILCS 66/65, Florida 790.06(12), plus airport secure areas, state/local
government property, K-12 schools, federal courthouses.

WHAT THIS APP IS NOT

• Not legal advice. Always confirm posted signage on site.
• Not affiliated with any government agency or political organization.

FREE TODAY

No ads, no premium tier, no in-app purchases. No current plans to monetize.
If costs ever outgrow what one developer can absorb, donations and grants
come first. Selling user data is not on the table.

Built by a CCW permit holder. Feedback: camilo@kyberneticlabs.com
```

`~1,900 chars` — App Store first-paragraph display is ~3 lines on iPhone, so the lead matters most.

## Keywords field (max 100 chars, comma-separated, no spaces)
```
concealed,carry,gun,firearm,permit,reciprocity,30.06,gfsz,zone,handgun,pistol,2a,ltc,ccw
```
`97 chars`

> Notes:
> - No plurals (algorithm matches stems).
> - No words that already appear in title or subtitle (Apple deprioritizes duplicates).
> - "ccw" goes here even though it's in the title — Apple's algorithm has flip-flopped on this; safer to include.

## Categories
- Primary: **Navigation**
- Secondary: **Reference**

## Age rating
- 17+ if your reviewer flags firearms content (most likely outcome)
- 12+ achievable if the description is purely navigational; document the case if you want to argue for 12+

## Screenshots (10 slots per device size)

Required device sizes (as of 2026):
- 6.7" iPhone (iPhone 14/15/16 Pro Max) — 1290×2796
- 6.5" iPhone (legacy) — 1242×2688 or 1284×2778
- 5.5" iPhone (legacy, optional but recommended) — 1242×2208
- 12.9" iPad Pro — 2048×2732 (required if app supports iPad)

Captions (same as Play, with one extra slot for App Store's longer slate):
1. "Find gun-free zones, anywhere"
2. "Tap a pin. Know why."
3. "3 taps to mark a posted business"
4. "Status, color-coded"
5. "Works offline"
6. "State-specific tags built in"
7. "No ads. No tracking."
8. "All 50 states, crowd-sourced"
9. "POI tap-detection on iOS"
10. "Free for every permit holder"

## App Preview video (optional, 15–30 seconds)
Use the 45-second demo video, trim to 15s. Adds 20%+ conversion in most categories.

## What's New (max 4000 chars per release)
Lead with the user-facing change, not the changelog. Example for v0.4.0:

```
New in 0.4.0
• You can now report problem pins directly from the pin detail
• Settings → Delete Account flow added (type-DELETE confirmation)
• 60-character cap on pin names so listings stay readable
• Block users whose pins you don't trust
• Faster POI tap detection on iOS
• Bug fixes and stability improvements
```

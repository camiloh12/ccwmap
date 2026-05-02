# r/CCW launch post

Post Tuesday or Wednesday, 8–10 AM ET. **Reply to every comment within 6 hours of posting.** Use the asset-pack demo GIF if the sub allows embedded images; otherwise link to it.

---

**Title:**
> I built a free, no-ads, no-tracking map of gun-free zones — looking for feedback before I add features

**Body:**

Hey r/CCW,

I'm a CCW holder and software developer. After {{insert founder-story moment in 1–2 sentences — e.g., "almost walking past a 30.06 sign in a parking lot before I noticed it"}}, I got tired of looking up sensitive-place rules every time I went somewhere new. I built **CCW Map** for myself first, and now it's live and free for anyone who wants it.

**What it does**
- Map view with crowd-sourced pins for gun-free zones (federal property, schools, posted businesses, secure airport areas, etc.)
- Three-color status: green (allowed), yellow (uncertain), red (no carry)
- Restriction tags so you know *why* a place is marked (federal, 30.06, school zone, etc.)
- Works offline — caches the map and your nearby pins
- Tap a POI to mark it; tap an existing pin to see details

**What it doesn't do**
- No ads today. Not planned. If hosting ever outgrows the free tier, I'll be open about whatever change is needed before making it.
- No tracking. No analytics SDKs, no ad pixels.
- No account required to view the map. (Account only needed to add or edit pins, so we can revoke abusers.)
- No selling user data. Not on the table.

**Where I'd appreciate feedback**
1. The status/restriction-tag taxonomy — does it cover the cases you actually encounter?
2. The flow for marking a posted business when you're standing in the parking lot — is it fast enough?
3. What's missing that would make you reach for it instead of Googling?

**Links**
- Play: https://play.google.com/store/apps/details?id=com.ccwmap.app&utm_source=reddit_ccw
- iOS: https://apps.apple.com/us/app/ccw-map/id6761668100?utm_source=reddit_ccw
- Source / issues: {{GitHub URL or "happy to share if useful"}}

Stack: Flutter, Supabase backend, MapLibre tiles. I'll be in the comments all morning answering anything — including the hard "but how do I know your data is right?" questions.

Thanks for taking a look.

— Camilo

---

## Comment-response cheat sheet (prep before posting)

**"Why should I trust your data?"**
> Honest answer: don't, until it earns it. The pins are crowd-sourced, last-modified is timestamped, and any authenticated user can correct a wrong pin. The map is a starting point, not legal advice — always confirm posted signage on site.

**"What's your business model? How do you pay for hosting?"**
> Free Supabase tier covers it today. No current plans to monetize. If usage outgrows what I can personally absorb, the first levers I'd reach for are donations or a 2A-aligned grant. I won't promise "never ads" — but selling user data and user-hostile dark patterns aren't on the table, and any change will be announced openly before it ships.

**"This is a honeypot for ATF / Bloomberg / [enemy of the day]"**
> No accounts needed to view the map, no analytics SDKs, the data is the same data that gets posted publicly on doors. The threat model here is about as low as a CCW-relevant app can be made.

**"How do you handle abusive pins (e.g., someone marking my house)?"**
> Pins are bound to map POIs and US-boundary-validated. Reports and per-user blocks are built in; abuse is reviewed and removed. We can't prevent every bad pin from going up, but we can make removal fast.

**"Why not Android-only / iOS-only / web?"**
> All three. Web is dev-mode only right now; Play and App Store are live.

**"Why crowd-sourced and not authoritative state-by-state data?"**
> The authoritative data doesn't fully exist or stay current — sensitive-places rules change, businesses post and unpost signs, federal facilities get added. Crowd-sourcing is the only way to keep up. The trade-off is accuracy noise, which we mitigate with timestamps and rapid correction.

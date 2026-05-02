# CCW Map Marketing Implementation Plan

**Status:** Draft v1
**Owner:** Camilo Hurtado
**Created:** 2026-04-30
**Budget:** $0
**Constraint:** Most major ad networks (Meta, Google, X) prohibit firearms-related promotion, so the plan is built around earned/owned channels only.

---

## Phase 0 — Asset Pack & Tracking (Week 1, ~6 hours total)

Every channel below needs the same inputs. Build them once.

### 0.1 — Marketing asset pack (3 hrs)
Create a folder `marketing-assets/` with:
- **Logo** (PNG transparent, 1024×1024 + 256×256)
- **6 screenshots**, captioned in-image: (1) map with mixed pins, (2) red pin detail with restriction tag, (3) green pin detail, (4) create-pin flow, (5) status cycling, (6) "find a gun-free zone near you" hero
- **15-second demo GIF** (under 5 MB) — record with ScreenToGif (free, Windows). Show: open app → tap POI → cycle status → save. No audio, no narration.
- **45-second demo video** (MP4) — same flow, narrated. Use OBS (free).
- **One-line pitch** (≤140 chars): "Free, crowd-sourced map of where you can and can't legally carry — works offline, built by a permit holder."
- **One-paragraph pitch** (≤500 chars).
- **Founder story** (3 paragraphs): why you built it, the problem, why crowd-sourced.
- **Direct app store links** (Play + iOS) + a unified link via Linktree (free) or your domain.

### 0.2 — Landing page (2 hrs)
You currently use a GitHub Pages auth callback. Stand up a real marketing page at the same domain root (`https://camiloh12.github.io/ccwmap/`):
- Hero: pitch + two store badges
- 3 screenshots
- Demo GIF
- "How it works" (3 bullets)
- FAQ: privacy, anonymity, data sources, who maintains
- Footer: support email (camilo@kyberneticlabs.com), GitHub link, EULA/privacy
- A single email-capture field tied to a free service (Buttondown free tier, or just a `mailto:`)

Use a free template — Tailwind UI's open templates, or a single-page Astro starter. ~150 lines of HTML.

### 0.3 — Tracking sheet (30 min)
One Google Sheet, three tabs:
- **Outreach log**: date | channel | contact | status | response | install attribution
- **Install tracking**: weekly Play Console + App Store Connect installs, by source where attributable (use UTMs on every external link)
- **Content calendar**: planned posts/emails/blog pitches with dates

Set up UTM links for every channel: `?utm_source=reddit_ccw&utm_medium=post&utm_campaign=launch` etc. Use Bitly free tier or just the raw query string — store console can't read UTMs but your landing page analytics can (use Plausible free trial or self-hosted Umami).

### 0.4 — Baseline analytics (30 min)
- Confirm you have **Play Console** install/uninstall reporting set up
- Confirm **App Store Connect** analytics enabled
- Add a free privacy-respecting analytics pixel to the landing page (Plausible / Umami)
- Note current 7-day install baseline so you can measure lift

---

## Phase 1 — Tier 1 (Week 1–2)

### Strategy 1 — Reddit r/CCW post (highest single lever)

**Objective:** 500–5,000 installs from one well-executed post.

**Time:** 4 hours (2 hrs prep, 2 hrs day-of engagement).

**Prereqs:** Asset pack done. Reddit account with **at least 30 days of age and ~100 comment karma** — r/CCW auto-removes new accounts. If yours is too new, spend 2 weeks commenting genuinely in the sub first. Do not buy karma.

**Steps:**
1. **Read the rules.** r/CCW has specific self-promo rules — usually a "Self-Promo Saturday" or a mod-approval requirement. Check sidebar + wiki.
2. **Message the mods 3 days before posting.** Short note: "Hi mods, I'm an independent dev and CCW holder. I built a free, no-ads, no-tracking app for marking gun-free zones. I'd like to share it with the community on [day] — happy to follow whatever format you prefer." Wait for go-ahead. This dramatically reduces removal risk.
3. **Post timing:** Tuesday or Wednesday, 8–10 AM Eastern. Avoid weekends (lower engagement, more mod backlog).
4. **Post format:**
   - **Title:** "I built a free crowd-sourced map of gun-free zones — looking for feedback before I add features"
   - **Body** (use this skeleton):
     ```
     Hey r/CCW,

     [1 paragraph: who you are, why you built it — your real story]

     What it does:
     - [3 bullets]

     What it doesn't do:
     - No ads, no tracking, no account required to view
     - [other anti-features that build trust]

     I'd really like feedback on:
     - [3 specific questions — not "is it good"]

     Play: [link]
     iOS: [link]
     Source/issues: [github link if open]

     Happy to answer anything.
     ```
   - Embed the demo GIF directly if the sub allows it.
5. **Day-of engagement:** Reply to *every* comment within the first 6 hours. This is the single biggest determinant of whether the post climbs. Be humble, take criticism, log feature requests publicly.
6. **Don't:** drop links and disappear, argue with critics, brag about installs, post the same thing in r/guns or r/Firearms within the same week (cross-posting is detected).

**Metrics to track:**
- Upvotes, comments, post position 6h/24h/72h
- Landing page sessions from `utm_source=reddit_ccw`
- Install delta vs baseline (Play Console day-over-day)
- Feature requests logged → triage as GitHub issues

**Pitfalls:**
- Posting from a stale/throwaway account → auto-removal
- Sounding like a marketer ("Excited to launch...") → instant downvote
- Not replying to the negative comments → kills momentum
- Forgetting UTMs → can't attribute the install spike

---

### Strategy 2 — State-specific subreddit posts

**Objective:** 50–300 installs per state subreddit; 1,000+ cumulative across 8–10 subs.

**Time:** 6 hours total (~30 min per sub).

**Prereqs:** r/CCW post is at least 1 week old (avoid cross-post detection).

**Subs to target, ordered by ICP density:**
1. r/CAguns (~80k) — strict laws, high engagement
2. r/NYguns (~25k)
3. r/NJGuns (~30k)
4. r/MassGuns (~10k)
5. r/IllinoisGuns / r/ChicagoGuns
6. r/FloridaGuns (~30k)
7. r/Texas_Guns / r/Texas_CCW
8. r/Colorado_guns
9. r/PAguns
10. r/WAGuns

**Steps per sub:**
1. Read sidebar rules. Some require mod approval; some forbid all self-promo.
2. **Tailor the post** — generic copy-paste gets removed. For each state, mention 2 specific local quirks:
   - CA: "supports tracking GFSZA-style 1000-ft school radii"
   - NY: "Bruen-era sensitive places marked"
   - TX: "30.06 / 30.07 sign distinction in restriction tags"
3. Use the same skeleton as r/CCW but lead with the state-relevant feature.
4. Stagger posts: **one sub per day max**. Reddit's anti-spam tooling watches for burst patterns.
5. Engage every comment within 6 hours.

**Metrics:** Same UTMs, one per sub: `utm_source=reddit_caguns` etc.

**Pitfalls:**
- Identical posts across subs → shadowban
- Posting in non-firearms state subs (r/California) — they'll remove or flame you
- Posting before the laws/features actually match the state — credibility collapses on first comment

---

### Strategy 3 — App Store Optimization (ASO)

**Objective:** 10–30% lift in organic store search installs (ongoing, compounds).

**Time:** 6 hours initial + 1 hour/month.

**Prereqs:** None.

**Steps:**

**A. Keyword research (2 hrs)**
- Free tools: AppFollow free tier, AppTweak free trial, ASOmobile free tier, Sensor Tower free.
- Manually search these in both stores and note rank/competitors:
  - "concealed carry"
  - "CCW"
  - "gun free zone"
  - "carry map"
  - "where can I carry"
  - "[state] carry laws"
  - "30.06 sign" (TX-specific, very high intent)
  - "reciprocity map"
- Build a target list of 15–20 keywords, ranked by (search volume) × (your shot at top 10).

**B. Listing optimization (Play Store) (1 hr)**
- **Title (50 chars):** "CCW Map: Concealed Carry Zones"
- **Short description (80 chars):** "Crowd-sourced map of where you can and can't legally carry. Free. Offline."
- **Long description (4000 chars):** front-load top 5 keywords in first 250 chars. Repeat each target keyword 3–5x naturally throughout. Use bullet points for features.
- **Screenshots:** 8 slots — use all 8. First 3 are what 90% of users see. Caption each in-image.
- **Feature graphic:** 1024×500 with logo + tagline.

**C. Listing optimization (App Store) (1 hr)**
- **Title (30 chars):** "CCW Map: Concealed Carry"
- **Subtitle (30 chars):** "Crowd-sourced GFZ map"
- **Keywords field (100 chars):** comma-separated, no spaces, no plurals (the algorithm matches stems): `concealed,carry,gun,firearm,permit,reciprocity,30.06,gfsz,zone,handgun,pistol,2a`
- **Promotional text (170 chars):** changes without app review — use it for seasonal pushes.
- **Screenshots:** 10 slots. Different sizes per device. Use Figma free + a screenshot generator (e.g., previewed.app free tier).

**D. Reviews bootstrap (1 hr)**
- Email 20 friends/family/range buddies with the app links. Ask for honest reviews — don't script them, that violates store policies and reviews-with-identical-language get nuked.
- Add an in-app "Rate" prompt (use `in_app_review` package) gated to: app opened ≥5 times, ≥2 days since first open, no prior prompt in 60 days.

**E. Monthly iteration (1 hr/month)**
- Pull keyword ranks. Swap underperforming keywords. A/B test screenshots via Play Console's experiments tool (free, built in).

**Metrics:**
- Keyword rank (track top 10 in a sheet)
- Store listing conversion rate (Play Console: "Store performance")
- Organic vs referral install split

**Pitfalls:**
- Keyword stuffing in title/description → store rejection
- Identical-text fake reviews → review removal + account flag
- Skipping screenshot captions → 30%+ conversion hit
- Forgetting the Play Store keyword field doesn't exist — it's all in the description

---

## Phase 2 — Tier 2 (Week 3–6)

### Strategy 4 — CCW Instructor Outreach (highest sustained ROI)

**Objective:** 20 instructors mentioning the app to ~30 students/month each = 600 warm installs/month, compounding.

**Time:** 8 hours initial + 2 hrs/month follow-up.

**Prereqs:** App is stable, has reviews, you can confidently demo it.

**Steps:**

**A. Build a lead list (3 hrs)**
- USCCA Find-an-Instructor: https://www.usconcealedcarry.com/find-an-instructor (public directory)
- NRA Instructor Locator: https://firearmtraining.nra.org
- State-by-state CCW class listings (each state DPS website typically lists certified instructors)
- Yelp/Google for "[city] concealed carry class" — pull top 5 in each of the 30 largest US metros

Target spreadsheet columns: name | business | state | email | phone | website | last contact | response | mention confirmed

Goal: **150 instructors** in the list. Realistic response rate is 5–15%, so this nets 8–25 advocates.

**B. Cold email template (1 hr to draft, then send in batches)**

```
Subject: Free tool for your CCW students — built by a permit holder

Hi [Name],

I'm Camilo, a CCW permit holder and software developer. I built a free, no-ads,
no-tracking app called CCW Map that helps carriers identify gun-free zones in
real time — exactly the kind of thing every student asks about after signing
their first permit application.

I'm not selling anything. The app is genuinely free, open-source, and I built
it because I needed it myself.

If you'd like to take a look:
- 30-second demo: [linked GIF]
- Play: [link]
- iOS: [link]

If it's useful, I'd be grateful if you mentioned it to your students. If you
have feedback or want a feature added for your state, I'll prioritize it.

Either way, thanks for what you do.

— Camilo
camilo@kyberneticlabs.com
```

**C. Send in batches (2 hrs)**
- 25 emails/day, M–Th, 9 AM local time to recipient (or 10 AM Eastern as a safe blanket).
- Use Gmail (your existing account) — don't use a sending service for cold outreach this small, deliverability is better and more personal.
- BCC yourself, not the recipient. **No bulk-merge tools** for the first 50 — type the salutation manually.

**D. Follow-up (2 hrs across weeks)**
- Day 7 follow-up to non-responders: 2 sentences, no guilt. "Just bumping this in case it got buried — happy to demo over a 10-min call if useful."
- For responders who say yes: send a printable 1-page handout (PDF, half-letter) they can hand to students. Make this in Canva free.
- For super-fans: offer a "[Instructor Name]'s recommended" badge on a future "Resources" screen.

**Metrics:**
- Open rate (use a single Bitly per recipient if you want tracking, but personal email > tracking pixels for trust)
- Reply rate
- "Mention confirmed" count
- Install spike correlated to confirmed mentions

**Pitfalls:**
- Mass-merge templates with `[FIRST_NAME]` failures → instant trash
- Following up more than twice → spammer reputation
- Writing like a marketer instead of an engineer → not your voice, instructors smell it

---

### Strategy 5 — Gun blog pitches

**Objective:** 1–3 placements, each worth 500–5,000 installs.

**Time:** 5 hours.

**Prereqs:** Asset pack, ≥50 reviews on at least one store, a real founder story.

**Targets (ranked by reach × likelihood):**

1. **The Truth About Guns** (TTAG) — high traffic, runs reader-submitted "Gear Review" pieces. Editor: Dan Zimmerman, dan@thetruthaboutguns.com (verify on site).
2. **The Reload** — Stephen Gutowski, paid Substack, very respected. Smaller list but high-converting. Pitch as a news angle ("crowd-sourced mapping movement") not a product launch.
3. **Concealed Nation** — directly your audience. Tips: tips@concealednation.org.
4. **Pew Pew Tactical** — high-traffic SEO blog. They run "best of" listicles you might fit into.
5. **Ammoland** — older audience, reliable cross-poster.
6. **Recoil** — premium brand, harder to crack but high-impact.
7. **Active Response Training** (Greg Ellifritz) — small but devoted.

**Pitch template (under 200 words):**

```
Subject: Tip — independent dev built a free GFZ map app

Hi [Editor],

I'm a CCW holder and indie developer. I built and just launched CCW Map, a
free, ad-free, crowd-sourced map of gun-free zones. It's offline-first, has
no tracking, and is currently used by [N] permit holders.

The angle I think is interesting for [outlet]:

[Pick one for the publication:]
- TTAG/Concealed Nation: a reader-built tool solving a real carry problem
- The Reload: crowd-sourced legal compliance as a 2A community response to
  Bruen-era legal complexity
- Pew Pew Tactical: addition to a "best CCW apps" listicle

Demo: [GIF]
Press kit: [landing page link]

Happy to provide a custom screenshot, do a Q&A, or write a guest post. No
embargo — write it whenever fits your editorial calendar.

— Camilo Hurtado
camilo@kyberneticlabs.com
```

**Steps:**
1. Verify each editor's email by checking 2 recent bylines + an "About" page.
2. Send 1 publication per day, M–Th. Personalize the angle paragraph each time.
3. Don't follow up before day 10. Send exactly one follow-up.
4. If picked up: send a thank-you, offer to come back with updates.

**Metrics:** placements landed, referral traffic from each, install lift in the 7 days after publication.

**Pitfalls:**
- Pitching every outlet the same week — they talk; looks desperate
- Burying the angle under feature lists — editors care about the *story*, not the product
- Not having reviews/installs to point to — wait until you have ≥50

---

### Strategy 6 — CCW podcaster outreach

**Objective:** 2–4 podcast mentions = 200–2,000 installs each.

**Time:** 4 hours.

**Targets:**
1. **Concealed Carry Podcast** (Riley Bowman, USCCA) — biggest in the niche
2. **Handgun World** (Bob Mayne)
3. **Polite Society Podcast**
4. **The CCW Guardian Podcast**
5. **Ballistic Radio**
6. **The Tactical Wire** (newsletter, not podcast, but adjacent)

**Pitch:**
- Either offer a guest spot ("happy to come on for 15 min to discuss the app + state-law fragmentation problem")
- Or just send for a free mention ("if you find it useful, a mention would mean the world")
- Send via the host's preferred contact (usually a tips@ or the show's contact form)

**Steps:** Mostly identical to blog outreach. One pitch per day, ≤6 total.

**Pitfalls:**
- Going on a podcast unprepared → wastes the channel
- Only pitching the top 2 → those are the longest replies. Cast wider.

---

### Strategy 7 — Facebook group infiltration (it's not what it sounds like)

**Objective:** 200–1,000 installs from 3–5 active groups.

**Time:** 4 hours initial + 30 min/week for 4 weeks.

**Prereqs:** Personal Facebook account at least a year old, with profile photo and some history. Brand-new accounts get auto-blocked.

**Steps:**
1. **Find groups.** Search FB for "[state] concealed carry," "[state] CCW," "[state] gun owners." Pick 5 with ≥10k members and recent activity. Examples: "Florida Concealed Carry," "Texas CHL/LTC Holders."
2. **Apply to join.** Most ask 1–3 vetting questions. Answer honestly.
3. **Lurk + contribute for 7–10 days before posting.** Like, comment on others' posts, answer state-law questions if you know the answer. Build a tiny presence so the post that mentions your app doesn't look like a hit-and-run.
4. **Post — once per group, never twice.** Format:
   ```
   I'm a permit holder and developer in [state]. I built a free no-ads tool
   for marking gun-free zones because I kept getting confused about [specific
   local example]. It's here if it's useful: [link]. Happy to answer feature
   requests in comments.
   ```
5. **Reply to every comment for 24 hours.** Disable notifications after.
6. **Don't:** post in 5 groups the same day; FB clusters posts by content fingerprint.

**Metrics:** Track per-group installs via UTM and post engagement.

**Pitfalls:**
- Posting before contributing → mod removal + ban
- Cross-posting same text → algorithmic spam flag
- Engaging in political flame wars in comments → kills credibility

---

## Phase 3 — Tier 3 (Week 7–12, compounding)

### Strategy 8 — SEO landing pages

**Objective:** 500–5,000 organic monthly visits within 6 months → 5–10% install conversion.

**Time:** 16 hours over 6 weeks (≈3 hrs/week).

**Prereqs:** Marketing landing page exists. You have some way to track unique visitors per page (Plausible/Umami).

**Page strategy — the "is X a gun-free zone" template:**

For each high-intent search, build a single page that ranks. Examples (verify search volume in Google's free Keyword Planner or Ahrefs free trial):

- "is [airport name] a gun-free zone" — 30 airports
- "30.06 vs 30.07 signs Texas"
- "California gun-free school zone law"
- "Florida CCW reciprocity map 2026"
- "states that honor [state] CCW permit"
- "concealed carry restaurant rules [state]"
- "gun free zones near me"

**Steps:**

**A. Pick 20 target queries (1 hr)**
- Use Google's autosuggest, "People also ask," and the free version of Ubersuggest.
- Filter for: ≥500 monthly searches, KD < 30 (low competition).

**B. Build the page template (2 hrs)**
- Static HTML, mobile-first, <100 KB.
- Title tag: exact-match query
- H1: exact-match query
- 600–1,200 word answer with citations to actual statutes (link to state code)
- Embedded mini-map showing relevant pins from your app
- Strong CTA: "See real-time updates in CCW Map — [store buttons]"
- Schema.org `FAQPage` markup for People-Also-Ask snippets
- One internal link to 2 sibling pages

**C. Write 20 pages (12 hrs, ~30 min each)**
- Use your existing knowledge + state law primary sources. Don't pull from copyrighted blogs.
- Have a lawyer-friend or paid Fiverr review for accuracy if discussing statute. Wrong legal info = liability + retracted rankings.
- Include a "last verified" date and a disclaimer.

**D. Get indexed (1 hr)**
- Submit `sitemap.xml` to Google Search Console (free) and Bing Webmaster Tools.
- Get one inbound link from your own social or a forum signature.

**E. Iterate (ongoing, 30 min/week)**
- Pull ranking weekly. Update underperforming pages (more depth, FAQ section, fresher data).
- After 90 days, identify top 3 by traffic — expand them to 2,000+ words.

**Metrics:** Pages indexed, queries ranked top 10, organic sessions/page, install conversion rate from these pages.

**Pitfalls:**
- Stating legal conclusions without disclaimers → liability
- AI-generated bulk content → Google's helpful-content penalty
- Building the pages on the same domain as the auth callback without clear path separation → confuses crawlers

---

### Strategy 9 — YouTube creator outreach

**Objective:** 1–2 mentions in mid-tier creator videos.

**Time:** 4 hours.

**Targets (10k–500k subs, audience-fit > size):**
- **Garand Thumb** (huge, low odds) — skip unless personal connection
- **Active Self Protection** (John Correia) — focused on real defensive scenarios; CCW Map fits "tools I use" segments
- **John Lovell / Warrior Poet Society** — political-adjacent, high CCW audience
- **Mrgunsngear**
- **Lucky Gunner Ammo** — they review gear regularly
- **MDFI Training**
- Local/state instructor channels (10k–50k subs each, much easier to reach)

**Steps:**
1. Find each channel's business email (in YouTube "About" tab).
2. Pitch with a 30-second loom video showing the app + a specific reason it fits their channel ("you do a lot of GFSZA-related content; this app shows real-time community-marked zones").
3. Don't ask for a full video review. Ask for "30 seconds in a 'tools I use' segment."
4. Offer nothing — the app is free, they don't get a kickback. Be upfront about that.

**Metrics:** placements; pre/post install lift on day-of-publish.

**Pitfalls:**
- Pitching channels with audience mismatch (e.g., 3-gun competitors don't carry concealed) → ignored
- Asking for a full review → too big a lift, declined

---

## Tracking & Metrics (Always-On)

Track weekly in your sheet:

| Metric | Where | Target by Week 4 | Target by Week 12 |
|---|---|---|---|
| Total installs (Play + iOS) | store consoles | 2× baseline | 10× baseline |
| Day-30 retention | store consoles | ≥25% | ≥35% |
| Reviews count | store consoles | 100 | 500 |
| Average rating | store consoles | ≥4.3 | ≥4.5 |
| Landing page sessions | Plausible | 500/wk | 5,000/wk |
| Outreach emails sent | sheet | 50 | 200 |
| Outreach responses | sheet | 5 | 30 |
| Confirmed instructor mentions | sheet | 5 | 25 |

If a metric is stalling, the playbook says: shift hours to whichever channel is closest to its target without exceeding it.

---

## Suggested 12-Week Sequence

| Week | Primary focus | Secondary |
|---|---|---|
| 1 | Asset pack + landing + tracking | r/CCW mod ping |
| 2 | r/CCW post + engagement | ASO listing rewrite |
| 3 | Instructor list build | First 3 state subs |
| 4 | Instructor batch 1 (50 emails) | Next 3 state subs |
| 5 | Blog pitches (3 outlets) | Instructor batch 2 (50) |
| 6 | Podcast pitches | Last state subs |
| 7 | SEO pages 1–5 | Follow-ups everywhere |
| 8 | SEO pages 6–10 | FB group lurk + post |
| 9 | SEO pages 11–15 | YouTube outreach |
| 10 | SEO pages 16–20 | Instructor batch 3 |
| 11 | ASO iteration | Press follow-ups |
| 12 | Review, double down on top channel | Plan next quarter |

---

## What to skip / kill criteria

- **Kill any channel** that produces <10 installs after 2 full execution attempts.
- **Skip TikTok / Instagram organic** — gun content is shadowbanned, ROI is near zero, and time spent is high.
- **Skip Twitter/X paid promotion** — banned for firearms even after the policy thaw.
- **Skip Product Hunt** — audience mismatch.
- **Don't build a Discord** until you have ≥1,000 active users — empty servers signal a dead project.

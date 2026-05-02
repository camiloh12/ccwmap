# Manual TODOs (steps Camilo has to do)

> Everything I could draft is in this `marketing-assets/` directory and at `docs/index.html`.
> The list below is the work that needs your hands, your accounts, or your judgment.

Group order matches recommended execution. Don't skip ahead — early TODOs unblock later ones.

---

## A. Asset pack — needed before any external outreach

- [ ] **Founder story:** Open `pitches/founder-story-draft.md` and replace the `{{...}}` placeholders with your real specific moment. Keep it under 250 words.
- [x] **Logo:** Exported to `marketing-assets/logo/ccw-map-icon-1024.png` and `ccw-map-icon-256.png`. Source was the iOS 1024 launcher icon (which `flutter_launcher_icons` generates from `assets/icon/app_icon.png`). Note: the master at `assets/icon/app_icon.png` is 512×512, so the 1024 had been upscaled by flutter_launcher_icons. If you need a sharper 1024 for high-DPI press use, redraw the icon natively at ≥2048 in Figma/Illustrator and re-run flutter_launcher_icons.
- [x] **In-app screenshots:** 4 existing Tampa-area screenshots from `store-assets/` mapped to landing-page slots. Wired into `docs/index.html` under "What you'll see" (browse map, tap-pin detail, create-pin, color-coded status). The 5th sign-in screen was skipped — it's not marketing-strong.
  - **Still needed for the stores** (separate task): captioned versions for Play Console (8 slots) and App Store Connect (10 slots per device size). Captions are listed in `aso/play-store.md` and `aso/app-store.md`. Use Figma + previewed.app free tier to add the captions in-image. The raw screenshots are uncaptioned — store listings convert better with captions overlaid.
  - **Still needed:** "Works offline" caption needs a screenshot of the app while offline (e.g., airplane-mode the device while map is cached). Currently no screenshot covers that.
- [ ] **15-second demo GIF:** record with **ScreenToGif** (free, Windows). Flow: open app → tap a POI → cycle status → save. No audio, no narration. Keep under 5 MB.
- [ ] **45-second demo MP4:** record with **OBS** (free). Same flow, with brief narration. Use this for podcast pitches and YouTube outreach.
- [ ] **Drop the demo GIF/MP4** into `docs/` (or a CDN) and update `docs/index.html` where it currently shows the `[ Demo GIF placeholder ]` block.
- [x] **Replace screenshot placeholders** in `docs/index.html` with `<img>` tags pointing at the captioned screenshots. (Done — wired 4 screenshots from `docs/screenshots/` with `<figcaption>` text captions and `alt` text. In-image text overlays for store-listing versions are still TODO under the screenshots item above.)
- [x] **Replace store-badge `href="#"` placeholders** in `docs/index.html` with the actual Play and App Store URLs. Done — also replaced `{{Play Store URL}}` / `{{App Store URL}}` placeholders across all reddit/outreach/facebook/seo templates with real URLs and per-channel UTMs (reddit_ccw, reddit_caguns, instructor_email, press, podcast, youtube, fb_{{group}}, seo). Note: Play install attribution from `&utm_source=...` is informational only — for true Play install attribution wrap Play links via Google's Play URL builder later.

---

## B. Tracking infrastructure

- [ ] **Google Sheet (3 tabs):** Outreach log | Install tracking | Content calendar. Columns are listed in `docs/marketing/IMPLEMENTATION_PLAN.md` § 0.3.
- [ ] **Plausible (or Umami) for the landing page:** sign up for the free trial / self-host Umami. Add the script tag to `docs/index.html` (just below the `<meta>` tags). Confirm pageviews show up.
- [ ] **Confirm Play Console install reporting** is set up and you can pull a daily install number.
- [ ] **Confirm App Store Connect analytics** is enabled.
- [ ] **Note your 7-day install baseline** in the Google Sheet so you can measure lift.
- [ ] **Build out UTM links** in a Bitly free account (or just hand-write them) for each channel so you can attribute installs.

---

## C. Reddit launch (week 2)

- [ ] **Verify Reddit account age + karma:** ≥30 days old, ~100 comment karma. If not, spend 2 weeks commenting genuinely in r/CCW first (not building a fake history — actually engaging).
- [ ] **Send the mod pre-message** at `reddit/ccw-mod-message.md`. Wait for go-ahead.
- [ ] **Fill in the `{{...}}` placeholders** in `reddit/ccw-launch-post.md` with: your founder-story moment, the actual store URLs, the GitHub URL or "happy to share."
- [ ] **Post Tuesday or Wednesday, 8–10 AM ET.** Block out the next 6 hours to reply to every comment.
- [ ] **Wait 7+ days** before any state-sub posts.
- [ ] **For each state sub** (`reddit/state-subs/*.md`): read sub rules, fill in placeholders, post. **One sub per day max.** Reply to comments for 6 hours after each.

---

## D. ASO — App Store Optimization (week 2, can run in parallel with Reddit)

- [ ] **Play Console:** Replace the current Main Store Listing fields with the copy from `aso/play-store.md`. Upload 8 captioned screenshots. Upload feature graphic.
- [ ] **App Store Connect:** Replace the current listing fields with the copy from `aso/app-store.md`. Upload 10 screenshots per device size. Optionally upload a 15-second App Preview video.
- [ ] **Email 20 friends/family/range buddies** asking for honest reviews. Don't script them.
- [ ] **Add `in_app_review` Flutter package and integrate** the rate-prompt:
  - Add `in_app_review: ^X.X.X` to `pubspec.yaml`
  - Gate prompt on: app opened ≥5 times AND ≥2 days since first open AND no prior prompt in 60 days
  - This is real Flutter code work — open as a separate task / branch when you get to it
- [ ] **Schedule a monthly recurring sweep** to check keyword rank and run a Play Store screenshot A/B test (Play Console → Store Performance → Experiments).

---

## E. Instructor outreach (week 3–6, the highest sustained ROI in the plan)

- [ ] **Build the lead spreadsheet.** Goal: 150 instructors. Sources:
  - USCCA Find-an-Instructor: https://www.usconcealedcarry.com/find-an-instructor
  - NRA Instructor Locator: https://firearmtraining.nra.org
  - Each state DPS website's certified-instructor list
  - Yelp/Google for "[city] concealed carry class" — top 5 in each of the 30 largest US metros
- [ ] **Render `outreach/instructor-handout.html` to PDF** (open it in Chrome → Print → Save as PDF). The two half-letter handouts on one letter sheet are designed for instructors to print and hand out.
- [x] **Generate two QR codes** — saved to `outreach/qr/android-instructor-qr.png` and `outreach/qr/ios-instructor-qr.png`. Embedded in `outreach/instructor-handout.html` (both copies on the 2-up letter sheet). Verify the encoded URLs include `utm_source=instructor_handout` if you want this channel attributable separately from `instructor_email` — re-generate at qr-code-generator.com if not.
- [ ] **Send instructor emails** in batches of 25/day, M–Th. Template at `outreach/instructor-email.md`.
- [ ] **Day-7 follow-up** to non-responders (template in same file). Single follow-up only.
- [ ] **Log every confirmed mention** in a separate sheet tab so you can correlate install spikes.

---

## F. Press outreach (week 5)

- [ ] **Verify each editor's email** by checking 2 recent bylines on their site + the "About" or "Masthead" page.
- [ ] **Build a simple press-kit page** at `docs/press/index.html`. Should include: founder story, one-paragraph pitch, demo GIF, downloadable logo (PNG + SVG), 6 hi-res screenshots. (I can draft this if you want — it wasn't in your task list but takes ~30 min.)
- [ ] **Send blog pitches** one outlet per day, M–Th. Templates at `outreach/blog-pitches.md`. Personalize the angle paragraph each time.
- [ ] **Send podcast pitches** one outlet per day, week after blog pitches. Templates at `outreach/podcast-pitches.md`.
- [ ] **Send YouTube creator pitches** one channel per day. Templates at `outreach/youtube-pitches.md`. Skip channels >500k subs unless you have a personal connection.
- [ ] **Day-10 single follow-up** to any non-responders.

---

## G. Facebook groups (week 7+)

- [ ] **Verify your personal FB account is ≥1 year old** with profile photo and history. Brand-new accounts get auto-blocked.
- [ ] **Join 5 target groups.** List in `facebook/group-post-template.md`. Answer their vetting questions honestly.
- [ ] **Lurk + contribute genuinely for 7–10 days** before posting. Like, comment, answer state-law questions where you know the answer.
- [ ] **Run the pre-post checklist** in `facebook/group-post-template.md` before each post.
- [ ] **Post one group per day, max.** Reply to every comment for 24 hours.

---

## H. SEO landing pages (week 7–12, compounding)

- [ ] **Verify search volume** for each query in `seo/target-queries.md` using Google Keyword Planner (free with a Google Ads account, no spend required) or Ubersuggest free tier.
- [ ] **Pick 20 to write.** Drop any with <500 monthly searches or KD > 30.
- [ ] **For each query, copy `seo/page-template.html`** to `docs/{{slug}}/index.html` and fill in the `{{...}}` placeholders.
- [ ] **Have legal claims reviewed** before publishing — wrong legal info is a liability AND a Google "helpful content" penalty trigger. Cheapest path: a $50 Fiverr lawyer review of all 20 pages in one batch.
- [ ] **Generate `docs/sitemap.xml`** listing all SEO pages.
- [ ] **Submit the sitemap** to:
  - Google Search Console: https://search.google.com/search-console
  - Bing Webmaster Tools: https://www.bing.com/webmasters
- [ ] **Get one inbound link** to each page (your social, a forum signature, etc.).
- [ ] **Iterate weekly:** pull rankings, update underperforming pages.

---

## I. Code work (separate from marketing — open as own branch when ready)

- [ ] **Add `in_app_review` package and rate-prompt logic** (covered in section D).
- [ ] **Optional: open-source the repo** if you decide to. Adds credibility in this community. Watch out for: leaked secrets in old commits (run gitleaks first), the existing `.env` references, and the Supabase URL/anon-key — anon-key is fine to expose, service-role key is not.
- [ ] **Optional: open a GitHub issues template** for "report a problem pin" so you can route community moderation requests.

---

## J. Things to actively NOT do

- Don't create a Discord until you have ≥1,000 active users
- Don't run TikTok / Instagram organic — gun content is shadowbanned
- Don't try paid ads on Meta / Google / X — banned for firearms
- Don't pitch Product Hunt — audience mismatch
- Don't argue politics in any comment thread, ever, regardless of who started it
- Don't follow up on outreach more than once
- Don't ask anyone to write a positive review — Apple/Google detect identical-language reviews and will nuke them all

---

## What's done that you don't have to redo

These are already drafted and ready to use:

- `docs/marketing/IMPLEMENTATION_PLAN.md` — the master strategy doc
- `docs/index.html` — marketing landing page (auth-callback redirect preserved at top of head)
- `marketing-assets/pitches/one-line.md` — primary + 3 variants
- `marketing-assets/pitches/one-paragraph.md` — primary + tighter press variant
- `marketing-assets/pitches/founder-story-draft.md` — structured, with placeholders
- `marketing-assets/reddit/ccw-mod-message.md` — pre-message for r/CCW mods
- `marketing-assets/reddit/ccw-launch-post.md` — main r/CCW post + comment-response cheat sheet
- `marketing-assets/reddit/state-subs/*.md` — 5 tailored variants (CA, TX, NY, NJ, FL, IL)
- `marketing-assets/aso/play-store.md` — full Play Console listing copy
- `marketing-assets/aso/app-store.md` — full App Store Connect listing copy
- `marketing-assets/outreach/instructor-email.md` — initial + day-7 follow-up
- `marketing-assets/outreach/instructor-handout.html` — 2-up letter sheet, print-ready
- `marketing-assets/outreach/blog-pitches.md` — 7 outlets, customized
- `marketing-assets/outreach/podcast-pitches.md` — 6 shows
- `marketing-assets/outreach/youtube-pitches.md` — 5 channels + 1 mid-tier template
- `marketing-assets/facebook/group-post-template.md` — template + checklist + comment responses
- `marketing-assets/seo/target-queries.md` — 20 starter queries with priority order
- `marketing-assets/seo/page-template.html` — reusable HTML page template with FAQ schema

# Facebook group post template

**Hard rules:**
- Personal FB account ≥1 year old, with profile photo and history
- Lurk + contribute genuinely for **7–10 days** before posting
- Post in **one group per day max** — FB clusters near-duplicate content
- One post per group, never twice
- Reply to every comment for the first 24 hours
- Don't engage politically in comments — kills credibility instantly

---

## Pre-post checklist

- [ ] Group has ≥10k members
- [ ] Group has had ≥3 posts in the past week (active, not dead)
- [ ] You've answered ≥2 questions from other members in the group in the past week
- [ ] You've liked / commented genuinely on ≥5 unrelated posts
- [ ] Group rules don't explicitly forbid promo (re-read pinned post)
- [ ] Today is Tue, Wed, or Thu (best engagement)
- [ ] You're posting between 8 AM and 11 AM in the group's timezone
- [ ] You've added the right UTM (`?utm_source=fb_{{groupname}}`)

## Post template

```
I'm a permit holder and developer in {{your state}}. I built a free no-ads
tool for marking gun-free zones because {{specific local moment — e.g., "I kept
forgetting whether the Costco on 121 was posted, and the answer changes every
time someone retires the sign"}}.

It's called CCW Map. View-only, no account needed. Sign in to add or correct
pins. No ads, no tracking, no premium tier — built it for myself first.

https://play.google.com/store/apps/details?id=com.ccwmap.app&utm_source=fb_{{group}}
https://apps.apple.com/us/app/ccw-map/id6761668100?utm_source=fb_{{group}}

Happy to answer feature requests in comments. If you carry in {{state}} and there
are sensitive-place rules I'm not handling well, tell me and I'll fix it this week.
```

## Common comment types and responses

**"Looks like an ad."**
> Fair concern. Not selling anything, no ads today, no premium tier. No current plans to monetize. If hosting ever outgrows what one dev can pay for, I'll be open about whatever change is needed before making it. Selling user data isn't on the table. Ask for whatever proof would help.

**"How do I know your data is right?"**
> Honest answer: don't, until it earns it. Crowd-sourced, last-modified timestamped, anyone authenticated can correct any pin. Always confirm signage on site — the map is a starting point, not legal advice.

**"What do you do with my data?"**
> No data collected beyond what's needed to authenticate (email if you sign up to add pins). No analytics SDKs, no ad pixels, no third-party trackers. App location is used to center the map; that's it. No location history stored.

**"Is this open source?"**
> {{If yes: link.}} {{If no but considering: "Not yet, considering it. Holding off until I'm sure I can support contributors well."}}

**"Why didn't you put this in a state-specific app?"**
> The sensitive-place rules vary state by state but the tool to track them shouldn't have to. The app handles state-specific tags (TX 30.06/30.07, NY CCIA, CA SB 2, etc.) — happy to add more if I'm missing yours.

**Politically charged comment ("typical liberal/conservative tracking app", etc.)**
> Don't engage. Like the comment if it's mild, ignore if hostile. The only winning move is not playing.

## Recommended target groups (verify activity before posting)

1. **Florida Concealed Carry** — large, active, light moderation
2. **Texas LTC Holders** — active, slight bias toward older carriers
3. **California Concealed Carry** — small but extremely high-intent (CA carriers are starved for tools)
4. **Carolina Carry** (NC + SC) — mid-size, friendly to indie tools
5. **Pennsylvania Firearm Owners Association group** — active, tools-friendly
6. **Arizona Open / Concealed Carry** — light moderation, easy share

Skip:
- Any group with "MAGA" or specific political branding in the name (community attracts flame wars, not installs)
- Any group with <5k members (won't move the needle)
- Groups where last-3-posts are all from the same poster (dead, just admin posting to themselves)

# Instructor cold email

> Send 25/day, M–Th, 9 AM in recipient's local time (or 10 AM ET as a safe blanket). Type each salutation manually for the first 50.

---

## Initial outreach

**Subject:** Free tool for your CCW students — built by a permit holder

```
Hi {{First Name}},

I'm Camilo Hurtado, a CCW permit holder and software developer. I built a free,
no-ads, no-tracking app called CCW Map that helps carriers identify gun-free zones
in real time — exactly the kind of thing every student asks about after signing
their first permit application.

I'm not selling anything. The app is genuinely free, no premium tier planned, and
I built it because I needed it myself.

If you'd like to take a look:
- 30-second demo: {{demo GIF URL}}
- Play: https://play.google.com/store/apps/details?id=com.ccwmap.app&utm_source=instructor_email
- iOS: https://apps.apple.com/us/app/ccw-map/id6761668100?utm_source=instructor_email

If it's useful, I'd be grateful if you mentioned it to your students. If you have
feedback or want a feature added for {{state, e.g., "Texas — like a 30.06 sign
distinction"}}, I'll prioritize it.

Either way, thanks for what you do.

— Camilo
camilo@kyberneticlabs.com
```

## Day-7 follow-up (only if no reply)

**Subject:** Re: Free tool for your CCW students

```
Hi {{First Name}},

Just bumping this in case it got buried — happy to walk you through it on a
10-minute call if useful, or send a printable handout you can give students
after class.

— Camilo
```

## Reply flow

**If they say "send the handout"** — send the PDF (`marketing-assets/outreach/instructor-handout.html` rendered to PDF; see that file).

**If they say "I have a feature request"** — log it in your GitHub issues immediately. Reply within 24 hours with either an ETA or "added to the list, here's where it sits in priority."

**If they say "I can't / won't"** — thank them, ask if they know other instructors who might benefit. (Referrals from instructors are warm.)

**If they say yes** — within 48 hours:
- Send the handout
- Add a "Thanks to {{Name}}" line in your `marketing-assets/instructor-supporters.md` log
- Ask if you can quote them on the landing page (one-liner testimonial)

## Pitfalls

- Don't use mail-merge for the first 50 — typos in `{{First Name}}` are instant deletes
- Don't follow up more than once
- Don't send PDFs as attachments on cold outreach — Gmail/Outlook flag PDF attachments from new senders. Link to the handout instead.
- Don't pitch instructors who are themselves selling competing apps. Quick check: search their site for "app" or "membership."

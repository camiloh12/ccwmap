# 15-second demo GIF — full walkthrough

Companion to `marketing-assets/TODO.md` § A: "15-second demo GIF: record with ScreenToGif (free, Windows). Flow: open app → tap a POI → cycle status → save. No audio, no narration. Keep under 5 MB."

## 1. Install ScreenToGif

- Download from https://www.screentogif.com → "Portable" zip (no install, no admin rights needed)
- Extract anywhere (e.g. `C:\Tools\ScreenToGif\`)
- Run `ScreenToGif.exe`

Or via winget: `winget install NickeManarin.ScreenToGif`

## 2. Pick what you're recording

You want the GIF to look like a phone, so record from a phone-shaped surface. Two good options:

**Option A — physical Android device via scrcpy (recommended).** Real phone, real fingers, looks authentic. From your Windows laptop:
```
winget install Genymobile.scrcpy
scrcpy --max-size 720
```
Plug phone in via USB, enable USB debugging. A scrcpy window appears mirroring your phone. Resize it to a tight phone aspect (e.g. ~360×780).

**Option B — Android emulator** (`flutter emulators --launch <id>`) at Pixel-class resolution. Fine, but the navigation gestures look less natural.

**Don't record the web build for this.** Landing-page visitors need to see "this is a phone app."

Either way, before you start recording: open the app, sign in if needed, pan the map to **a Tampa-area location with several visible pins** (matches the in-app screenshots already in `docs/screenshots/`). Then close and reopen the app so the recording can start with a cold-ish open.

## 3. Configure ScreenToGif for size

In ScreenToGif main window → click **Recorder**. A resizable selection frame appears.

Before recording, click the **gear icon** (top-right of recorder) and set:
- **Frame rate:** `15 fps` — plenty for UI, halves filesize vs 30fps
- **Capture frequency:** `Per Frame` (more accurate than time-based)

Drag/resize the recorder frame so it sits **exactly** over the scrcpy/emulator window. Don't include desktop chrome.

## 4. Record the 15 seconds

Hit **Record** (or F7), then perform the flow with deliberate pauses so each step reads on screen:

| Time | Action | Notes |
|---|---|---|
| 0–3s | App is open, map visible with pins | Let viewer's eye settle on the colored pins |
| 3–5s | Tap a POI label (a named place, e.g. "Starbucks") | The create-pin dialog opens with the POI name pre-filled |
| 5–10s | Tap the status button to cycle: green → yellow → red | Pause ~1s on each color so the change registers |
| 10–12s | Tap "Save" | Dialog dismisses |
| 12–15s | New pin appears on the map in its final color | This is the payoff frame — don't cut it short |

Hit **Stop** (F8) when done. The editor opens automatically.

## 5. Trim and optimize in the editor

The editor shows every captured frame in a strip at the bottom.

1. **Trim to 15s exactly:**
   - Select extra frames at the start/end (Shift-click the strip)
   - Right-click → Delete (or press `Del`)
   - Total frame count target: ~225 (15s × 15fps)

2. **Resize down if file is too big:**
   - `Image` tab → `Resize` → set width to 480px (height auto-calculates). 480px wide is plenty for a landing-page hero GIF.

3. **Reduce colors (biggest filesize lever):**
   - When you save, you'll get to pick this. Skip for now.

## 6. Export

`File` tab → `Save as` → choose **Gif** encoder.

Recommended settings:
- **Encoder:** `ScreenToGif 2.0` (the built-in one is fine; `FFmpeg` gives smaller files but requires you to bundle ffmpeg)
- **Quality / Color quantization:** start at `30` (range 1–30, lower = smaller file with more dithering). If the GIF looks acceptable at 30, try 15 to halve size.
- **Looped:** yes, infinite

Save to `docs/demo-15s.gif`.

## 7. Verify under 5 MB

```
ls -lh docs/demo-15s.gif
```

If it's over 5 MB:
1. First lever: drop colors to 64 in the export dialog
2. Second lever: resize to 360px wide
3. Third lever: drop to 12 fps in the editor (`Image` → `Reduce framerate`)
4. Last resort: trim to 12 seconds

If it's still over after all four, switch to MP4 + a `<video>` tag instead of GIF — modern landing pages prefer this anyway. ScreenToGif → `Save as Video`. Then in `docs/index.html`:
```html
<video autoplay muted loop playsinline src="demo-15s.mp4"></video>
```

## 8. Wire it into the landing page

Find the placeholder in `docs/index.html`:
```
[ Demo GIF placeholder ]
```
Replace with:
```html
<img src="demo-15s.gif" alt="CCW Map demo: tap a place, mark its CCW status, save." loading="lazy">
```

Open `docs/index.html` in a browser to confirm it plays.

---

**Common gotchas:**
- ScreenToGif portable doesn't auto-update — re-download in 6 months
- If scrcpy window resizes mid-recording, your frame slips. Lock the window before hitting Record.
- Don't record while signed in as your dev/test account if usernames or emails are visible — check the create-pin dialog UI before recording.

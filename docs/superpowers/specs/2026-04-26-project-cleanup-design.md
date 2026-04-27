# Project Cleanup Design

**Date:** 2026-04-26  
**Status:** Approved

## Goal

Declutter the repository root and make `docs/` internally consistent by separating GitHub Pages web content from developer documentation.

## Constraints

- GitHub Pages is configured to serve from `/docs`. The HTML web files must remain at the `docs/` root level.
- `CLAUDE.md`, `README.md`, `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `ccwmap.iml`, and `flutter_launcher_icons_debug.yaml` must stay at the repository root (tooling or convention requirements).
- Historical superpowers plans/specs are left unchanged — they are archival records of completed work, not living docs.

## Target Structure

```
ccwmap/
├── CLAUDE.md
├── README.md
├── pubspec.yaml / pubspec.lock
├── analysis_options.yaml
├── flutter_launcher_icons_debug.yaml
├── ccwmap.iml
│
├── store-assets/                        # new top-level folder for store screenshots
│   ├── screenshot-1.png
│   ├── screenshot-2.png
│   ├── screenshot-3.png
│   ├── screenshot-4.png
│   ├── screenshot-5.png
│   ├── ipad-screenshot-1.png
│   ├── ipad-screenshot-2.png
│   ├── ipad-screenshot-3.png
│   ├── ipad-screenshot-4.png
│   └── ipad-screenshot-5.png
│
├── docs/                                # GitHub Pages root — web content only at this level
│   ├── index.html
│   ├── privacy-policy.html
│   ├── data-deletion.html
│   ├── auth/
│   ├── terms/
│   │
│   ├── dev/                             # new subfolder — all developer markdown docs
│   │   ├── FUNCTIONAL_SPEC.md
│   │   ├── IMPLEMENTATION_PLAN.md
│   │   ├── IOS_BUILD_STATUS.md
│   │   ├── ITERATION_8_NOTES.md
│   │   ├── TESTING_GUIDELINES.md
│   │   ├── APP_STORE_DEPLOYMENT.md
│   │   ├── PLAY_STORE_DEPLOYMENT.md
│   │   ├── DEPLOY.md
│   │   ├── GIT_FLOW.md
│   │   ├── MODERATION.md
│   │   └── RELEASE_NOTES.md
│   │
│   └── superpowers/
│       ├── plans/
│       │   ├── 2026-04-12-ios-poi-tap-fix.md    # renamed from ios-poi-tap-fix-plan.md
│       │   └── (existing plans unchanged)
│       └── specs/
│           └── (existing specs unchanged)
│
├── assets/screenshots/                  # unchanged — organized Play Store assets
├── release_notes/                       # unchanged — Play Store delivery format
└── supabase/                            # unchanged
```

## File Moves

### From root → `docs/dev/`
- `FUNCTIONAL_SPEC.md`
- `IMPLEMENTATION_PLAN.md`
- `IOS_BUILD_STATUS.md`
- `ITERATION_8_NOTES.md`
- `TESTING_GUIDELINES.md`
- `APP_STORE_DEPLOYMENT.md`
- `PLAY_STORE_DEPLOYMENT.md`

### From `docs/` → `docs/dev/`
- `DEPLOY.md`
- `GIT_FLOW.md`
- `MODERATION.md`
- `RELEASE_NOTES.md`

### Rename + move
- `docs/ios-poi-tap-fix-plan.md` → `docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md`

### From root → `store-assets/`
- `screenshot-1.png` through `screenshot-5.png`
- `ipad-screenshot-1.png` through `ipad-screenshot-5.png`

### `.gitignore` + delete
- `pub_upgrade.log`

## Reference Updates

Active references only. Historical superpowers plans are left unchanged.

| File | Old reference | New reference |
|---|---|---|
| `CLAUDE.md` | `FUNCTIONAL_SPEC.md` | `docs/dev/FUNCTIONAL_SPEC.md` |
| `CLAUDE.md` | `docs/GIT_FLOW.md` | `docs/dev/GIT_FLOW.md` |
| `CLAUDE.md` | `docs/MODERATION.md` | `docs/dev/MODERATION.md` |
| `CLAUDE.md` | `docs/DEPLOY.md` | `docs/dev/DEPLOY.md` |
| `README.md` | `IMPLEMENTATION_PLAN.md` (×2) | `docs/dev/IMPLEMENTATION_PLAN.md` |
| `docs/dev/FUNCTIONAL_SPEC.md` | `screenshot-1.png` through `screenshot-4.png` (multiple occurrences) | `store-assets/screenshot-N.png` |
| `docs/dev/IMPLEMENTATION_PLAN.md` | `TESTING_GUIDELINES.md` | `docs/dev/TESTING_GUIDELINES.md` |
| `lib/data/datasources/maptiler_geocoding_client.dart` | `docs/ios-poi-tap-fix-plan.md` | `docs/superpowers/plans/2026-04-12-ios-poi-tap-fix.md` |

## What Does Not Change

- `assets/screenshots/` — already organized, correctly referenced in `PLAY_STORE_DEPLOYMENT.md`
- `release_notes/` — Play Store delivery format, correct location
- `supabase/` — untouched
- All superpowers plans and specs (historical records)
- GitHub Pages web content (`index.html`, `privacy-policy.html`, `data-deletion.html`, `auth/`, `terms/`)

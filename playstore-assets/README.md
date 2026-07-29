# PlayHub — Google Play Store assets

Everything you need to submit the Play Store listing. The finished, upload-ready
images are in **`screenshots/`** and **`graphics/`**. The source HTML that
generates them is in **`ui-assets/`** — edit those and re-render if you want to
change anything.

## What's here

| File | Size | Play field |
|---|---|---|
| `graphics/icon.png` | 512 × 512 | **App icon** (Store listing) |
| `graphics/feature-graphic.png` | 1024 × 500 | **Feature graphic** (Store listing) |
| `screenshots/01-dashboard.png` | 1080 × 1920 | Phone screenshot 1 — Owner dashboard |
| `screenshots/02-students.png` | 1080 × 1920 | Phone screenshot 2 — Students |
| `screenshots/03-batches.png` | 1080 × 1920 | Phone screenshot 3 — Batches & schedule |
| `screenshots/04-attendance.png` | 1080 × 1920 | Phone screenshot 4 — Attendance |
| `screenshots/05-performance.png` | 1080 × 1920 | Phone screenshot 5 — Performance |
| `screenshots/06-billing.png` | 1080 × 1920 | Phone screenshot 6 — Billing & payments |
| `screenshots/07-parent.png` | 1080 × 1920 | Phone screenshot 7 — Parent view |
| `screenshots/08-announcements.png` | 1080 × 1920 | Phone screenshot 8 — Announcements |
| `screenshots/tablet-7/*.png` (8) | 1200 × 1920 | **7-inch tablet** screenshots |
| `screenshots/tablet-10/*.png` (8) | 1600 × 2560 | **10-inch tablet** screenshots |

The tablet images are the same 8 app screens presented in a device frame on a
branded background with a caption (the app is phone-first single-column, so this
truthfully shows how it looks on a tablet rather than faking a two-pane layout).
Tablet screenshots are **optional** on Play — upload them under
"7-inch tablet" and "10-inch tablet" if you want the app to feature on tablet search.

> These are **marketing mockups** built to match the app's real design system
> (colors, type, components from `apps/mobile/lib/core/design_tokens.dart`) with
> realistic sample data. They are for the store listing. Google may *separately*
> ask for real in-app screenshots during review of sensitive features — these are
> representative but not live captures.

## Google Play image requirements (met by these files)

- **App icon:** 512 × 512, 32-bit PNG. Play applies its own rounded-corner mask,
  so `icon.png` is a full-bleed square (no transparency/rounding of its own).
- **Feature graphic:** 1024 × 500, PNG or JPEG, no alpha.
- **Phone screenshots:** 2–8 required. PNG/JPEG, 16:9 or 9:16, each side
  320–3840 px. These are 1080 × 1920 (9:16) — the safe, universally-accepted size.
- Upload order in Play = the order you want them shown. Recommended:
  dashboard → students → batches → attendance → performance → billing → parent → announcements.

## Re-rendering after an edit

Edit any file in `ui-assets/` then run the render script. It uses headless
Chrome, so the output PNG is **exactly** the target pixel size regardless of your
monitor resolution (that's why you don't screenshot these by hand):

```bash
# from playstore-assets/
bash ui-assets/render.sh
```

Or one file manually (Git Bash):

```bash
"/c/Program Files/Google/Chrome/Application/chrome.exe" \
  --headless --disable-gpu --no-sandbox --hide-scrollbars \
  --force-device-scale-factor=1 --virtual-time-budget=3000 \
  --window-size=1080,1920 \
  --screenshot="screenshots/01-dashboard.png" \
  "file:///C:/Users/hp/Documents/MyProjects/playhub/playstore-assets/ui-assets/01-dashboard.html"
```

## Still owed before you can publish the listing

- **Privacy policy URL** — required by the listing and the Data Safety form; none
  exists yet. Host one and paste the URL into Play.
- **Data-deletion path** — Play requires in-app account deletion **and** a public
  deletion-request URL for apps with sign-up. Not built yet.
- Short & full description text — drafted separately (not in this folder).

#!/usr/bin/env bash
# Render all PlayHub Play Store assets to exact-size PNGs via headless Chrome.
# Output size is independent of your monitor — Chrome renders to the pixel size
# given by --window-size at scale factor 1. Run from anywhere:  bash render.sh
set -u

CHROME="/c/Program Files/Google/Chrome/Application/chrome.exe"
[ -f "$CHROME" ] || CHROME="/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"

# Resolve paths relative to this script.
HERE="$(cd "$(dirname "$0")" && pwd)"          # .../playstore-assets/ui-assets
ROOT="$(cd "$HERE/.." && pwd)"                  # .../playstore-assets
# Windows-style base for file:// URLs (C:/...)
WINBASE="$(cd "$HERE" && pwd -W 2>/dev/null || echo "$HERE")"

mkdir -p "$ROOT/screenshots" "$ROOT/graphics"

render () { # $1=html  $2=out.png  $3=W,H
  "$CHROME" --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --force-device-scale-factor=1 --virtual-time-budget=3000 \
    --window-size="$3" --screenshot="$2" "file:///$WINBASE/$1" 2>/dev/null
  echo "  -> $2"
}

echo "Rendering phone screenshots (1080x1920)…"
for f in 01-dashboard 02-students 03-batches 04-attendance \
         05-performance 06-billing 07-parent 08-announcements; do
  render "$f.html" "$ROOT/screenshots/$f.png" "1080,1920"
done

echo "Rendering store graphics…"
render "feature-graphic.html" "$ROOT/graphics/feature-graphic.png" "1024,500"
render "icon.html"            "$ROOT/graphics/icon.png"            "512,512"

# Tablet screenshots: same app screens, framed, at 7-inch (1200x1920) and
# 10-inch (1600x2560). Uses tablet.html?screen=..&size=.. (real screen via iframe).
mkdir -p "$ROOT/screenshots/tablet-7" "$ROOT/screenshots/tablet-10"
echo "Rendering tablet screenshots…"
for f in 01-dashboard 02-students 03-batches 04-attendance \
         05-performance 06-billing 07-parent 08-announcements; do
  render "tablet.html?screen=$f&size=7"  "$ROOT/screenshots/tablet-7/$f.png"  "1200,1920"
  render "tablet.html?screen=$f&size=10" "$ROOT/screenshots/tablet-10/$f.png" "1600,2560"
done

echo "Done."

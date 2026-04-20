#!/usr/bin/env bash
#
# generate_icons.sh — One-command pipeline to regenerate all platform icons
# and native splash assets from the source SVG.
#
# Prerequisites:
#   brew install librsvg    # provides rsvg-convert
#
# Usage:
#   ./scripts/generate_icons.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

SVG="assets/icon/app_logo.svg"
PNG="assets/images/app_icon.png"

# ---------- 1. SVG → 1024×1024 PNG ----------
echo "▸ Rendering $SVG → $PNG (1024×1024)…"
if ! command -v rsvg-convert &>/dev/null; then
  echo "  ✗ rsvg-convert not found. Install with: brew install librsvg"
  exit 1
fi
rsvg-convert -w 1024 -h 1024 "$SVG" -o "$PNG"
echo "  ✓ $PNG generated"

# ---------- 2. Flutter Launcher Icons ----------
echo "▸ Regenerating launcher icons (Android, iOS)…"
dart run flutter_launcher_icons
echo "  ✓ Launcher icons done"

# ---------- 3. Flutter Native Splash ----------
echo "▸ Regenerating native splash assets…"
dart run flutter_native_splash:create
echo "  ✓ Native splash done"

# ---------- 4. Web icons ----------
echo "▸ Generating web icons…"
rsvg-convert -w 192 -h 192 "$SVG" -o web/icons/Icon-192.png
rsvg-convert -w 512 -h 512 "$SVG" -o web/icons/Icon-512.png
rsvg-convert -w 192 -h 192 "$SVG" -o web/icons/Icon-maskable-192.png
rsvg-convert -w 512 -h 512 "$SVG" -o web/icons/Icon-maskable-512.png
echo "  ✓ Web icons done"

# ---------- 5. macOS icons ----------
echo "▸ Generating macOS icons…"
MACOS_DIR="macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" -h "$size" "$SVG" -o "$MACOS_DIR/app_icon_${size}.png"
done
echo "  ✓ macOS icons done"

echo ""
echo "✅ All platform icons regenerated."

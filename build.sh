#!/bin/bash
# Builds ImageDrop.app next to this script. Usage:
#   ./build.sh            build only
#   ./build.sh --install  build, copy to /Applications, and launch
set -euo pipefail
cd "$(dirname "$0")"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools are required. Run:  xcode-select --install"
  exit 1
fi

APP="ImageDrop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling…"
swiftc -O main.swift -o "$APP/Contents/MacOS/ImageDrop"
cp Info.plist "$APP/Contents/Info.plist"
[[ -f AppIcon.icns ]] || ./make-icon.sh
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so macOS is happy running a locally built app.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x ImageDrop >/dev/null 2>&1 || true
  rm -rf "/Applications/$APP"
  cp -R "$APP" /Applications/
  open "/Applications/$APP"
  echo "Installed to /Applications and launched. Look for the photo icon in your menu bar."
fi

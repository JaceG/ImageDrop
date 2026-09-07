#!/bin/bash
# Regenerates AppIcon.icns from make-icon.swift. build.sh copies AppIcon.icns into the bundle.
set -euo pipefail
cd "$(dirname "$0")"
TMP="$(mktemp -d)"
swiftc -O make-icon.swift -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o AppIcon.icns
rm -rf "$TMP"
echo "Wrote AppIcon.icns"

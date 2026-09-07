#!/bin/bash
# Builds ImageDrop.app, zips it, and publishes a GitHub Release so the website's
# "Download for Mac" link (…/releases/latest/download/ImageDrop.zip) picks it up.
#   ./release.sh 1.0.0
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:?usage: ./release.sh <version>  e.g. 1.0.0}"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" Info.plist

./build.sh
rm -f ImageDrop.zip
ditto -c -k --keepParent ImageDrop.app ImageDrop.zip
echo "Zipped ImageDrop.app ($(du -h ImageDrop.zip | cut -f1))"

git add Info.plist
git commit -m "Release v$VERSION" >/dev/null 2>&1 || true
git push
gh release create "v$VERSION" ImageDrop.zip --title "ImageDrop $VERSION" --generate-notes
echo "Published v$VERSION — https://github.com/JaceG/ImageDrop/releases/latest"

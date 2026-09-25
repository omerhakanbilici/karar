#!/bin/sh
# Packs a built Karar.app into Karar.dmg in the repo root, always under this name (spec §2), with
# an Applications link to drag it onto. Refuses an app that isn't signed adhoc,runtime.
#   scripts/make-dmg.sh [path/to/Karar.app]      default: the Release build
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app=${1:-"$root/build/Build/Products/Release/Karar.app"}
[ -d "$app" ] || { echo "error: $app not found; run the Release build first" >&2; exit 1; }

codesign --verify --deep --strict "$app"
for binary in "$app" "$app/Contents/MacOS/ollaya"; do
  codesign -dv "$binary" 2>&1 | grep -q '(adhoc,runtime)' \
    || { echo "error: $binary is not signed adhoc,runtime" >&2; exit 1; }
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/Karar"
ditto "$app" "$tmp/Karar/Karar.app"
ln -s /Applications "$tmp/Karar/Applications"
dmg="$root/Karar.dmg"
rm -f "$dmg"
hdiutil create -quiet -volname Karar -srcfolder "$tmp/Karar" -format UDZO "$dmg"
hdiutil verify -quiet "$dmg"
echo "$dmg ($(du -h "$dmg" | cut -f1 | tr -d ' '))"

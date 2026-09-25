#!/bin/sh
# Downloads the pinned Ollaya release into vendor/ollaya and verifies its checksum.
set -eu
OLLAYA_VERSION=v0.5.0
OLLAYA_SHA256=70b7183e3ffcbee66f2058a16703d52363fb3d764c835cd97e0f14f97be8a8e1

root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/vendor/ollaya"
if [ -f "$dest/VERSION" ] && [ "$(cat "$dest/VERSION")" = "$OLLAYA_VERSION" ]; then
  echo "Ollaya $OLLAYA_VERSION already in vendor/ollaya"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/ollaya.tgz" \
  "https://github.com/ollaya-dev/ollaya/releases/download/$OLLAYA_VERSION/ollaya-darwin-arm64.tgz"
echo "$OLLAYA_SHA256  $tmp/ollaya.tgz" | shasum -a 256 -c -
rm -rf "$dest"
mkdir -p "$dest"
tar -xzf "$tmp/ollaya.tgz" -C "$dest"
echo "$OLLAYA_VERSION" > "$dest/VERSION"
echo "Ollaya $OLLAYA_VERSION ready in vendor/ollaya"

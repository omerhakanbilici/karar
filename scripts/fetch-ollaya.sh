#!/bin/sh
# Downloads the pinned Ollaya release into vendor/ollaya and verifies its checksum.
set -eu
OLLAYA_VERSION=v0.3.2
OLLAYA_SHA256=959aabbddde2c8c59b585933047a12a70ca7df20d503aa7ae171a38c2b29876e

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

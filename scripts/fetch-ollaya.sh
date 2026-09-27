#!/bin/sh
# Downloads the pinned Ollaya release into vendor/ollaya and verifies its checksums: the engine,
# and MLX's Metal kernels, which let laya and nli:modernbert-large run on the Apple GPU.
set -eu
OLLAYA_VERSION=v0.7.1
OLLAYA_SHA256=e0b281036611f8a074e07ce553a57916bf49c48b609601adec03531ad821942c      # ollaya-darwin-arm64.tgz
OLLAYA_MLX_SHA256=5a85d974ade710b9c3c201c73a96eb0bfdbf782d9bf0b0c970cd187f5e619e4f  # ollaya-darwin-arm64-mlx.tgz

root=$(cd "$(dirname "$0")/.." && pwd)
dest="$root/vendor/ollaya"
if [ -f "$dest/VERSION" ] && [ "$(cat "$dest/VERSION")" = "$OLLAYA_VERSION" ]; then
  echo "Ollaya $OLLAYA_VERSION already in vendor/ollaya"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
base="https://github.com/ollaya-dev/ollaya/releases/download/$OLLAYA_VERSION"
curl -fsSL -o "$tmp/ollaya.tgz" "$base/ollaya-darwin-arm64.tgz"
curl -fsSL -o "$tmp/mlx.tgz" "$base/ollaya-darwin-arm64-mlx.tgz"
printf '%s  %s\n%s  %s\n' "$OLLAYA_SHA256" "$tmp/ollaya.tgz" "$OLLAYA_MLX_SHA256" "$tmp/mlx.tgz" | shasum -a 256 -c -
rm -rf "$dest"
mkdir -p "$dest"
# Both archives share the prefix layout (bin/, lib/ollaya/, share/).
tar -xzf "$tmp/ollaya.tgz" -C "$dest"
tar -xzf "$tmp/mlx.tgz" -C "$dest"
echo "$OLLAYA_VERSION" > "$dest/VERSION"
echo "Ollaya $OLLAYA_VERSION ready in vendor/ollaya"

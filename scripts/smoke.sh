#!/bin/sh
# Real-engine smoke test (spec §6), local only: starts the ollaya inside a built Karar.app on
# 127.0.0.1:11436 with a scratch model store, pulls laya:en, runs one decide with the triage
# question set, and checks the answer's shape. Never touches ~/.ollaya. Needs jq (macOS 15+).
#   scripts/smoke.sh [path/to/Karar.app]      default: the Release build
#   KARAR_SMOKE_MODELS=<dir> keeps the store (and laya:en, ~850 MB) for the next run and the UI tests.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
app=${1:-"$root/build/Build/Products/Release/Karar.app"}
ollaya="$app/Contents/MacOS/ollaya"
[ -x "$ollaya" ] || { echo "error: $ollaya not found; build Karar first" >&2; exit 1; }
host=127.0.0.1:11436
if curl -s -m 2 -o /dev/null "http://$host/"; then echo "error: something already listens on $host" >&2; exit 1; fi

tmp=$(mktemp -d)
models=${KARAR_SMOKE_MODELS:-"$tmp/models"}
mkdir -p "$models"
OLLAYA_HOST=$host OLLAYA_MODELS=$models "$ollaya" serve > "$tmp/serve.log" 2>&1 &
pid=$!
# SIGTERM: ollaya shuts down cleanly and stops its runners (SIGKILL would orphan them).
trap 'kill $pid 2>/dev/null; wait $pid 2>/dev/null; rm -rf "$tmp"' EXIT

i=0
until curl -fs -m 1 "http://$host/" 2>/dev/null | grep -q "Ollaya is running"; do
  i=$((i + 1))
  [ $i -lt 50 ] || { echo "error: the engine did not start" >&2; cat "$tmp/serve.log" >&2; exit 1; }
  sleep 0.2
done
echo "engine: $(curl -fs "http://$host/api/version")"

# /api/pull streams NDJSON; a failure mid-stream is a line with "error" (api.md §7.6).
curl -fsN "http://$host/api/pull" -d '{"model":"laya:en"}' > "$tmp/pull.ndjson"
if grep -q '"error"' "$tmp/pull.ndjson"; then grep '"error"' "$tmp/pull.ndjson" >&2; exit 1; fi
tail -n 1 "$tmp/pull.ndjson" | grep -q '"success"' || { echo "error: the pull did not finish" >&2; exit 1; }

# The preset is spliced in verbatim: question order matters and jq would keep it anyway.
printf '{"model":"laya:en","state":"I was charged twice this month. Please refund me by Friday.","questions":%s}' \
  "$(cat "$root/Karar/Presets/triage.json")" > "$tmp/body.json"
curl -fs "http://$host/api/decide" -d @"$tmp/body.json" > "$tmp/decide.json" \
  || { echo "error: /api/decide failed" >&2; exit 1; }
jq -e '(.answers | length) == 5
  and (.answers.intent.choice | type) == "string"
  and (.answers.is_urgent.noul | type) == "number"
  and (.answers.frustration.score | type) == "number"
  and .usage.input_tokens > 0' "$tmp/decide.json" > /dev/null \
  || { echo "error: unexpected answer:" >&2; cat "$tmp/decide.json" >&2; exit 1; }
echo "smoke test passed: $(jq -c '{model, intent: .answers.intent.choice, ms: (.total_duration / 1000000 | floor)}' "$tmp/decide.json")"

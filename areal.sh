#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:-./Aerial-H264}"
mkdir -p "$OUTDIR"

# sehr schoene landschaftsvideos ca 15gb

URLS=(
  "https://a1.phobos.xxxxxx/us/r1000/000/Features/atv/AutumnResources/videos/entries.json"
  "https://a1.v2.phobos.xxxxxx.edgesuite.net/us/r1000/000/Features/atv/AutumnResources/videos/entries.json"
)

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

fetch_ok=0
for u in "${URLS[@]}"; do
  if curl -kfsSL "$u" -o "$tmp"; then
    fetch_ok=1
    break
  fi
done
[[ "$fetch_ok" -eq 1 ]] || { echo "ERROR: entries.json nicht ladbar." >&2; exit 1; }

# URLs -> Download
jq -r '.. | objects | .url? // empty' "$tmp" \
| grep -E '\.(mov|mp4)(\?.*)?$' \
| sort -u \
| while IFS= read -r url; do
    fn="${url##*/}"
    fn="${fn%%\?*}"
    wget --no-check-certificate -c -O "$OUTDIR/$fn" "$url"
  done
#chromium akzeptiert auch die mov-dateien in mp4 umbenannt
cd Aerial-H264
mv *.mov *.mp4

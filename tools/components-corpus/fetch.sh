#!/bin/bash
# Fetches the components corpus (open-source macOS apps and Apple's sample code) into a folder, read-only use:
# nothing in it is built or run. Usage: tools/components-corpus/fetch.sh <folder>
set -u
OUT="${1:?Usage: fetch.sh <folder>}"
mkdir -p "$OUT"
tail -n +2 "$(dirname "$0")/MANIFEST.tsv" | while IFS=$'\t' read -r folder url _rest; do
  [ -d "$OUT/$folder" ] && continue
  case "$url" in
    *.zip) tmp=$(mktemp -d); curl -sL "$url" -o "$tmp/s.zip" && unzip -q "$tmp/s.zip" -d "$tmp/x" && mkdir -p "$OUT/$folder" && cp -R "$tmp/x/." "$OUT/$folder/"; rm -rf "$tmp" ;;
    *) git clone -q --depth 1 "$url" "$OUT/$folder" ;;
  esac
  echo "$folder"
done

#!/usr/bin/env bash
# Serves website/ at http://localhost:8123/Songie/ (the same /Songie/ base as
# GitHub Pages, which the room page relies on). Python's server has no 404
# fallback: preview the room page at
#   http://localhost:8123/Songie/404.html?preview=/Songie/r/ABCD2345
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
ln -s "$root/website" "$dir/Songie"
echo "Serving http://localhost:${PORT:-8123}/Songie/"
cd "$dir" && python3 -m http.server "${PORT:-8123}" --bind 127.0.0.1

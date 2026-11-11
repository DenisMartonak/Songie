#!/usr/bin/env bash
# Takes the website's showcase screenshots in the real Linux app and writes
# them to website/media/showcase/ (plus showcase.json, which the home page
# reads). See docs/website.md.
#
#   tool/showcase.sh                    # every scene
#   SCENES=themes,search tool/showcase.sh
#
# The app runs against a throwaway data folder (XDG_DATA_HOME), signed out of
# everything; your own library and accounts are never opened. A window opens
# on your desktop while it records; leave it alone until it closes.
set -euo pipefail
shopt -s nullglob

root="$(cd "$(dirname "$0")/.." && pwd)"
flutter="${FLUTTER:-$HOME/development/flutter/bin/flutter}"
media="$root/website/media/showcase"
raw="$root/build/showcase"
real_db_dir="${HOME}/.local/share/songies"

data="$(mktemp -d -t showcase-XXXXXX)"
trap 'rm -rf "$data"' EXIT

# yt-dlp is a program, not data: reuse the installed copy so downloads work
# without fetching it again.
mkdir -p "$data/songies/bin"
if [[ -x "$real_db_dir/bin/yt-dlp" ]]; then
  cp "$real_db_dir/bin/yt-dlp" "$data/songies/bin/yt-dlp"
fi

# Proof afterwards that the real library wasn't touched.
real_before="$(find "$real_db_dir" -maxdepth 1 -type f -printf '%f %T@\n' 2>/dev/null | sort || true)"

rm -rf "$raw"
mkdir -p "$raw" "$media"

echo "Recording (data folder $data)..."
(
  cd "$root"
  XDG_DATA_HOME="$data" \
  SHOWCASE_OUT="$raw" \
  SHOWCASE_COVERS="$root/integration_test/showcase/covers" \
  SHOWCASE_SCENES="${SCENES:-}" \
    "$flutter" test integration_test/showcase/showcase_test.dart -d linux
)

real_after="$(find "$real_db_dir" -maxdepth 1 -type f -printf '%f %T@\n' 2>/dev/null | sort || true)"
if [[ "$real_before" != "$real_after" ]]; then
  echo "WARNING: files in $real_db_dir changed during the recording." >&2
  echo "(The real Songies may have been running; check before trusting this.)" >&2
fi

for dir in "$raw"/*/; do
  scene="$(basename "$dir")"
  rm -f "$media/$scene".* "$media/$scene"-*.webp
  i=0
  for png in "$dir"/*.png; do
    i=$((i + 1))
    ffmpeg -loglevel error -y -i "$png" -vf "scale='min(2240,iw)':-2:flags=lanczos" \
      -c:v libwebp -quality 86 "$media/$scene-$i.webp"
  done
  echo "$scene: $i screenshot(s)"
done

# showcase.json: what each scene has (merged with scenes not re-recorded).
python3 - "$media" <<'EOF'
import json, os, sys
media = sys.argv[1]
path = os.path.join(media, 'showcase.json')
try:
    scenes = {s['id']: s for s in json.load(open(path))['scenes']}
except (OSError, ValueError, KeyError):
    scenes = {}
for scene in ['themes', 'playlists', 'downloads', 'search']:
    entry = {'id': scene}
    shots = sorted(f for f in os.listdir(media) if f.startswith(f'{scene}-') and f.endswith('.webp'))
    if not shots:
        continue
    entry['shots'] = shots
    scenes[scene] = entry
json.dump({'scenes': list(scenes.values())}, open(path, 'w'), indent=2)
print(open(path).read())
EOF
du -h "$media"/* | sort -h | tail -12

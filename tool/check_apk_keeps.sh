#!/usr/bin/env bash
# Checks that R8 kept what the app reaches only by name at runtime, so a
# shrunk release APK doesn't crash where debug builds work.
#
#   tool/check_apk_keeps.sh path/to/app-release.apk
#
# Needs the Android build-tools (dexdump), found under $ANDROID_HOME or
# ~/Android/Sdk. Exits 1 naming what is missing.
set -euo pipefail

apk="$1"
sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
bt="$(ls -d "$sdk"/build-tools/* | sort -V | tail -1)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
unzip -q -o "$apk" 'classes*.dex' -d "$work"

dump() { for f in "$work"/classes*.dex; do "$bt/dexdump" "$f" 2>/dev/null; done; }

# Room makes WorkManager's database with getDeclaredConstructor(): without
# the no-argument constructor, scheduling the update check crashes at launch
# (1.5.0).
# Captured first: grep -q stops early, which pipefail would count as failing.
impl="$(dump | awk '/Class descriptor.*androidx\/work\/impl\/WorkDatabase_Impl;/{p=1}
      p && /Class descriptor/ && !/WorkDatabase_Impl;/{p=0} p')"
if ! grep -q "type *: '()V'" <<<"$impl"; then
  echo "::error::R8 removed WorkDatabase_Impl's no-argument constructor (see android/app/proguard-rules.pro)." >&2
  exit 1
fi
echo "APK keeps: ok"

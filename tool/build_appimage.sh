#!/usr/bin/env bash
# Builds songies-X.Y.Z-x86_64.AppImage from the Flutter Linux release bundle.
#
# Usage (from anywhere, after `flutter build linux --release`):
#   tool/build_appimage.sh X.Y.Z
#
# Runs on ubuntu-22.04 (CI) and on newer distros. Needs: bash, curl,
# sha256sum, ldconfig and a system libmpv (Ubuntu: apt install libmpv-dev).
#
# AppDir layout:
#   AppRun                   linux/packaging/AppRun
#   opt/songies/             the release bundle, copied unchanged (Flutter
#                            finds lib/ and data/ next to its executable)
#   usr/lib/                 libmpv and its media libraries, by linuxdeploy
#   usr/share/applications/  linux/packaging/songies.desktop
#   usr/share/icons/...      the app icon
#
# Optional environment:
#   LINUXDEPLOY, APPIMAGETOOL, APPIMAGE_RUNTIME, PATCHELF
#                     use these tool files instead of downloading the pinned
#                     releases below
#   SONGIES_TOOL_CACHE  where pinned tools are downloaded
#                       (default build/appimage/tools)
#   SONGIES_BUNDLE_DIR  the Flutter bundle (default build/linux/x64/release/bundle)
#   SONGIES_OUT_DIR     where the AppImage goes (default build/)
#   LIBMPV              the libmpv to bundle (default: found with ldconfig)
#   APPIMAGE_EXTRACT_AND_RUN  defaults to 1 so the tools run without FUSE
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 X.Y.Z" >&2
  exit 64
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="${SONGIES_BUNDLE_DIR:-$REPO_ROOT/build/linux/x64/release/bundle}"
WORK_DIR="$REPO_ROOT/build/appimage"
TOOL_CACHE="${SONGIES_TOOL_CACHE:-$WORK_DIR/tools}"
OUT_DIR="${SONGIES_OUT_DIR:-$REPO_ROOT/build}"
APPDIR="$WORK_DIR/Songies.AppDir"
OUTPUT="$OUT_DIR/songies-${VERSION}-x86_64.AppImage"
PACKAGING="$REPO_ROOT/linux/packaging"
# The app icon, 512 px (made by tool/generate_icons.py).
ICON_SRC="$PACKAGING/songies.png"

# The CI runners have no FUSE; the tools are AppImages themselves.
export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"
export ARCH=x86_64
# Distro libraries are already stripped, and linuxdeploy's bundled strip is
# too old for newer binutils sections (.relr.dyn) on current distros.
export NO_STRIP=1

# Pinned tool releases, checked by SHA-256 (from the GitHub release digests).
LINUXDEPLOY_URL="https://github.com/linuxdeploy/linuxdeploy/releases/download/1-alpha-20251107-1/linuxdeploy-x86_64.AppImage"
LINUXDEPLOY_SHA256="c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage"
APPIMAGETOOL_SHA256="ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0"
RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64"
RUNTIME_SHA256="2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d"
# linuxdeploy's own patchelf (0.15) corrupts libraries that use RELR
# relocations (Fedora and other newer distros): they crash in _init.
PATCHELF_URL="https://github.com/NixOS/patchelf/releases/download/0.19.2/patchelf-0.19.2-x86_64.tar.gz"
PATCHELF_SHA256="2abdc34fbe949c995a1baa4ec310896a085588a45a99cd0d726851bdfac2a4bb"

# Desktop-stack libraries the system must provide. Bundling them breaks more
# than it fixes (theme, keyring, portals, mDNS). Glob patterns on file names.
EXCLUDES=(
  'libgtk-*' 'libgdk-*' 'libgdk_pixbuf-*' 'libatk-*' 'libatk-bridge-*'
  'libatspi*' 'libpango*' 'libcairo*' 'libharfbuzz*' 'libepoxy*'
  'libglib-*' 'libgobject-*' 'libgio-*' 'libgmodule-*' 'libgthread-*'
  'libsecret-*'
  'libdbus-*'
  'libavahi-*'
  'libsystemd*'
  'libwayland-*' 'libxkbcommon*'
)

# fetch <url> <sha256> <file>: download once into the cache and verify.
fetch() {
  local url="$1" sha="$2" file="$3"
  if [[ ! -f "$file" ]] || ! echo "$sha  $file" | sha256sum -c --status; then
    mkdir -p "$(dirname "$file")"
    echo "Downloading $url"
    curl -fsSL --retry 3 -o "$file.part" "$url"
    if ! echo "$sha  $file.part" | sha256sum -c --status; then
      rm -f "$file.part"
      echo "Checksum mismatch for $url" >&2
      exit 1
    fi
    mv "$file.part" "$file"
  fi
}

if [[ -z "${LINUXDEPLOY:-}" ]]; then
  LINUXDEPLOY="$TOOL_CACHE/linuxdeploy-x86_64.AppImage"
  fetch "$LINUXDEPLOY_URL" "$LINUXDEPLOY_SHA256" "$LINUXDEPLOY"
  chmod +x "$LINUXDEPLOY"
fi
if [[ -z "${APPIMAGETOOL:-}" ]]; then
  APPIMAGETOOL="$TOOL_CACHE/appimagetool-x86_64.AppImage"
  fetch "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA256" "$APPIMAGETOOL"
  chmod +x "$APPIMAGETOOL"
fi
if [[ -z "${APPIMAGE_RUNTIME:-}" ]]; then
  APPIMAGE_RUNTIME="$TOOL_CACHE/runtime-x86_64"
  fetch "$RUNTIME_URL" "$RUNTIME_SHA256" "$APPIMAGE_RUNTIME"
fi

if [[ -z "${PATCHELF:-}" ]]; then
  PATCHELF="$TOOL_CACHE/patchelf-0.19.2/bin/patchelf"
  if [[ ! -x "$PATCHELF" ]]; then
    fetch "$PATCHELF_URL" "$PATCHELF_SHA256" "$TOOL_CACHE/patchelf-0.19.2.tar.gz"
    mkdir -p "$TOOL_CACHE/patchelf-0.19.2"
    tar -xzf "$TOOL_CACHE/patchelf-0.19.2.tar.gz" -C "$TOOL_CACHE/patchelf-0.19.2" ./bin/patchelf
  fi
fi
export PATCHELF  # linuxdeploy uses this instead of its bundled copy

if [[ ! -x "$BUNDLE_DIR/songies" ]]; then
  echo "No release bundle at $BUNDLE_DIR; run: flutter build linux --release" >&2
  exit 1
fi

# media_kit opens libmpv.so / libmpv.so.2 / libmpv.so.1 at runtime, so it is
# not a link-time dependency linuxdeploy could discover by itself.
if [[ -z "${LIBMPV:-}" ]]; then
  for name in libmpv.so.2 libmpv.so.1; do
    # No early exit in awk: with pipefail, ldconfig would die of SIGPIPE.
    LIBMPV="$(ldconfig -p | awk -v n="$name" '$1 == n && /x86-64/ && !f { print $NF; f = 1 }')"
    [[ -n "$LIBMPV" ]] && break
  done
fi
if [[ -z "${LIBMPV:-}" || ! -e "$LIBMPV" ]]; then
  echo "libmpv not found; install it (Ubuntu: apt install libmpv-dev)" >&2
  exit 1
fi
echo "Bundling $LIBMPV"

rm -rf "$APPDIR"
mkdir -p "$APPDIR/opt/songies" "$OUT_DIR"
cp -a "$BUNDLE_DIR/." "$APPDIR/opt/songies/"

ICON_DIR="$WORK_DIR/icon"
rm -rf "$ICON_DIR"
mkdir -p "$ICON_DIR"
cp "$ICON_SRC" "$ICON_DIR/songies.png"

exclude_args=()
for pattern in "${EXCLUDES[@]}"; do
  exclude_args+=(--exclude-library "$pattern")
done

# linuxdeploy copies libmpv and its dependency tree into usr/lib, skips the
# excludes above and its own list of base-system libraries (glibc, libGL,
# X11, fontconfig, ALSA, ...), and sets RUNPATH=$ORIGIN on every copy.
"$LINUXDEPLOY" \
  --appdir "$APPDIR" \
  --library "$LIBMPV" \
  "${exclude_args[@]}" \
  --desktop-file "$PACKAGING/songies.desktop" \
  --icon-file "$ICON_DIR/songies.png" \
  --custom-apprun "$PACKAGING/AppRun"

# The AppRun looks for this exact file name.
if [[ ! -e "$APPDIR/usr/lib/$(basename "$LIBMPV")" ]]; then
  echo "linuxdeploy did not bundle $(basename "$LIBMPV")" >&2
  exit 1
fi

# Fail if a desktop-stack library slipped in anyway.
for pattern in "${EXCLUDES[@]}"; do
  if compgen -G "$APPDIR/usr/lib/$pattern" >/dev/null; then
    echo "Excluded library bundled: $pattern" >&2
    exit 1
  fi
done

rm -f "$OUTPUT"
"$APPIMAGETOOL" --no-appstream --runtime-file "$APPIMAGE_RUNTIME" \
  "$APPDIR" "$OUTPUT"
chmod +x "$OUTPUT"
echo "Built $OUTPUT"

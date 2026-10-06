#!/bin/bash
# fetch-upstream-patches.sh — fetches the Android port patch sets for modern
# JDKs that are not vendored in this repo.
#
# Vendored (no download needed):
#   patches/jdk25u_android.diff  — from FCL-Team/Android-OpenJDK-Build
#                                  (see PATCH_SOURCES.md).
# Fetched by this script into patches/upstream/ (already vendored; re-run
# to refresh from branch tip):
#   jre_17/android/*.diff, jre_21/android/*.diff — from
#   PojavLauncherTeam/android-openjdk-build-multiarch, branch buildjre17-21
#   (verified 2026-10-06, see PATCH_SOURCES.md).
#
# Layout note: buildjdk-modern.sh prefers patches/jre_<major>/android/ when
# present (so a pinned local copy always wins) and only uses
# patches/upstream/ as fallback.
set -e

OUTDIR="$(pwd)/patches/upstream"
BRANCH="buildjre17-21"
TARBALL_URL="https://codeload.github.com/PojavLauncherTeam/android-openjdk-build-multiarch/tar.gz/refs/heads/${BRANCH}"

mkdir -p "$OUTDIR"

need_major() {
  if [ ! -d "$(pwd)/patches/jre_$1/android" ] && [ ! -d "$OUTDIR/jre_$1/android" ]; then
    return 0
  fi
  return 1
}

if ! need_major 17 && ! need_major 21; then
  echo "Upstream 17/21 patches already present, nothing to fetch."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Downloading Pojav android-openjdk-build-multiarch@${BRANCH} ..."
curl -fsSL "$TARBALL_URL" -o "$TMP/upstream.tar.gz"
tar xzf "$TMP/upstream.tar.gz" -C "$TMP"
ROOT=$(find "$TMP" -maxdepth 1 -type d -name "android-openjdk-build-multiarch-*" | head -1)
[ -n "$ROOT" ] || { echo "FATAL: unexpected tarball layout"; exit 1; }

for MAJOR in 17 21; do
  if need_major "$MAJOR"; then
    SRC="$ROOT/patches/jre_$MAJOR/android"
    [ -d "$SRC" ] || { echo "FATAL: $SRC missing in upstream tarball"; exit 1; }
    mkdir -p "$OUTDIR/jre_$MAJOR"
    rm -rf "$OUTDIR/jre_$MAJOR/android"
    cp -r "$SRC" "$OUTDIR/jre_$MAJOR/android"
    echo "Fetched jre_$MAJOR/android: $(ls "$OUTDIR/jre_$MAJOR/android" | wc -l) diff(s)"
  else
    echo "jre_$MAJOR patches already present, skipping."
  fi
done

echo "Upstream patches ready under $OUTDIR"

#!/bin/bash
# repackjre-modern.sh — repackages a source-built modern JRE (17/21/25) into
# the final HostCraft release archive.
#
# Usage: JDK_MAJOR=<17|21|25> ./repackjre-modern.sh [input_tar] [output_path]
# Defaults mirror repackjre.sh conventions: finds jre<MAJOR>-*-release.tar.xz
# in the current dir, writes jre-<major>-<arch>.tar.xz into ./repack-out/.
#
# Output layout (MUST match what the app fetches and unpacks — filenames
# jre-<major>-<arch>.tar.xz with arch in {arm,aarch64,x86,x86_64} per
# JavaInstaller.resolveArch, top dir java-<major>-openjdk/ per
# JvmServerHost.findHome):
#   java-17-openjdk/bin/java, lib/server/libjvm.so, release, ...
set -e

MAJOR="${JDK_MAJOR:-}"
case "$MAJOR" in
  17|21|25) ;;
  *) echo "FATAL: set JDK_MAJOR to 17, 21 or 25"; exit 1 ;;
esac

in="${1:-.}"
out="${2:-./repack-out}"

work="$out/work"
mkdir -p "$work" "$out"

SRC=$(find "$in" -maxdepth 1 -name "jre${MAJOR}-*-release.tar.xz" | head -1)
[ -n "$SRC" ] || { echo "FATAL: no jre${MAJOR}-*-release.tar.xz in $in"; exit 1; }
echo "Repacking $SRC ..."

# Detect arch from the tarjdk filename (jre<MAJOR>-<short>-<date>-release).
BASE=$(basename "$SRC")
SHORT=$(echo "$BASE" | sed -E "s/^jre${MAJOR}-([a-z0-9_]+)-.*/\1/")
case "$SHORT" in
  aarch32) ARCH=arm ;;
  aarch64) ARCH=aarch64 ;;
  x86)     ARCH=x86 ;;
  x86_64)  ARCH=x86_64 ;;
  arm)     ARCH=arm ;;
  arm64)   ARCH=aarch64 ;;
  i386|i686) ARCH=x86 ;;
  amd64)   ARCH=x86_64 ;;
  *) echo "FATAL: cannot map '$SHORT' to a release arch"; exit 1 ;;
esac

rm -rf "$work/repack"
mkdir -p "$work/repack/java-$MAJOR-openjdk"
tar xf "$SRC" -C "$work/repack/java-$MAJOR-openjdk"

DEST="$work/repack/java-$MAJOR-openjdk"
[ -x "$DEST/bin/java" ] || { echo "FATAL: $DEST/bin/java missing after extract"; exit 1; }
[ -f "$DEST/release" ] || { echo "FATAL: $DEST/release missing after extract"; exit 1; }
if ! find "$DEST" -name libjvm.so | grep -q .; then
  echo "FATAL: no libjvm.so under $DEST"; exit 1
fi
# The freetype-bundling contract (assemble-modern-jre.sh copies the freshly
# built .so in): libfontmanager.so must resolve its freetype at load time.
if ! find "$DEST" -name libfreetype.so | grep -q .; then
  echo "FATAL: no libfreetype.so under $DEST (freetype bundling regressed)"
  exit 1
fi

# Drop first-run weight the app never needs from a server JRE.
rm -rf "$DEST/man" "$DEST/legal" 2>/dev/null || true

OUTPUT="$out/jre-$MAJOR-$ARCH.tar.xz"
tar -cJf "$OUTPUT" -C "$work/repack" .
echo "Created: $OUTPUT ($(du -sh "$OUTPUT" | cut -f1))"
echo "$OUTPUT"

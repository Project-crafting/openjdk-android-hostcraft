#!/bin/bash
# verifyjre.sh <tarball> <expected-java-major> <expected-arch-tag>
#
# Guards the release pipeline against wrong-VM / wrong-arch JRE packages:
# extracts libjvm.so and asserts (1) ELF machine matches the arch tag,
# (2) the HotSpot version embedded in libjvm.so maps to the expected JDK
# major, (3) the `release` file agrees. Exits 0 on success, 1 with a clear
# message otherwise (CI fails the release).
#
# NOTE on HotSpot numbering: HotSpot 25 *is* JDK 8's VM (HS 24 = JDK 7,
# HS 25 = JDK 8; the scheme restarted at 9). A libjvm reporting
# "OpenJDK 64-Bit Server VM (25.512-b00)" with JRE "1.8.0_512" is a
# CORRECT Java 8 build — do NOT "fix" this mapping.
set -u

TARBALL="$1"
EXPECT_MAJOR="$2"
EXPECT_ARCH="$3"

fail() { echo "VERIFY-FAIL [$TARBALL]: $1"; exit 1; }

[ -f "$TARBALL" ] || fail "file not found"
command -v readelf >/dev/null 2>&1 || fail "readelf missing (install binutils)"
command -v strings >/dev/null 2>&1 || fail "strings missing (install binutils)"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
tar xf "$TARBALL" -C "$WORK" 2>/dev/null || fail "extract failed"

LIBJVM=$(find "$WORK" -name libjvm.so | head -1)
[ -n "$LIBJVM" ] || fail "libjvm.so not found in archive"

# 1) Architecture from the ELF header.
MACHINE=$(readelf -h "$LIBJVM" 2>/dev/null | grep -i 'machine:' | head -1) || fail "readelf failed"
case "$EXPECT_ARCH" in
  aarch64) echo "$MACHINE" | grep -qi "aarch64" || fail "arch mismatch: want aarch64, got [$MACHINE]" ;;
  arm)     echo "$MACHINE" | grep -qiE "machine: +arm$" || fail "arch mismatch: want arm, got [$MACHINE]" ;;
  x86_64)  echo "$MACHINE" | grep -qi "x86-64" || fail "arch mismatch: want x86_64, got [$MACHINE]" ;;
  x86|i686) echo "$MACHINE" | grep -qi "intel 80386" || fail "arch mismatch: want x86, got [$MACHINE]" ;;
  *) fail "unknown arch tag: $EXPECT_ARCH" ;;
esac

# 2) HotSpot major embedded in libjvm.so -> JDK major (25 maps to 8).
VMVER=$(strings -a "$LIBJVM" 2>/dev/null | grep -oE 'OpenJDK 64-Bit Server VM \([0-9]+' | head -1 | grep -oE '[0-9]+$')
[ -n "$VMVER" ] || fail "no HotSpot version string inside libjvm.so"
if [ "$VMVER" = "25" ]; then VMJDK=8; else VMJDK=$VMVER; fi
[ "$VMJDK" = "$EXPECT_MAJOR" ] || fail "VM reports JDK $VMJDK, expected JDK $EXPECT_MAJOR"

# 3) `release` file consistency (when present in the package).
REL=$(find "$WORK" -maxdepth 4 -name release -type f | head -1)
RV="n/a"
if [ -n "$REL" ]; then
  RV=$(grep -E '^JAVA_VERSION=' "$REL" 2>/dev/null | head -1 | cut -d'"' -f2)
  if [ -n "$RV" ]; then
    case "$RV" in
      1.*) RELMAJOR=$(echo "$RV" | cut -d. -f2 | cut -d. -f1 | tr -cd '0-9') ;;
      *)   RELMAJOR=$(echo "$RV" | cut -d. -f1 | tr -cd '0-9') ;;
    esac
    # Strip leading zeros some vendors emit ("08" vs "8").
    RELMAJOR=$(echo "$RELMAJOR" | sed 's/^0*//')
    [ -z "$RELMAJOR" ] && RELMAJOR=0
    [ "$RELMAJOR" = "$EXPECT_MAJOR" ] || fail "release file says Java $RELMAJOR ($RV), expected JDK $EXPECT_MAJOR"
  fi
fi

echo "VERIFY-OK [$TARBALL]: arch=$EXPECT_ARCH vm=$VMVER jdk=$VMJDK release=$RV"

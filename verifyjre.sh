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

LIBJVMS=$(find "$WORK" -name libjvm.so)
[ -n "$LIBJVMS" ] || fail "libjvm.so not found in archive"
echo "libjvm.so copies found:"
echo "$LIBJVMS" | while read -r f; do echo "  - $f ($(du -h "$f" | cut -f1))"; done

check_one_libjvm() {
  LIBJVM="$1"
  # 1) Architecture from the ELF header.
  MACHINE=$(readelf -h "$LIBJVM" 2>/dev/null | grep -i 'machine:' | head -1) || return 1
  case "$EXPECT_ARCH" in
    aarch64) echo "$MACHINE" | grep -qi "aarch64" || return 1 ;;
    arm)     echo "$MACHINE" | grep -qiE "machine: +arm$" || return 1 ;;
    x86_64)  echo "$MACHINE" | grep -qi "x86-64" || return 1 ;;
    x86|i686) echo "$MACHINE" | grep -qi "intel 80386" || return 1 ;;
    *) return 1 ;;
  esac
  # 2) HotSpot major embedded in libjvm.so -> JDK major (25 maps to 8).
  # Banner shapes vary by toolchain: 64-bit builds print
  # "OpenJDK 64-Bit Server VM (17...", while 32-bit client builds print
  # "OpenJDK Client VM (25..." with no bitness infix at all. A toolchain
  # that folds neither into one literal is covered by the standalone
  # HotSpot release fallback (e.g. 25.512-b00).
  VMSTR=$(strings -a "$LIBJVM" 2>/dev/null | grep -oE 'OpenJDK( (32|64)-Bit)? (Client|Server) VM \([0-9]+' | head -1)
  if [ -n "$VMSTR" ]; then
    VMVER=$(echo "$VMSTR" | grep -oE '[0-9]+$')
  else
    VMSTR=$(strings -a "$LIBJVM" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+-b[0-9]+' | head -1)
    [ -n "$VMSTR" ] || return 1
    VMVER=$(echo "$VMSTR" | grep -oE '^[0-9]+')
  fi
  if [ "$VMVER" = "25" ]; then VMJDK=8; else VMJDK=$VMVER; fi
  [ "$VMJDK" = "$EXPECT_MAJOR" ] || return 1
  echo "$LIBJVM :: arch=$EXPECT_ARCH vm=$VMVER jdk=$VMJDK"
  return 0
}

PASS_COUNT=0
FAIL_DETAIL=""
while IFS= read -r _lib; do
  [ -n "$_lib" ] || continue
  if check_one_libjvm "$_lib"; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_DETAIL="${FAIL_DETAIL}FAILED: $_lib"$'\n'
  fi
done <<< "$LIBJVMS"

if [ "$PASS_COUNT" -eq 0 ]; then
  echo "VERIFY-FAIL [$TARBALL]: no usable libjvm.so (need arch=$EXPECT_ARCH, JDK=$EXPECT_MAJOR)"
  echo "$FAIL_DETAIL"
  FIRST_LIB=$(echo "$LIBJVMS" | head -1)
  echo "--- version-like strings in $FIRST_LIB (excluding gHotSpotVM debug symbols): ---"
  strings -a "$FIRST_LIB" 2>/dev/null | grep -v '^gHotSpotVM' | grep -iE 'openjdk|hotspot|server vm|client vm|java version|1\.[89]\.|^1[0-9]\.|^2[0-9]\.' | head -40
  echo "--- (empty above = stripped or non-HotSpot binary) ---"
  exit 1
fi

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

echo "VERIFY-OK [$TARBALL]: arch=$EXPECT_ARCH release=$RV ($PASS_COUNT libjvm validated)"

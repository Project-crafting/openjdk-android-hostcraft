#!/bin/bash
# getbootjdk.sh — resolves the *host* boot JDK needed to compile modern JDKs.
# Only used for JDK_MAJOR 17/21/25 (jdk8 bootstraps itself via its own chain).
#
# Minimum boot versions (upstream requirement):
#   17 -> boot 17,  21 -> boot 21,  25 -> boot 24 (FCL-Team uses jdk-24.0.2).
# Resolution order: $BOOT_JDK, then $JAVA_HOME (as provided by CI
# actions/setup-java), then a Temurin download via the Adoptium API.
#
# Stdout contract: human logs go to stderr; on success the LAST line is
#   BOOT_JDK=<path>
# so callers do:  eval "$(bash getbootjdk.sh)"
set -e

MAJOR="${JDK_MAJOR:-8}"
case "$MAJOR" in
  17|21|25) ;;
  *) echo "getbootjdk.sh: JDK_MAJOR=$MAJOR needs no boot JDK step" >&2; exit 0 ;;
esac
case "$MAJOR" in
  17) NEED=17; REL=ga ;;
  21) NEED=21; REL=ga ;;
  25) NEED=24; REL=feature ;;
esac

ver_of() {
  # prints the major of "$1/bin/java -version"
  "$1/bin/java" -version 2>&1 | grep -oE 'version "[0-9]+' | head -1 | grep -oE '[0-9]+' || echo 0
}

for CAND in "${BOOT_JDK:-}" "${JAVA_HOME:-}"; do
  if [ -n "$CAND" ] && [ -x "$CAND/bin/javac" ]; then
    GOT=$(ver_of "$CAND")
    if [ "$GOT" -ge "$NEED" ] 2>/dev/null; then
      echo "Boot JDK: $CAND (major $GOT, need >= $NEED)" >&2
      echo "BOOT_JDK=$CAND"
      exit 0
    else
      echo "Ignoring boot candidate $CAND (major ${GOT:-unknown}, need >= $NEED)" >&2
    fi
  fi
done

# Fallback: Temurin (Adoptium API, no auth).
URL="https://api.adoptium.net/v3/binary/latest/${NEED}/${REL}/linux/x64/jdk/hotspot/normal/eclipse"
echo "Downloading Temurin boot JDK $NEED ($REL) ..." >&2
curl -fsSL "$URL" -o bootjdk.tar.gz
mkdir -p bootjdk && tar xzf bootjdk.tar.gz -C bootjdk --strip-components=1
rm bootjdk.tar.gz
GOT=$(ver_of "$PWD/bootjdk")
[ "$GOT" -ge "$NEED" ] || { echo "FATAL: downloaded boot JDK reports $GOT, need >= $NEED" >&2; exit 1; }
echo "Boot JDK ready: $PWD/bootjdk (major $GOT)" >&2
echo "BOOT_JDK=$PWD/bootjdk"

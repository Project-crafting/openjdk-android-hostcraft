#!/bin/bash
set -e
. setdevkitpath.sh

export JDK_DEBUG_LEVEL=release

if [[ "${JDK_MAJOR:-8}" == "8" ]]; then

if [[ "$BUILD_IOS" != "1" ]]; then
  ./maketoolchain.sh
else
  chmod +x ios-arm64-clang
  chmod +x ios-arm64-clang++
  chmod +x macos-host-cc
fi

# Some modifies to NDK to fix

./getlibs.sh
./buildlibs.sh
./clonejdk.sh
./buildjdk.sh
./removejdkdebuginfo.sh
./tarjdk.sh

else

# Modern JDKs (17/21/25): NDK toolchain, freetype/cups from source, upstream
# sources + Android port patches, Temurin/setup-java boot JDK, jlink-assembled
# self-contained JRE (bundled freetype — no Termux sibling libs at runtime).
./maketoolchain.sh
./getlibs.sh
./buildlibs.sh
./clonejdk.sh
./fetch-upstream-patches.sh
eval "$(bash getbootjdk.sh)" || { echo "FATAL: getbootjdk.sh failed"; exit 1; }
export BOOT_JDK
./buildjdk-modern.sh
./assemble-modern-jre.sh
./tarjdk.sh

fi

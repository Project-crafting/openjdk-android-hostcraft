#!/bin/bash
# assemble-modern-jre.sh — produces the stripped jreout/ tree for JDK 17/21/25.
# Modeled on FCL-Team/Android-OpenJDK-Build/remove_jdk_debug_info.sh, minus
# libawt_xawt (X11 AWT — HostCraft servers run headless; see PATCH_SOURCES.md).
# The freshly built freetype.so is copied into jreout/lib so the JRE carries
# its own correctly-named freetype (no .so.6 alias problem at runtime).
set -e

. setdevkitpath.sh

MAJOR="${JDK_MAJOR:-8}"
case "$MAJOR" in
  17|21|25) ;;
  *) echo "FATAL: assemble-modern-jre.sh handles JDK_MAJOR 17/21/25, got $MAJOR"; exit 1 ;;
esac

targetpath=openjdk-$MAJOR/build/${JVM_PLATFORM}-${TARGET_JDK}-${JVM_VARIANTS}-${JDK_DEBUG_LEVEL}

rm -rf dizout jreout jdkout dSYM-temp
mkdir -p dizout dSYM-temp/{lib,bin}

FREETYPE_SO=freetype-$BUILD_FREETYPE_VERSION/build_android-$TARGET_SHORT/lib/libfreetype.so
[ -f "$FREETYPE_SO" ] || { echo "FATAL: built freetype missing at $FREETYPE_SO (buildlibs.sh step failed?)"; exit 1; }
cp "$FREETYPE_SO" $targetpath/images/jdk/lib/

cp -r $targetpath/images/jdk jdkout

export EXTRA_JLINK_OPTION=

if [[ "$TARGET_JDK" == "aarch64" ]] || [[ "$TARGET_JDK" == "x86_64" ]]; then
   echo "Building for aarch64 or x86_64, introducing JVMCI module"
   export EXTRA_JLINK_OPTION=,jdk.internal.vm.ci,jdk.internal.jvmstat,jdk.internal.ed,jdk.internal.le,jdk.internal.md,jdk.internal.opt
fi

export JLINK_STRIP_ARG="--strip-native-debug-symbols=exclude-debuginfo-files:objcopy=${OBJCOPY}"

# Produce the jre equivalent from the jdk (https://blog.adoptium.net/2021/10/jlink-to-produce-own-runtime/)
# Module set mirrors FCL's (server-capable headless runtime).
$targetpath/buildjdk/jdk/bin/jlink \
--module-path=jdkout/jmods \
--add-modules java.base,java.compiler,java.datatransfer,java.desktop,java.instrument,java.logging,java.management,java.management.rmi,java.naming,java.net.http,java.prefs,java.rmi,java.scripting,java.se,java.security.jgss,java.security.sasl,java.sql,java.sql.rowset,java.transaction.xa,java.xml,java.xml.crypto,jdk.accessibility,jdk.charsets,jdk.crypto.cryptoki,jdk.crypto.ec,jdk.dynalink,jdk.editpad,jdk.httpserver,jdk.jdwp.agent,jdk.jfr,jdk.jsobject,jdk.localedata,jdk.management,jdk.management.agent,jdk.management.jfr,jdk.naming.dns,jdk.naming.rmi,jdk.net,jdk.nio.mapmode,jdk.sctp,jdk.security.auth,jdk.security.jgss,jdk.unsupported,jdk.xml.dom,jdk.zipfs,jdk.hotspot.agent,jdk.incubator.vector$EXTRA_JLINK_OPTION \
--output jreout \
$JLINK_STRIP_ARG \
--no-man-pages \
--no-header-files \
--release-info=jdkout/release \
--compress=0

cp "$FREETYPE_SO" jreout/lib/

find jdkout -name "*.debuginfo" -exec mv {}   dizout/ \;

find jdkout -name "*.dSYM"  | xargs -- rm -rf

echo "Modern JRE assembled in jreout/ (freetype bundled: $(ls -la jreout/lib/libfreetype.so))"

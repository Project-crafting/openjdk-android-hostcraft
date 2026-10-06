#!/bin/bash
# buildjdk-modern.sh — configures and builds OpenJDK 17/21/25 for Android.
# jdk8 keeps using buildjdk.sh untouched; this script covers only JDK_MAJOR
# 17, 21 and 25. Combines PojavLauncherTeam/android-openjdk-build-multiarch
# (branch buildjre17-21: 5_clonejdk.sh/6_buildjdk.sh) with
# FCL-Team/Android-OpenJDK-Build (build_jdk.sh, jdk25) — see PATCH_SOURCES.md.
set -e
. setdevkitpath.sh

MAJOR="${JDK_MAJOR:-8}"
case "$MAJOR" in
  17|21|25) ;;
  *) echo "FATAL: buildjdk-modern.sh handles JDK_MAJOR 17/21/25, got $MAJOR"; exit 1 ;;
esac
if [[ "$BUILD_IOS" == "1" ]]; then
  echo "FATAL: iOS modern-JDK builds are not wired (jdk8 iOS flow is separate)"
  exit 1
fi
export TARGET_VERSION=$MAJOR

if [[ "$TARGET_JDK" == "arm" ]]; then
  export CFLAGS+=" -O3 -D__thumb__"
  export CFLAGS+=" -Dfseeko=fseek -Dftello=ftell"
else
  export CFLAGS+=" -O3"
fi
if [[ "$TARGET_JDK" == "x86" ]]; then
  export CFLAGS+=" -mstackrealign"
  # OpenJDK defaults 32-bit x86 to -march=i586, which NDK clang removed
  # ("error: unknown target CPU 'i586'"). Override via extra-cflags (later
  # flag wins on the command line). Must be a 64-bit-capable CPU like the
  # silvermont used by buildjdk.sh: these CFLAGS also leak into the HOST
  # build-tools compile, where a 32-bit-only -march (e.g. i686) collides
  # with 64-bit-only flags ("CPU you selected does not support x86-64").
  export CFLAGS+=" -march=silvermont"
fi

export FREETYPE_DIR=$PWD/freetype-$BUILD_FREETYPE_VERSION/build_android-$TARGET_SHORT
export CUPS_DIR=$PWD/cups-2.2.4
export CFLAGS+=" -DLE_STANDALONE"

chmod +x android-wrapped-clang android-wrapped-clang++
ln -s -f /usr/include/X11 $ANDROID_INCLUDE/
ln -s -f /usr/include/fontconfig $ANDROID_INCLUDE/
platform_args="--with-toolchain-type=gcc \
  --with-freetype-include=$FREETYPE_DIR/include/freetype2 \
  --with-freetype-lib=$FREETYPE_DIR/lib \
  "
if [[ "$MAJOR" == "21" || "$MAJOR" == "25" ]]; then
  platform_args+="--build=x86_64-unknown-linux-gnu \
  "
fi
platform_args+="OBJCOPY=${OBJCOPY} \
  RANLIB=${RANLIB} \
  AR=${AR} \
  STRIP=${STRIP} \
  "

AUTOCONF_x11arg="--x-includes=$ANDROID_INCLUDE/X11"

export CFLAGS+=" -mllvm -polly -DANDROID -D__ANDROID__=1 -Wno-error=implicit-function-declaration -Wno-error=int-conversion"
export LDFLAGS+=" -L$PWD/dummy_libs -Wl,--undefined-version"

# Create dummy libraries so we won't have to remove them in OpenJDK makefiles
mkdir -p dummy_libs
ar cru dummy_libs/libpthread.a
ar cru dummy_libs/librt.a
ar cru dummy_libs/libthread_db.a

# fix building libjawt
ln -s -f $CUPS_DIR/cups $ANDROID_INCLUDE/

# Boot JDK (ci_build_global.sh runs getbootjdk.sh first and exports it;
# re-resolve here for manual runs via its stdout contract).
if [[ -z "${BOOT_JDK:-}" || ! -x "$BOOT_JDK/bin/javac" ]]; then
  eval "$(bash getbootjdk.sh)" || { echo "FATAL: getbootjdk.sh failed"; exit 1; }
fi
if [[ -z "${BOOT_JDK:-}" || ! -x "$BOOT_JDK/bin/javac" ]]; then
  echo "FATAL: no usable boot JDK (need >= $([[ "$MAJOR" == "25" ]] && echo 24 || echo "$MAJOR")); run getbootjdk.sh or set BOOT_JDK/JAVA_HOME)"
  exit 1
fi

# --- Android port patches (FATAL on drift, same policy as buildjdk.sh) ---
apply_patch() {
  local patch_file="$1" desc="$2"
  echo "Applying $desc ($patch_file)..."
  if ! git apply --check --whitespace=fix "$patch_file" 2>patch-check.log; then
    echo "FATAL: patch pre-check failed for $desc — sources drifted, refusing to build unpatched:"
    cat patch-check.log
    exit 1
  fi
  git apply --whitespace=fix "$patch_file"
  echo "Applied $desc cleanly."
}

resolve_patch_dir() {
  # Local pin wins (patches/jre_<major>/android), then the fetched upstream
  # copy (fetch-upstream-patches.sh), then the vendored jdk25 file.
  if [ -d "patches/jre_$MAJOR/android" ]; then
    echo "patches/jre_$MAJOR/android"
  elif [ -d "patches/upstream/jre_$MAJOR/android" ]; then
    echo "patches/upstream/jre_$MAJOR/android"
  elif [ "$MAJOR" == "25" ] && [ -f "patches/jdk25u_android.diff" ]; then
    echo "FILE:patches/jdk25u_android.diff"
  else
    echo ""
  fi
}

cd openjdk-$MAJOR
git reset --hard
PATCHDIR=$(cd .. && resolve_patch_dir)
if [[ "$PATCHDIR" == FILE:* ]]; then
  apply_patch "../${PATCHDIR#FILE:}" "vendored jdk25u Android port (FCL-Team)"
elif [[ -n "$PATCHDIR" ]]; then
  # NOTE: find prints paths prefixed with the search root (../patches/...),
  # already correct relative to our cwd inside openjdk-$MAJOR — do NOT
  # prepend another ../ here (that produced '../../patches/...' misses).
  while IFS= read -r -d '' diff; do
    apply_patch "$diff" "upstream Android port $(basename "$diff")"
  done < <(find "../$PATCHDIR" -name "*.diff" -print0 | sort -z)
else
  echo "FATAL: no Android patch set for JDK $MAJOR (run fetch-upstream-patches.sh or vendor patches/jre_$MAJOR/android/)"
  exit 1
fi
cd ..

# NOTE: configure must run from INSIDE the source tree (like Pojav/FCL):
# it creates build/<conf>/ relative to the cwd. All paths handed to it
# (FREETYPE/CUPS dirs, dummy_libs, TOOLCHAIN, BOOT_JDK) are absolute, so
# changing directory here is safe.
cd openjdk-$MAJOR
bash ./configure \
    --with-boot-jdk=$BOOT_JDK \
    --openjdk-target=$TARGET \
    --with-extra-cflags="$CFLAGS" \
    --with-extra-cxxflags="$CFLAGS" \
    --with-extra-ldflags="$LDFLAGS" \
    --disable-precompiled-headers \
    --disable-warnings-as-errors \
    --enable-option-checking=fatal \
    --enable-headless-only=yes \
    --with-jvm-variants=$JVM_VARIANTS \
    --with-jvm-features=-dtrace,-zero,-vm-structs,-epsilongc \
    --with-cups-include=$CUPS_DIR \
    --with-devkit=$TOOLCHAIN \
    --with-native-debug-symbols=external \
    --with-debug-level=$JDK_DEBUG_LEVEL \
    --with-fontconfig-include=$ANDROID_INCLUDE \
    $AUTOCONF_x11arg $AUTOCONF_EXTRA_ARGS \
    --x-libraries=/usr/lib \
        $platform_args || \
error_code=$?
if [[ "$error_code" -ne 0 ]]; then
  echo "\n\nCONFIGURE ERROR $error_code , config.log:"
  cat config.log
  exit $error_code
fi

jobs=$(nproc)
echo "Running ${jobs} jobs to build JDK $MAJOR"
cd build/${JVM_PLATFORM}-${TARGET_JDK}-${JVM_VARIANTS}-${JDK_DEBUG_LEVEL}
make JOBS=$jobs images || \
error_code=$?
if [[ "$error_code" -ne 0 ]]; then
  echo "Build failure, exited with code $error_code. Trying again."
  make JOBS=$jobs images
fi

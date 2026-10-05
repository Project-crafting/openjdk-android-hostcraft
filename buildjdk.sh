#!/bin/bash
set -e
. setdevkitpath.sh

if [[ "$TARGET_JDK" == "arm" ]]
then
  export TARGET_JDK=aarch32
  export TARGET_PHYS=aarch32-linux-androideabi
  export JVM_VARIANTS=client
  export CFLAGS+=" -march=armv7-a"
else
  export TARGET_PHYS=$TARGET
fi

if [[ "$TARGET_JDK" == "x86" || "$TARGET_JDK" == "x86_64" ]]; then
  export CFLAGS+=" -march=silvermont"
fi

if [[ "$TARGET_JDK" == "x86" ]]; then
  export CFLAGS+=" -mstackrealign"
fi

export FREETYPE_DIR=$PWD/freetype-$BUILD_FREETYPE_VERSION/build_android-$TARGET_SHORT
export CUPS_DIR=$PWD/cups-2.2.4
export CFLAGS+=" -DLE_STANDALONE" # -I$FREETYPE_DIR -I$CUPS_DI

# if [[ "$TARGET_JDK" == "aarch32" ]] || [[ "$TARGET_JDK" == "aarch64" ]]
# then
#   export CFLAGS+=" -march=armv7-a+neon"
# fi

# It isn't good, but need make it build anyways
# cp -R $CUPS_DIR/* $ANDROID_INCLUDE/

# cp -R /usr/include/X11 $ANDROID_INCLUDE/
# cp -R /usr/include/fontconfig $ANDROID_INCLUDE/

if [[ "$BUILD_IOS" != "1" ]]; then
  export CFLAGS+=" -O3 -D__ANDROID__"

  ln -s -f /usr/include/X11 $ANDROID_INCLUDE/
  ln -s -f /usr/include/fontconfig $ANDROID_INCLUDE/
  AUTOCONF_x11arg="--x-includes=$ANDROID_INCLUDE/X11"

  export LDFLAGS+=" -L`pwd`/dummy_libs"

# Create dummy libraries so we won't have to remove them in OpenJDK makefiles
  mkdir -p dummy_libs
  ar cru dummy_libs/libpthread.a
  ar cru dummy_libs/libthread_db.a
  if [[ "$TARGET_JDK" == "aarch64" || "$TARGET_JDK" == "x86_64" ]]; then
     export LDFLAGS+=" -Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"
  fi
else
  ln -s -f /opt/X11/include/X11 $ANDROID_INCLUDE/
  platform_args="--with-toolchain-type=clang SDKNAME=iphoneos"
  # --disable-precompiled-headers
  AUTOCONF_x11arg="--with-x=/opt/X11/include/X11 --prefix=/usr/lib"
  sameflags="-arch arm64 -DHEADLESS=1 -I$PWD/ios-missing-include -Wno-implicit-function-declaration"
  export CFLAGS+=" $sameflags"
  export LDFLAGS+=" -arch arm64"
  export BUILD_SYSROOT_CFLAGS="-isysroot ${themacsysroot}"

  HOMEBREW_NO_AUTO_UPDATE=1 brew install ldid xquartz
fi

# fix building libjawt
ln -s -f $CUPS_DIR/cups $ANDROID_INCLUDE/

#FREEMARKER=$PWD/freemarker-2.3.8/lib/freemarker.jar

cd openjdk

# Apply patches
git reset --hard
# Patch application is FATAL on failure: a drifted patch set must never
# silently produce an unpatched (minus Android port) tree. The old
# `|| echo` swallowed rejections and shipped broken runtimes.
apply_patch() {
  local patch_file="$1"
  local desc="$2"
  echo "Applying $desc ($patch_file)..."
  if ! git apply --check --whitespace=fix "$patch_file" 2>patch-check.log; then
    echo "FATAL: patch pre-check failed for $desc — jdk8u sources drifted, refusing to build unpatched:"
    cat patch-check.log
    exit 1
  fi
  git apply --whitespace=fix "$patch_file"
  echo "Applied $desc cleanly."
}
# The android-config hunks (config.sub triple handling + generated-configure
# OS mapping) differ between the jdk8u-master and aarch32-port sources, so
# they live in per-source variants. Try master layout first, fall back to
# the aarch32-port layout; fail if neither matches (new drift).
apply_config_android_patch() {
  if git apply --check --whitespace=fix ../patches/jdk8u_android_config_master.diff 2>/dev/null; then
    apply_patch ../patches/jdk8u_android_config_master.diff "android config (jdk8u master layout)"
  elif git apply --check --whitespace=fix ../patches/jdk8u_android_config_aarch32.diff 2>/dev/null; then
    apply_patch ../patches/jdk8u_android_config_aarch32.diff "android config (aarch32-port layout)"
  else
    echo "FATAL: neither android-config patch variant applies — sources drifted:"
    git apply --check --whitespace=fix ../patches/jdk8u_android_config_master.diff 2>&1 | head -5 || true
    exit 1
  fi
}
apply_patch ../patches/jdk8u_android.diff "universal patch set"
apply_config_android_patch
if [[ "$BUILD_IOS" != "1" ]]; then
  if [[ "$TARGET_JDK" != "aarch32" ]]; then
    apply_patch ../patches/jdk8u_android_main.diff "main non-universal patch set"
  else
    apply_patch ../patches/jdk8u_android_aarch32.diff "aarch32 non-universal patch set"
  fi
  if [[ "$TARGET_JDK" == "x86" ]]; then
    apply_patch ../patches/jdk8u_android_page_trap_fix.diff "x86 page trap fix"
  fi
else
  apply_patch ../patches/jdk8u_ios.diff "ios patch set"
fi

#   --with-extra-cxxflags="$CXXFLAGS -Dchar16_t=uint16_t -Dchar32_t=uint32_t" \
#   --with-extra-cflags="$CPPFLAGS" \
#   --with-sysroot="$(xcrun --sdk iphoneos --show-sdk-path)" \

# Let's print what's available
# bash configure --help

#   --with-freemarker-jar=$FREEMARKER \
#   --with-toolchain-type=clang \
#   --with-native-debug-symbols=none \
bash ./configure \
    --openjdk-target=$TARGET_PHYS \
    --with-extra-cflags="$CFLAGS" \
    --with-extra-cxxflags="$CFLAGS" \
    --with-extra-ldflags="$LDFLAGS" \
    --enable-option-checking=fatal \
    --with-jdk-variant=normal \
    --with-jvm-variants="${JVM_VARIANTS/AND/,}" \
    --with-cups-include=$CUPS_DIR \
    --with-devkit=$TOOLCHAIN \
    --with-debug-level=$JDK_DEBUG_LEVEL \
    --with-fontconfig-include=$ANDROID_INCLUDE \
    --with-freetype-lib=$FREETYPE_DIR/lib \
    --with-freetype-include=$FREETYPE_DIR/include/freetype2 \
    $AUTOCONF_x11arg $AUTOCONF_EXTRA_ARGS \
    --x-libraries=/usr/lib \
        $platform_args || \
error_code=$?
if [[ "$error_code" -ne 0 ]]; then
  echo "\n\nCONFIGURE ERROR $error_code , config.log:"
  cat config.log
  exit $error_code
fi

cd build/${JVM_PLATFORM}-${TARGET_JDK}-normal-${JVM_VARIANTS}-${JDK_DEBUG_LEVEL}
make JOBS=4 images || \
error_code=$?
if [[ "$error_code" -ne 0 ]]; then
  echo "Build failure, exited with code $error_code. Trying again."
  make JOBS=4 images
fi

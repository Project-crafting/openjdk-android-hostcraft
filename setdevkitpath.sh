# Use the old NDK r10e to not get internal compile error at
# https://github.com/PojavLauncherTeam/openjdk-multiarch-jdk8u/blob/aarch64-shenandoah-jdk8u272-b10/jdk/src/share/native/sun/java2d/loops/GraphicsPrimitiveMgr.c
export NDK_VERSION=r10e

# JDK_MAJOR selects the JDK line to build (default 8, preserves the original
# behavior exactly). Modern lines need a modern NDK instead of r10e:
#   17/21 -> r27b (PojavLauncherTeam/android-openjdk-build-multiarch,
#                  branch buildjre17-21)
#   25    -> r28  (FCL-Team/Android-OpenJDK-Build)
if [[ "${JDK_MAJOR:-8}" == "25" ]]; then
  export NDK_VERSION=r28
elif [[ "${JDK_MAJOR:-8}" == "17" || "${JDK_MAJOR:-8}" == "21" ]]; then
  export NDK_VERSION=r27b
fi

if [[ -z "$BUILD_FREETYPE_VERSION" ]]
then
  export BUILD_FREETYPE_VERSION="2.10.4"
fi

if [[ -z "$JDK_DEBUG_LEVEL" ]]
then
  export JDK_DEBUG_LEVEL=release
fi

if [[ "$TARGET_JDK" == "aarch64" ]]
then
  export TARGET_SHORT=arm64
else
  export TARGET_SHORT=$TARGET_JDK
fi

if [[ "$TARGET_JDK" == "aarch32" ]] || [[ "$TARGET_JDK" == "arm" ]] || [[ "$TARGET_JDK" == "x86" ]]
then
  echo "VM variant: client"
  if [[ -z "$JVM_VARIANTS" ]]
  then
    export JVM_VARIANTS=client
  fi
else
  echo "VM variant: server"
  if [[ -z "$JVM_VARIANTS" ]]
  then
    export JVM_VARIANTS=server
  fi
fi

# Modern JDKs only ship the server VM for Android (headless-only builds, same
# as FCL/Pojav): force it even on 32-bit arches where jdk8 defaulted to client.
if [[ "${JDK_MAJOR:-8}" != "8" ]]; then
  export JVM_VARIANTS=server
fi

if [[ "$BUILD_IOS" == "1" ]]; then
  export JVM_PLATFORM=macosx

  export thecc=$(xcrun -find -sdk iphoneos clang)
  export thecxx=$(xcrun -find -sdk iphoneos clang++)
  export thesysroot=$(xcrun --sdk iphoneos --show-sdk-path)
  export themacsysroot=$(xcrun --sdk macosx --show-sdk-path)

  export thehostcxx=$PWD/macos-host-cc
  export CC=$PWD/ios-arm64-clang
  export CXX=$PWD/ios-arm64-clang++
  export LD=$(xcrun -find -sdk iphoneos ld)

  export HOTSPOT_DISABLE_DTRACE_PROBES=1

  export ANDROID_INCLUDE=$PWD/ios-missing-include
else

export JVM_PLATFORM=linux
if [[ "${JDK_MAJOR:-8}" == "8" ]]; then
# Set NDK
export API=21
export NDK=`pwd`/android-ndk-$NDK_VERSION
export TOOLCHAIN=$NDK/generated-toolchains/android-${TARGET_SHORT}-toolchain

export ANDROID_INCLUDE=$TOOLCHAIN/sysroot/usr/include

# Configure and build.
export AR=$TOOLCHAIN/bin/$TARGET-ar
export AS=$TOOLCHAIN/bin/$TARGET-as
export CC=$TOOLCHAIN/bin/$TARGET-gcc
export CXX=$TOOLCHAIN/bin/$TARGET-g++
export LD=$TOOLCHAIN/bin/$TARGET-ld
export OBJCOPY=$TOOLCHAIN/bin/$TARGET-objcopy
export RANLIB=$TOOLCHAIN/bin/$TARGET-ranlib
export STRIP=$TOOLCHAIN/bin/$TARGET-strip
else
# Modern JDKs (17/21/25): stock LLVM toolchain from the NDK (FCL-Team /
# Pojav layout) instead of the Mojo gcc-13 generated toolchain.
export API=21
export NDK=`pwd`/android-ndk-$NDK_VERSION
export TOOLCHAIN=$NDK/toolchains/llvm/prebuilt/linux-x86_64
export ANDROID_NDK_HOME=$NDK
export ANDROID_INCLUDE=$TOOLCHAIN/sysroot/usr/include

export CPPFLAGS="-I$ANDROID_INCLUDE -I$ANDROID_INCLUDE/$TARGET"
export LDFLAGS="-L$NDK/platforms/android-$API/arch-$TARGET_SHORT/usr/lib -lstdc++ -lc++abi"

# NDK clang ships no arm-linux-androideabi<API>-clang wrapper — 32-bit ARM is
# armv7a-linux-androideabi<API>-clang (FCL uses the armv7a triple directly).
# $TARGET itself stays arm-linux-androideabi for the sysroot include dir and
# --openjdk-target; only the compiler wrappers are remapped.
case "$TARGET" in
  arm-linux-androideabi) CLANG_TARGET=armv7a-linux-androideabi ;;
  *) CLANG_TARGET=$TARGET ;;
esac
export thecc=$TOOLCHAIN/bin/${CLANG_TARGET}${API}-clang
export thecxx=$TOOLCHAIN/bin/${CLANG_TARGET}${API}-clang++

# Configure and build.
export AR=$TOOLCHAIN/bin/llvm-ar
export AS=$TOOLCHAIN/bin/llvm-as
export CC=$PWD/android-wrapped-clang
export CXX=$PWD/android-wrapped-clang++
export LD=$TOOLCHAIN/bin/ld
export OBJCOPY=$TOOLCHAIN/bin/llvm-objcopy
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip
fi
fi

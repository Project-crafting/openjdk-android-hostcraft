#!/bin/bash
set -e

. setdevkitpath.sh

if [[ "${JDK_MAJOR:-8}" == "8" ]]; then
mkdir -p $NDK/generated-toolchains/android-${TARGET_SHORT}-toolchain
pushd $NDK/generated-toolchains/android-${TARGET_SHORT}-toolchain

wget -nc -nv https://github.com/MojoLauncher/gcc-toolchain/releases/download/prebuilt/gcc-13-${TARGET_SHORT}-21.tar.xz
tar xf gcc-13-${TARGET_SHORT}-21.tar.xz
rm gcc-13-${TARGET_SHORT}-21.tar.xz

#set +e
# I didn't pay enough attention :(
# Remove old libstdc++.so for gcc 4.9, to force the compiler into using the fresher one in aarch64-linux-android/lib64/
rm sysroot/usr/lib/libstdc++.a
rm sysroot/usr/lib/libstdc++.so
#set -e

popd

cp devkit.info.${TARGET_SHORT} $NDK/generated-toolchains/android-${TARGET_SHORT}-toolchain/
else
# Modern JDKs (17/21/25): stock NDK from Google (Pojav/FCL pattern), plus the
# wrapped-clang shims as executable. No Mojo gcc toolchain involved.
if [ ! -d "$NDK" ]; then
  echo "Downloading Android NDK $NDK_VERSION ..."
  wget -nc -nv -O android-ndk-$NDK_VERSION-linux.zip "https://dl.google.com/android/repository/android-ndk-$NDK_VERSION-linux.zip"
  unzip -q android-ndk-$NDK_VERSION-linux.zip
fi
[ -d "$NDK" ] || { echo "FATAL: NDK directory $NDK missing after download"; exit 1; }
chmod +x android-wrapped-clang android-wrapped-clang++
cp devkit.info.${TARGET_SHORT} "$TOOLCHAIN"/ 2>/dev/null || true
fi

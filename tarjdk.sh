#!/bin/bash
set -e

# JDK 8 path: pinned termux-elf-cleaner v2.2.0 via autotools (historical,
# keep byte-identical behavior for the working jdk8 line).
if [[ "${JDK_MAJOR:-8}" == "8" ]]; then

if [[ "$BUILD_IOS" != "1" ]]; then

unset AR AS CC CXX LD OBJCOPY RANLIB STRIP CPPFLAGS LDFLAGS
git clone --depth 1 -b 'v2.2.0' https://github.com/termux/termux-elf-cleaner
cd termux-elf-cleaner
autoreconf --install
bash configure
make CFLAGS=-D__ANDROID_API__=24
cd ..

findexec() { find $1 -type f -name "*" -not -name "*.o" -exec sh -c '
    case "$(head -n 1 "$1")" in
      ?ELF*) exit 0;;
      MZ*) exit 0;;
      #!*/ocamlrun*)exit0;;
    esac
exit 1
' sh {} \; -print
}

findexec jreout | xargs -- ./termux-elf-cleaner/termux-elf-cleaner

fi

cp -Rf jre_override/lib/* jreout/lib/

cd jreout

# Strip in place all .so files thanks to the ndk
find ./ -name '*.so' -execdir ${NDK}${NDK_PREBUILT_ARCH} {} \;

tar cJf ../jre${JDK_MAJOR:-8}-${TARGET_SHORT}-`date +%Y%m%d`-${JDK_DEBUG_LEVEL}.tar.xz .

else
# Modern path (17/21/25): FCL-Team layout — latest elf-cleaner via cmake with
# an explicit target API level, then jre_override fonts, NDK strip.
. setdevkitpath.sh

unset AR AS CC CXX LD OBJCOPY RANLIB STRIP CPPFLAGS LDFLAGS
git clone --depth 1 https://github.com/termux/termux-elf-cleaner || true
cd termux-elf-cleaner
mkdir -p build
cd build
export CFLAGS=-D__ANDROID_API__=${API}
cmake ..
make -j4
unset CFLAGS
cd ../..

findexec() { find $1 -type f -name "*" -not -name "*.o" -exec sh -c '
    case "$(head -n 1 "$1")" in
      ?ELF*) exit 0;;
      MZ*) exit 0;;
      #!*/ocamlrun*)exit0;;
    esac
exit 1
' sh {} \; -print
}

findexec jreout | xargs ./termux-elf-cleaner/build/termux-elf-cleaner --api-level 24

cp -rv jre_override/lib/* jreout/lib/ || true

cd jreout

# Strip in place all .so files thanks to the ndk
find ./ -name '*.so' -execdir $NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip {} \;

tar cJf ../jre${JDK_MAJOR:-8}-${TARGET_SHORT}-`date +%Y%m%d`-${JDK_DEBUG_LEVEL}.tar.xz .

fi

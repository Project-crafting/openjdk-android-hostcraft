#!/bin/bash
set -e
if [[ "${JDK_MAJOR:-8}" == "8" ]]; then
if [[ "$TARGET_JDK" == "arm" ]]; then
git clone --depth 1 https://github.com/openjdk/aarch32-port-jdk8u openjdk
elif [[ "$BUILD_IOS" == "1" ]]; then
git clone --depth 1 https://github.com/corretto/corretto-8 openjdk
else
# Use aarch32 repo because it also has aarch64

git clone --depth 1 https://github.com/openjdk/jdk8u openjdk
fi
elif [[ "${JDK_MAJOR:-8}" == "17" ]]; then
git clone --depth 1 https://github.com/openjdk/jdk17u openjdk-17
elif [[ "${JDK_MAJOR:-8}" == "21" ]]; then
git clone --depth 1 https://github.com/openjdk/jdk21u openjdk-21
elif [[ "${JDK_MAJOR:-8}" == "25" ]]; then
git clone --depth 1 https://github.com/openjdk/jdk25u openjdk-25
else
echo "FATAL: unsupported JDK_MAJOR=${JDK_MAJOR:-8} (want 8, 17, 21 or 25)"
exit 1
fi

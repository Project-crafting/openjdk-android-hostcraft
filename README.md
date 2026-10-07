# openjdk-android-hostcraft

Free and open-source OpenJDK builds for Android (arm, aarch64, x86, x86_64),
covering Java 8, 17, 21 and 25. These runtimes ship in our official Android
app, **MineWrap**, which runs Minecraft servers in-process via
`JNI_CreateJavaVM` — so every JRE here is built to boot headless, self-contained
(no Termux sibling libs at runtime), and verified on real devices.

Based on http://openjdk.java.net/projects/mobile/android.html, with the Android
port patches and build flow adapted from
[PojavLauncherTeam/android-openjdk-build-multiarch](https://github.com/PojavLauncherTeam/android-openjdk-build-multiarch)
(`buildjre17-21`), [FCL-Team/Android-OpenJDK-Build](https://github.com/FCL-Team/Android-OpenJDK-Build)
and [aaaapai/android-openjdk-build](https://github.com/aaaapai/android-openjdk-build).
See [PATCH_SOURCES.md](PATCH_SOURCES.md) for exact provenance of every patch set.

## What gets built

| JDK | Sources | Patches | Boot JDK | NDK |
|-----|---------|---------|----------|-----|
| 8 | `openjdk/jdk8u` (aarch32-port for arm) | `patches/jdk8u_*.diff` (in-repo) | self-bootstrapping | r10e |
| 17 | `openjdk/jdk17u` | `patches/upstream/jre_17/android/*.diff` | 17 (Temurin via `getbootjdk.sh`, or CI `setup-java`) | r27b |
| 21 | `openjdk/jdk21u` | `patches/upstream/jre_21/android/*.diff` | 21 (Temurin via `getbootjdk.sh`, or CI `setup-java`) | r27b |
| 25 | `openjdk/jdk25u` | `patches/jdk25u_android.diff` (vendored from FCL-Team) | 24 (Temurin via `getbootjdk.sh`, or CI `setup-java`) | r28 |

Release archives are named `jre-<major>-<arch>.tar.xz` with
`<arch>` in `{arm, aarch64, x86, x86_64}`, each extracting to a top-level
`java-<major>-openjdk/` dir (`bin/java`, `release`, `lib/server/libjvm.so` —
jdk8 uses the `lib/<arch>/server/` layout). `verifyjre.sh` asserts arch +
embedded VM major + `release` agreement for every archive.

## Building

### Setup
#### Android
- The toolchain scripts download the right NDK automatically (`setdevkitpath.sh`
  picks r10e / r27b / r28 per `JDK_MAJOR`, `maketoolchain.sh` fetches it).
- **Warning**: do not mix NDK versions across majors — it leads to compilation errors.

#### iOS
- Only the jdk8 flow supports iOS. Modern scripts (17/21/25) fail fast on `BUILD_IOS=1`.
- You should get latest Xcode (tested with Xcode 12) for the jdk8 iOS path.

### Platform and architecture specific environment variables
<table>
      <thead>
        <tr>
          <th></th>
          <th align="center" colspan="7">Environment variables</th>
        </tr>
        <tr>
          <th>Platform - Architecture</th>
          <th align="center">TARGET</th>
          <th align="center">TARGET_JDK</th>
        </tr>
      </thead>
      <tbody>
        <tr>
          <td>Android - armv8/aarch64</td>
          <td align="center">aarch64-linux-android</td>
          <td align="center">aarch64</td>
        </tr>
        <tr>
          <td>Android - armv7/aarch32</td>
          <td align="center">arm-linux-androideabi</td>
          <td align="center">arm</td>
        </tr>
        <tr>
          <td>Android - x86/i686</td>
          <td align="center">i686-linux-android</td>
          <td align="center">x86</td>
        </tr>
        <tr>
          <td>Android - x86_64/amd64</td>
          <td align="center">x86_64-linux-android</td>
          <td align="center">x86_64</td>
        </tr>
        <tr>
          <td>iOS/iPadOS - armv8/aarch64</td>
          <td align="center">aarch64-macos-ios</td>
          <td align="center">aarch64</td>
        </tr>
      </tbody>
	</table>

### Run in this directory (JDK 8):
```
export BUILD_IOS=1 # only when targeting iOS, default is 0 (target Android)

export BUILD_FREETYPE_VERSION=[2.6.2/.../2.10.4] # default: 2.10.4
export JDK_DEBUG_LEVEL=[release/fastdebug/debug] # default: release
export JVM_VARIANTS=[client/server] # default: client (aarch32), server (other architectures)

# Setup NDK, run once (Android only)
./extractndk.sh
./maketoolchain.sh

# Get CUPS, Freetype and build Freetype
./getlibs.sh
./buildlibs.sh

# Clone JDK, run once
./clonejdk.sh

# Configure JDK and build, if no configuration is changed, run makejdkwithoutconfigure.sh instead
./buildjdk.sh

# Pack the built JDK
./removejdkdebuginfo.sh
./tarjdk.sh
```

### Run in this directory (JDK 17 / 21 / 25):
```
export JDK_MAJOR=[17/21/25] # required: selects sources, patches, NDK and boot JDK
export BUILD_FREETYPE_VERSION=[2.6.2/.../2.10.4] # default: 2.10.4
export JDK_DEBUG_LEVEL=[release/fastdebug/debug] # default: release

# Setup NDK toolchain, freetype/cups, clone sources, fetch port patches,
# resolve the Temurin boot JDK, configure + build, assemble the jlink JRE,
# then pack it (patch application is fatal on drift — never builds unpatched)
./ci_build_global.sh

# Verify the release archive (arch, VM major, release-file agreement)
./verifyjre.sh jre<MAJOR>-<arch>-<date>-release.tar.xz <MAJOR> <arch>

# Repack into the MineWrap release layout (jre-<major>-<arch>.tar.xz)
JDK_MAJOR=<17|21|25> ./repackjre-modern.sh
```

Per-arch CI entry points (`ci_build_arch_aarch64.sh`, `ci_build_arch_aarch32.sh`,
`ci_build_arch_x86.sh`, `ci_build_arch_x86_64.sh`) set `TARGET`/`TARGET_JDK` and
call `ci_build_global.sh`.

## Notes for device compatibility

- **Heap tagging stays off.** Some vendor ROMs tag every heap pointer (e.g. fixed
  `0xB4` tags) and abort in `free()` on anything else, which kills HotSpot on its
  inline-cache path. All patch sets carry the `android_disable_tags()` hunk in
  `libjli/java.c`, and MineWrap additionally disables tagging in its in-process
  loader before any JVM allocation. Details in [PATCH_SOURCES.md](PATCH_SOURCES.md).
- **Headless only.** Servers run with `-Djava.awt.headless=true`; X11 AWT
  (`libawt_xawt`) is intentionally omitted from modern JREs.
- **Freetype is bundled** inside each modern JRE (`assemble-modern-jre.sh` copies
  the freshly built `libfreetype.so` in, like FCL) — no `.so.6` alias problem.

## License

Free and open source. The OpenJDK sources are GPLv2 with Classpath Exception;
the Android port patches follow their upstreams (see [PATCH_SOURCES.md](PATCH_SOURCES.md)).

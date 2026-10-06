# JDK 17/21/25 source-build pipeline — sources & provenance

All JREs HostCraft ships are built from OpenJDK source with an Android port
patch set. Java 8 has always been built this way here; 17/21/25 used to be
repackaged Termux binaries (which need Termux sibling libs at runtime) and are
now built from source too, so every JRE carries a complete in-JRE native
closure like FoldCraftLauncher's.

## Per-version build matrix

| JDK | Sources | Android port patches | Boot JDK | NDK | Patches live in |
|-----|---------|----------------------|----------|-----|-----------------|
| 8 | `openjdk/jdk8u` (or `aarch32-port-jdk8u` for arm) | `patches/jdk8u_*.diff` (in-repo, Pojav lineage) | self-bootstrapping | r10e + Mojo gcc-13 toolchain | `patches/` |
| 17 | `openjdk/jdk17u` | Pojav `buildjre17-21` → `patches/jre_17/android/*.diff` | 17 (Temurin via `getbootjdk.sh`, or CI `setup-java`) | r27b | `patches/upstream/jre_17/` (vendored 2026-10-06; refresh via `fetch-upstream-patches.sh`) |
| 21 | `openjdk/jdk21u` | Pojav `buildjre17-21` → `patches/jre_21/android/*.diff` | 21 (Temurin via `getbootjdk.sh`, or CI `setup-java`) | r27b | `patches/upstream/jre_21/` (vendored 2026-10-06; refresh via `fetch-upstream-patches.sh`) |
| 25 | `openjdk/jdk25u` | `patches/jdk25u_android.diff` vendored from FCL-Team | 24 (Temurin via `getbootjdk.sh`, or CI `setup-java`, like FCL's jdk-24.0.2) | r28 | `patches/jdk25u_android.diff` |

## Upstream provenance (licenses)

- `patches/jdk25u_android.diff`: vendored copy of
  `FCL-Team/Android-OpenJDK-Build@patches/jdk25u_android.diff`
  (FoldCraftLauncher's JDK build scripts).
- 17/21 patch sets: `PojavLauncherTeam/android-openjdk-build-multiarch`,
  branch `buildjre17-21`, `patches/jre_17/android/` and `patches/jre_21/android/`
  (fetched at build time by `fetch-upstream-patches.sh`; a local
  `patches/jre_<major>/` copy always wins so a known-good set can be pinned).
- Build scripts for modern lines adapt `6_buildjdk.sh` (Pojav `buildjre17-21`)
  and `build_jdk.sh` + `remove_jdk_debug_info.sh` + `tar_jdk.sh`
  (FCL-Team `Android-OpenJDK-Build`); `android-wrapped-clang[++ whoever]` are
  verbatim ports of theirs.
- The OpenJDK sources themselves are GPLv2+CE (unchanged by Android porting).

## Why source-built JREs need no Termux sibling libs

Termux's `openjdk-*` packages are linked against the Termux prefix
(`$PREFIX/lib`), so `libjvm.so` drags in `libandroid-spawn`,
`libandroid-shmem`, Termux `libc++_shared`/`libz`/`libiconv` — the app used to
fetch those at runtime. Source-built JREs link only OS libs
(`libc/libm/libdl`, verifiable with `readelf -d libjvm.so | grep NEEDED`)
because support libs are compiled from source and packed *inside* the JRE:
freetype (`--with-freetype-lib` + copied into `jreout/lib` by
`assemble-modern-jre.sh`, like FCL) and the jdk8 in-tree `tinyiconv`.
The runtime-side Termux fetching in the app (`ensureNativeDepsBlocking`)
stays as a harmless fallback for old installs.

## Layout contract with the app (do not break silently)

- Release archives stay named `jre-<major>-<arch>.tar.xz` with
  `<arch> ∈ {arm,aarch64,x86,x86_64}` (`repackjre-modern.sh` maps the
  `tarjdk.sh` short names onto these) — the app's
  `JavaInstaller.fetchJavaDownloadUrl` depends on these exact names.
- Each archive extracts to a top-level `java-<major>-openjdk/` dir containing
  `bin/java`, `release`, and `lib/server/libjvm.so` (or the jdk8
  `lib/<arch>/server/` layout) — `JvmServerHost.findHome` + `libJvm()`
  depend on this.
- `verifyjre.sh` (CI `verify_all_packages`) asserts arch + embedded VM major
  + `release` agreement for every archive, including the new source-built ones.

## Deliberate omissions vs FCL

- `libawt_xawt.so` / `libjsound.so` APK-side replacement (`patchJava` in FCL):
  HostCraft servers run headless (`-Djava.awt.headless=true`), so X11 AWT and
  the OpenAL sound backend are dead code paths. If GUI jars ever need to run
  in-app, revisit.
- iOS modern builds: the jdk8 iOS flow is untouched; modern scripts fail fast
  on `BUILD_IOS=1`.

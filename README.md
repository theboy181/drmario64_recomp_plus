# Dr. Mario 64: Recompiled Plus

A native recompilation of *Dr. Mario 64* with improved rendering, smoother
motion, and quality-of-life enhancements while remaining faithful to the
original game.

## Features

- GPU-rendered pills
- Smooth 60+ FPS gameplay through interpolation
- Support for four controllers
- CRT effects
- Updated main menu and tuned default Recomp settings
- Custom red and blue capsule icons

## Requirements

You must provide your own clean US copy of *Dr. Mario 64*. No ROM file is
included with this project.

Building requires:

- Git
- C17 and C++20 compilers (Clang 15 or newer is recommended)
- CMake 3.20 or newer
- SDL2
- The project submodules

Platform-specific dependencies and instructions are listed below.

## Prepare the generated sources

These steps are required before building on any platform.

1. Clone the repository and initialize its submodules:

   ```bash
   git clone --recurse-submodules https://github.com/theboy181/drmario64_recomp_plus.git
   cd drmario64_recomp_plus
   ```

   If the repository is already cloned, initialize the submodules with:

   ```bash
   git submodule update --init --recursive
   ```

2. Follow the [`drmario64` decompilation setup](https://github.com/AngheloAlf/drmario64)
   through `make setup`. This project currently uses commit
   `91dab37987bdad4d100958685cc10a011d4917dd`.

3. Copy `baserom_uncompressed.us.z64` from the decompilation repository into
   this repository and rename it to `drmario64_uncompressed.us.z64`.

   Verify that the uncompressed ROM has the expected SHA-1 checksum:

   ```bash
   shasum -a 1 drmario64_uncompressed.us.z64
   ```

   The expected result is:

   ```text
   96ba0ce2f9e98e5790df120320cd3d1a3d7080d2  drmario64_uncompressed.us.z64
   ```

4. Build [`N64Recomp`](https://github.com/Mr-Wiseguy/N64Recomp) at commit
   `a13e5cff96686776b0e03baf23923e3c1927b770`, then copy `N64Recomp` and
   `RSPRecomp` into this repository's root directory.

5. Generate the game and RSP sources:

   ```bash
   ./N64Recomp drmario64.us.toml
   ./RSPRecomp aspMain.us.toml
   ```

## Build on macOS

The macOS build produces a self-contained `drmario64_recomp.app` bundle. The
bundling step supports both Apple silicon and Intel Homebrew installations.

1. Install full Xcode and select its developer directory. The standalone
   Command Line Tools package does not include RT64's required Metal shader
   compiler.

   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   xcrun --find metal
   ```

2. Install the remaining dependencies with [Homebrew](https://brew.sh):

   ```bash
   brew install cmake ninja llvm lld make sdl2-compat sdl3 freetype
   ```

3. Configure and build:

   ```bash
   cmake -S . -B build -G Ninja \
     -DCMAKE_BUILD_TYPE=Release \
     -DCMAKE_C_COMPILER="$(brew --prefix llvm)/bin/clang" \
     -DCMAKE_CXX_COMPILER="$(brew --prefix llvm)/bin/clang++"
   cmake --build build --parallel
   ```

4. Launch the application:

   ```bash
   open build/drmario64_recomp.app
   ```

The local bundle uses an ad-hoc signature and includes its non-system runtime
libraries. Public distribution requires an Apple Developer ID signature and
notarization.

### Create a macOS release package

After preparing the generated sources, create a compatibility-targeted DMG
with:

~~~bash
./.github/macos/package_release.sh
~~~

The script downloads checksum-pinned SDL3, sdl2-compat, libpng, and FreeType
sources, builds them for macOS 11 or newer, builds the application, and writes
the DMG and its SHA-256 file to dist/. It never places a ROM in the application
or disk image.

Without an Apple signing identity, the result is ad-hoc signed and suitable
for local testing. For a public release, provide a Developer ID identity and
a configured notarytool keychain profile:

~~~bash
MACOS_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
MACOS_NOTARY_PROFILE="drmario64-notary" \
./.github/macos/package_release.sh
~~~

## Build on Linux

Install SDL2 and GTK 3 development packages for your distribution. SDL2 may
need to be built from source if your distribution does not provide a compatible
version. Then configure and build with CMake:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
```

## Build on Windows

Use Visual Studio with its C++ desktop development tools. Windows dependency
handling is included in the CMake configuration; configure and build the
project with CMake from a Visual Studio developer environment.

## License

This project is licensed under the [GNU General Public License v3.0](COPYING).
Third-party libraries and assets retain their respective licenses; see the
license files included with those components.

## Status

This project is still lightly tested. Please report reproducible problems with
your operating system, hardware, build type, and the steps needed to trigger
the issue.

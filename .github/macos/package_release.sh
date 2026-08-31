#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR

RELEASE_VERSION="${RELEASE_VERSION:-1.0.0}"
MACOS_ARCH="${MACOS_ARCH:-$(uname -m)}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-11.0}"
DEPS_ROOT="${DEPS_ROOT:-${REPO_ROOT}/build-macos-deps}"
APP_BUILD_DIR="${APP_BUILD_DIR:-${REPO_ROOT}/build-macos-release}"
DIST_DIR="${DIST_DIR:-${REPO_ROOT}/dist}"
PREFIX="${DEPS_ROOT}/prefix"
DOWNLOADS_DIR="${DEPS_ROOT}/downloads"
SOURCES_DIR="${DEPS_ROOT}/sources"
STAGE_DIR="${APP_BUILD_DIR}/dmg-stage"

SDL3_VERSION="3.4.14"
SDL3_SHA256="30d4aa2b3037718142b32dffd4e72f917ebb6cc5227150e7bb9c45efb2153aeb"
SDL2_COMPAT_VERSION="2.32.70"
SDL2_COMPAT_SHA256="998fa62557eb46ffe7e5c3e2c123bc332f7df9d9f593b3ceed88ed1158428a44"
LIBPNG_VERSION="1.6.58"
LIBPNG_SHA256="28eb403f51f0f7405249132cecfe82ea5c0ef97f1b32c5a65828814ae0d34775"
FREETYPE_VERSION="2.14.3"
FREETYPE_SHA256="36bc4f1cc413335368ee656c42afca65c5a3987e8768cc28cf11ba775e785a5f"

SDL3_ARCHIVE="${DOWNLOADS_DIR}/SDL3-${SDL3_VERSION}.tar.gz"
SDL2_COMPAT_ARCHIVE="${DOWNLOADS_DIR}/sdl2-compat-${SDL2_COMPAT_VERSION}.tar.gz"
LIBPNG_ARCHIVE="${DOWNLOADS_DIR}/libpng-${LIBPNG_VERSION}.tar.xz"
FREETYPE_ARCHIVE="${DOWNLOADS_DIR}/freetype-${FREETYPE_VERSION}.tar.xz"

SDL3_SOURCE="${SOURCES_DIR}/SDL3-${SDL3_VERSION}"
SDL2_COMPAT_SOURCE="${SOURCES_DIR}/sdl2-compat-${SDL2_COMPAT_VERSION}"
LIBPNG_SOURCE="${SOURCES_DIR}/libpng-${LIBPNG_VERSION}"
FREETYPE_SOURCE="${SOURCES_DIR}/freetype-${FREETYPE_VERSION}"

APP_NAME="Dr. Mario 64 Recompiled Plus.app"
DMG_NAME="Dr-Mario-64-Recompiled-Plus-${RELEASE_VERSION}-macos-${MACOS_ARCH}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

download_and_verify() {
    local url="$1"
    local destination="$2"
    local checksum="$3"

    if [[ ! -f "${destination}" ]]; then
        curl --fail --location --retry 3 "${url}" --output "${destination}"
    fi

    echo "${checksum}  ${destination}" | shasum -a 256 --check
}

extract_source() {
    local archive="$1"
    local source_dir="$2"

    if [[ ! -d "${source_dir}" ]]; then
        tar -xf "${archive}" -C "${SOURCES_DIR}"
    fi
}

for command_name in brew cmake codesign curl hdiutil ninja shasum tar; do
    require_command "${command_name}"
done

if [[ ! -d "${DEVELOPER_DIR}" ]]; then
    echo "Full Xcode was not found at ${DEVELOPER_DIR}" >&2
    exit 1
fi

if ! xcrun --find metal >/dev/null 2>&1; then
    echo "Xcode's Metal Toolchain component is required." >&2
    exit 1
fi

if [[ ! -d "${REPO_ROOT}/RecompiledFuncs" || ! -f "${REPO_ROOT}/RecompiledPatches/patches.c" ]]; then
    echo "Generated game sources are missing; complete the README setup first." >&2
    exit 1
fi

mkdir -p "${DOWNLOADS_DIR}" "${SOURCES_DIR}" "${PREFIX}" "${DIST_DIR}"

download_and_verify \
    "https://github.com/libsdl-org/SDL/releases/download/release-${SDL3_VERSION}/SDL3-${SDL3_VERSION}.tar.gz" \
    "${SDL3_ARCHIVE}" "${SDL3_SHA256}"
download_and_verify \
    "https://github.com/libsdl-org/sdl2-compat/releases/download/release-${SDL2_COMPAT_VERSION}/sdl2-compat-${SDL2_COMPAT_VERSION}.tar.gz" \
    "${SDL2_COMPAT_ARCHIVE}" "${SDL2_COMPAT_SHA256}"
download_and_verify \
    "https://download.sourceforge.net/libpng/libpng-${LIBPNG_VERSION}.tar.xz" \
    "${LIBPNG_ARCHIVE}" "${LIBPNG_SHA256}"
download_and_verify \
    "https://download.savannah.gnu.org/releases/freetype/freetype-${FREETYPE_VERSION}.tar.xz" \
    "${FREETYPE_ARCHIVE}" "${FREETYPE_SHA256}"

extract_source "${SDL3_ARCHIVE}" "${SDL3_SOURCE}"
extract_source "${SDL2_COMPAT_ARCHIVE}" "${SDL2_COMPAT_SOURCE}"
extract_source "${LIBPNG_ARCHIVE}" "${LIBPNG_SOURCE}"
extract_source "${FREETYPE_ARCHIVE}" "${FREETYPE_SOURCE}"

cmake -S "${SDL3_SOURCE}" -B "${DEPS_ROOT}/build-sdl3" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DCMAKE_OSX_ARCHITECTURES="${MACOS_ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DSDL_SHARED=ON \
    -DSDL_STATIC=OFF \
    -DSDL_HIDAPI_LIBUSB=OFF \
    -DSDL_TEST_LIBRARY=OFF \
    -DSDL_TESTS=OFF \
    -DSDL_EXAMPLES=OFF \
    -DSDL_INSTALL=ON \
    -DSDL_INSTALL_CPACK=OFF \
    -DSDL_INSTALL_DOCS=OFF
cmake --build "${DEPS_ROOT}/build-sdl3" --parallel
cmake --install "${DEPS_ROOT}/build-sdl3"

cmake -S "${SDL2_COMPAT_SOURCE}" -B "${DEPS_ROOT}/build-sdl2-compat" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_OSX_ARCHITECTURES="${MACOS_ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DCMAKE_PREFIX_PATH="${PREFIX}" \
    -DSDL3_DIR="${PREFIX}/lib/cmake/SDL3" \
    -DSDL2COMPAT_TESTS=OFF \
    -DSDL2COMPAT_INSTALL=ON \
    -DSDL2COMPAT_INSTALL_CPACK=OFF
cmake --build "${DEPS_ROOT}/build-sdl2-compat" --parallel
cmake --install "${DEPS_ROOT}/build-sdl2-compat"

cmake -S "${LIBPNG_SOURCE}" -B "${DEPS_ROOT}/build-libpng" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_OSX_ARCHITECTURES="${MACOS_ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DPNG_SHARED=ON \
    -DPNG_STATIC=OFF \
    -DPNG_FRAMEWORK=OFF \
    -DPNG_TESTS=OFF \
    -DPNG_TOOLS=OFF
cmake --build "${DEPS_ROOT}/build-libpng" --parallel
cmake --install "${DEPS_ROOT}/build-libpng"

cmake -S "${FREETYPE_SOURCE}" -B "${DEPS_ROOT}/build-freetype" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_OSX_ARCHITECTURES="${MACOS_ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}" \
    -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
    -DPNG_LIBRARY="${PREFIX}/lib/libpng16.dylib" \
    -DPNG_PNG_INCLUDE_DIR="${PREFIX}/include" \
    -DBUILD_SHARED_LIBS=ON \
    -DFT_DISABLE_BZIP2=TRUE \
    -DFT_DISABLE_BROTLI=TRUE \
    -DFT_DISABLE_HARFBUZZ=TRUE \
    -DFT_DISABLE_PNG=FALSE
cmake --build "${DEPS_ROOT}/build-freetype" --parallel
cmake --install "${DEPS_ROOT}/build-freetype"

LLVM_PREFIX="$(brew --prefix llvm)"
LLD_PREFIX="$(brew --prefix lld)"
PATCHES_C_COMPILER="${PATCHES_C_COMPILER:-${LLVM_PREFIX}/bin/clang}"
PATCHES_LD="${PATCHES_LD:-${LLD_PREFIX}/bin/ld.lld}"

cmake -S "${REPO_ROOT}" -B "${APP_BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DCMAKE_AR="${LLVM_PREFIX}/bin/llvm-ar" \
    -DCMAKE_OSX_ARCHITECTURES="${MACOS_ARCH}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}" \
    -DCMAKE_PREFIX_PATH="${PREFIX}" \
    -DSDL2_DIR="${PREFIX}/lib/cmake/SDL2" \
    -DSDL3_COMPAT_RUNTIME="${PREFIX}/lib/libSDL3.0.dylib" \
    -DMACOS_BUNDLE_LIBRARY_DIR="${PREFIX}/lib" \
    -DPATCHES_C_COMPILER="${PATCHES_C_COMPILER}" \
    -DPATCHES_LD="${PATCHES_LD}"
cmake --build "${APP_BUILD_DIR}" --parallel

BUILT_APP="${APP_BUILD_DIR}/drmario64_recomp.app"
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:--}"
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    codesign --deep --force --options runtime --timestamp \
        --entitlements "${REPO_ROOT}/.github/macos/entitlements.plist" \
        --sign "${SIGN_IDENTITY}" "${BUILT_APP}"
fi
codesign --verify --deep --strict --verbose=2 "${BUILT_APP}"

ROM_FILE="$(find "${BUILT_APP}" -type f \( -iname '*.z64' -o -iname '*.n64' -o -iname '*.v64' \) -print -quit)"
if [[ -n "${ROM_FILE}" ]]; then
    echo "Refusing to package ROM file: ${ROM_FILE}" >&2
    exit 1
fi

cmake -E remove_directory "${STAGE_DIR}"
mkdir -p "${STAGE_DIR}/Licenses"
ditto "${BUILT_APP}" "${STAGE_DIR}/${APP_NAME}"
ln -s /Applications "${STAGE_DIR}/Applications"
cp "${REPO_ROOT}/COPYING" "${STAGE_DIR}/Licenses/Dr-Mario-64-Recompiled-Plus-GPL-3.0.txt"
cp "${SDL3_SOURCE}/LICENSE.txt" "${STAGE_DIR}/Licenses/SDL3-Zlib.txt"
cp "${SDL2_COMPAT_SOURCE}/LICENSE.txt" "${STAGE_DIR}/Licenses/sdl2-compat-Zlib.txt"
cp "${LIBPNG_SOURCE}/LICENSE" "${STAGE_DIR}/Licenses/libpng.txt"
cp "${FREETYPE_SOURCE}/LICENSE.TXT" "${STAGE_DIR}/Licenses/FreeType.txt"
cp "${FREETYPE_SOURCE}/docs/FTL.TXT" "${STAGE_DIR}/Licenses/FreeType-License.txt"

hdiutil create -ov -format UDZO \
    -volname "Dr. Mario 64 Recompiled Plus" \
    -srcfolder "${STAGE_DIR}" \
    "${DMG_PATH}"

if [[ "${SIGN_IDENTITY}" != "-" ]]; then
    codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG_PATH}"
fi

if [[ -n "${MACOS_NOTARY_PROFILE:-}" ]]; then
    if [[ "${SIGN_IDENTITY}" == "-" ]]; then
        echo "MACOS_SIGN_IDENTITY is required for notarization." >&2
        exit 1
    fi
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${MACOS_NOTARY_PROFILE}" --wait
    xcrun stapler staple "${DMG_PATH}"
fi

hdiutil verify "${DMG_PATH}"
(
    cd "${DIST_DIR}"
    shasum -a 256 "${DMG_NAME}" | tee "${DMG_NAME}.sha256"
)
echo "Release package: ${DMG_PATH}"

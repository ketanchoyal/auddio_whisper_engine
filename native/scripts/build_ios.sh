#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${NATIVE_DIR}/build/ios"
OUT_DIR="${NATIVE_DIR}/build/output"
DEPLOYMENT_TARGET="15.0"

"${SCRIPT_DIR}/fetch_whisper.sh"

build_slice() {
  local name="$1" sysroot="$2" archs="$3" simulator="$4"
  local dir="${BUILD_ROOT}/${name}"
  rm -rf "${dir}"
  cmake -S "${NATIVE_DIR}" -B "${dir}" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${sysroot}" \
    -DCMAKE_OSX_ARCHITECTURES="${archs}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_COREML=ON \
    -DGGML_OPENMP=OFF
  cmake --build "${dir}" --config Release
}

build_slice "device" "iphoneos" "arm64" "NO"
build_slice "simulator" "iphonesimulator" "arm64;x86_64" "YES"

rm -rf "${OUT_DIR}/libauddio_whisper.xcframework"
mkdir -p "${OUT_DIR}"
xcodebuild -create-xcframework \
  -framework "${BUILD_ROOT}/device/Release-iphoneos/auddio_whisper.framework" \
  -framework "${BUILD_ROOT}/simulator/Release-iphonesimulator/auddio_whisper.framework" \
  -output "${OUT_DIR}/libauddio_whisper.xcframework"

echo "Built ${OUT_DIR}/libauddio_whisper.xcframework"

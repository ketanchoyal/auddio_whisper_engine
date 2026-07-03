#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${NATIVE_DIR}/build/ios"
OUT_DIR="${NATIVE_DIR}/build/output"
DEPLOYMENT_TARGET="16.4"

"${SCRIPT_DIR}/fetch_whisper.sh"

build_slice() {
  local name="$1" sysroot="$2" archs="$3" accel="$4"
  local dir="${BUILD_ROOT}/${name}"
  rm -rf "${dir}"
  # The iOS Simulator's Metal driver (MTLSimDevice) aborts in ggml-metal during
  # buffer init, so the simulator slice is built CPU-only (no Metal/CoreML). The
  # device slice keeps full Metal + CoreML acceleration. Runtime detection can't
  # gate this: iOS doesn't expose env vars to Platform.environment, so the only
  # reliable guard is to omit the Metal code from the simulator binary entirely.
  local accel_flags
  if [ "${accel}" = "ON" ]; then
    accel_flags=(-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON
                 -DWHISPER_COREML=ON -DWHISPER_COREML_ALLOW_FALLBACK=ON)
  else
    accel_flags=(-DGGML_METAL=OFF -DWHISPER_COREML=OFF)
  fi
  cmake -S "${NATIVE_DIR}" -B "${dir}" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="${sysroot}" \
    -DCMAKE_OSX_ARCHITECTURES="${archs}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
    -DCMAKE_XCODE_ATTRIBUTE_ONLY_ACTIVE_ARCH=NO \
    "${accel_flags[@]}" \
    -DGGML_OPENMP=OFF
  cmake --build "${dir}" --config Release
}

build_slice "device" "iphoneos" "arm64" "ON"
build_slice "simulator" "iphonesimulator" "arm64;x86_64" "OFF"

rm -rf "${OUT_DIR}/ios/auddio_whisper.xcframework"
mkdir -p "${OUT_DIR}/ios"
xcodebuild -create-xcframework \
  -framework "${BUILD_ROOT}/device/Release-iphoneos/auddio_whisper.framework" \
  -framework "${BUILD_ROOT}/simulator/Release-iphonesimulator/auddio_whisper.framework" \
  -output "${OUT_DIR}/ios/auddio_whisper.xcframework"

echo "Built ${OUT_DIR}/ios/auddio_whisper.xcframework"

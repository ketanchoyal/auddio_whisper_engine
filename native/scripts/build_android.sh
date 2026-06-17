#!/usr/bin/env bash
set -euo pipefail

: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to your NDK path}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_ROOT="${NATIVE_DIR}/build/android"
OUT_DIR="${NATIVE_DIR}/build/output/jniLibs"
MIN_SDK="24"

"${SCRIPT_DIR}/fetch_whisper.sh"

build_abi() {
  local abi="$1" extra="$2"
  local dir="${BUILD_ROOT}/${abi}"
  rm -rf "${dir}"
  cmake -S "${NATIVE_DIR}" -B "${dir}" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="${abi}" \
    -DANDROID_PLATFORM="android-${MIN_SDK}" \
    -DANDROID_STL=c++_shared \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_USE_CPU=ON \
    -DGGML_METAL=OFF \
    -DWHISPER_COREML=OFF \
    -DGGML_OPENMP=OFF \
    -DCMAKE_C_FLAGS="${extra}" \
    -DCMAKE_CXX_FLAGS="${extra}"
  cmake --build "${dir}"
  mkdir -p "${OUT_DIR}/${abi}"
  cp "${dir}/libauddio_whisper.so" "${OUT_DIR}/${abi}/libauddio_whisper.so"
}

build_abi "arm64-v8a" "-march=armv8.2-a+fp16"
build_abi "armeabi-v7a" "-mfpu=neon-vfpv4"
build_abi "x86_64" ""

echo "Built Android .so libraries into ${OUT_DIR}"

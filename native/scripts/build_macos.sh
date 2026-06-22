#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${NATIVE_DIR}/build/macos"
OUT_DIR="${NATIVE_DIR}/build/output"
DEPLOYMENT_TARGET="13.3"

"${SCRIPT_DIR}/fetch_whisper.sh"

rm -rf "${BUILD_DIR}"
cmake -S "${NATIVE_DIR}" -B "${BUILD_DIR}" -G Xcode \
  -DCMAKE_SYSTEM_NAME=Darwin \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
  -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DWHISPER_COREML=ON \
  -DWHISPER_COREML_ALLOW_FALLBACK=ON \
  -DGGML_OPENMP=OFF
cmake --build "${BUILD_DIR}" --config Release

rm -rf "${OUT_DIR}/libauddio_whisper.macos.xcframework"
mkdir -p "${OUT_DIR}"
xcodebuild -create-xcframework \
  -framework "${BUILD_DIR}/Release/auddio_whisper.framework" \
  -output "${OUT_DIR}/libauddio_whisper.macos.xcframework"

echo "Built ${OUT_DIR}/libauddio_whisper.macos.xcframework"

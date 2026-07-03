#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/build/output"
REL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/build/release"

sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

rm -rf "${REL_DIR}"
mkdir -p "${REL_DIR}"

# Artifact names MUST match the download URLs in ios/macos podspec and
# android/build.gradle.kts exactly, or runtime download fails.
zip_xcframework() {
  local label="$1" src="$2" asset="$3"
  if [ ! -d "${src}" ]; then
    echo "${label}: MISSING (${src}) -- run the build script first"
    return
  fi
  ( cd "$(dirname "${src}")" && zip -qry "${REL_DIR}/${asset}" "$(basename "${src}")" )
  echo "${label}: $(sha "${REL_DIR}/${asset}")  ${asset}"
}

zip_xcframework "ios" \
  "${OUT_DIR}/ios/auddio_whisper.xcframework" \
  "libauddio_whisper_ios.xcframework.zip"
zip_xcframework "macos" \
  "${OUT_DIR}/macos/auddio_whisper.xcframework" \
  "libauddio_whisper_macos.xcframework.zip"

for abi in arm64-v8a armeabi-v7a x86_64; do
  so="${OUT_DIR}/jniLibs/${abi}/libauddio_whisper.so"
  [ -e "${so}" ] || { echo "android ${abi}: MISSING (${so})"; continue; }
  cp "${so}" "${REL_DIR}/libauddio_whisper-${abi}.so"
  echo "android ${abi}: $(sha "${REL_DIR}/libauddio_whisper-${abi}.so")  libauddio_whisper-${abi}.so"
done

echo ""
echo "Release artifacts staged in: ${REL_DIR}"

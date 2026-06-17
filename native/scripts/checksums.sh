#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/build/output"

sha() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

zip_and_hash() {
  local label="$1" path="$2"
  if [ ! -e "${path}" ]; then
    echo "${label}: MISSING (${path})"
    return
  fi
  local zip="${path%.xcframework}.xcframework.zip"
  rm -f "${zip}"
  ( cd "$(dirname "${path}")" && zip -qry "$(basename "${zip}")" "$(basename "${path}")" )
  echo "${label}: $(sha "${zip}")  -> ${zip}"
}

zip_and_hash "ios-xcframework" "${OUT_DIR}/libauddio_whisper.xcframework"
zip_and_hash "macos-xcframework" "${OUT_DIR}/libauddio_whisper.macos.xcframework"

if [ -d "${OUT_DIR}/jniLibs" ]; then
  for so in "${OUT_DIR}"/jniLibs/*/libauddio_whisper.so; do
    [ -e "${so}" ] || continue
    echo "android $(basename "$(dirname "${so}")"): $(sha "${so}")  -> ${so}"
  done
fi

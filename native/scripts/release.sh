#!/usr/bin/env bash
set -euo pipefail

# One-shot release: build all platforms, stage correctly-named artifacts,
# create the GitHub release, and print the SHA-256s to paste into the
# podspecs and android/build.gradle.kts.
#
# Prerequisites (run on macOS):
#   - Xcode + command line tools (iOS/macOS + CoreML coremlc)
#   - ANDROID_NDK_HOME exported (for build_android.sh)
#   - gh CLI authenticated (gh auth login)
#
# Usage: native/scripts/release.sh [TAG]   (default TAG = whisper-v0.0.1)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${1:-whisper-v0.0.1}"
REPO="ketanchoyal/auddio_whisper_engine"
REL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)/build/release"

missing=()
for tool in cmake ninja xcodebuild gh zip; do
  command -v "${tool}" >/dev/null 2>&1 || missing+=("${tool}")
done
[ -n "${ANDROID_NDK_HOME:-}" ] || missing+=("ANDROID_NDK_HOME (env var)")
if [ "${#missing[@]}" -gt 0 ]; then
  echo "ERROR: missing prerequisites:" >&2
  printf '  - %s\n' "${missing[@]}" >&2
  echo "Install CLI tools with: brew install cmake ninja gh" >&2
  exit 1
fi

echo ">> Building iOS..."
"${SCRIPT_DIR}/build_ios.sh"
echo ">> Building macOS..."
"${SCRIPT_DIR}/build_macos.sh"
echo ">> Building Android..."
"${SCRIPT_DIR}/build_android.sh"

echo ">> Staging artifacts + computing checksums..."
"${SCRIPT_DIR}/checksums.sh" | tee "${REL_DIR}/SHA256SUMS.txt"

echo ">> Creating GitHub release ${TAG} on ${REPO}..."
gh release create "${TAG}" \
  --repo "${REPO}" \
  --title "${TAG}" \
  --notes "Prebuilt whisper.cpp engine binaries for auddio_whisper_engine." \
  "${REL_DIR}/libauddio_whisper_ios.xcframework.zip" \
  "${REL_DIR}/libauddio_whisper_macos.xcframework.zip" \
  "${REL_DIR}/libauddio_whisper-arm64-v8a.so" \
  "${REL_DIR}/libauddio_whisper-armeabi-v7a.so" \
  "${REL_DIR}/libauddio_whisper-x86_64.so"

echo ""
echo ">> Done. Paste the SHA-256s above into:"
echo "   ios/auddio_whisper_engine.podspec   (EXPECTED_SHA256)"
echo "   macos/auddio_whisper_engine.podspec (EXPECTED_SHA256)"
echo "   android/build.gradle.kts            (3x per-ABI sha256)"

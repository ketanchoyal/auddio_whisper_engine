#!/usr/bin/env bash
set -euo pipefail

WHISPER_COMMIT="306c88f4d1286aec1bf96e544632897886af5501"
WHISPER_REPO="https://github.com/ggml-org/whisper.cpp.git"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${SCRIPT_DIR}/../third_party/whisper.cpp"

if [ -d "${DEST}/.git" ]; then
  CURRENT="$(git -C "${DEST}" rev-parse HEAD)"
  if [ "${CURRENT}" != "${WHISPER_COMMIT}" ]; then
    echo "Updating whisper.cpp to pinned commit ${WHISPER_COMMIT}"
    git -C "${DEST}" fetch --depth 1 origin "${WHISPER_COMMIT}"
    git -C "${DEST}" checkout --force "${WHISPER_COMMIT}"
  else
    echo "whisper.cpp already at pinned commit ${WHISPER_COMMIT}"
  fi
else
  mkdir -p "${DEST}"
  git -C "${DEST}" init -q
  git -C "${DEST}" remote add origin "${WHISPER_REPO}"
  git -C "${DEST}" fetch --depth 1 origin "${WHISPER_COMMIT}"
  git -C "${DEST}" checkout --force "${WHISPER_COMMIT}"
  echo "Fetched whisper.cpp @ ${WHISPER_COMMIT}"
fi

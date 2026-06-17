#!/usr/bin/env bash
# MUST be sourced, not executed: it exports ANDROID_NDK_HOME into the caller's
# shell, which only works when sourced (a subprocess can't mutate its parent's
# environment).

awe_brew_pkg_for() {
  case "$1" in
    cmake) echo cmake ;;
    ninja) echo ninja ;;
    gh) echo gh ;;
    zip) echo zip ;;
    *) echo "$1" ;;
  esac
}

awe_setup_prereqs() {
  local cli_tools="cmake ninja gh zip"

  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "ERROR: xcodebuild not found. Install Xcode from the App Store, then" >&2
    echo "       run: sudo xcode-select -s /Applications/Xcode.app" >&2
    return 1
  fi

  for tool in ${cli_tools}; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      if ! command -v brew >/dev/null 2>&1; then
        echo "ERROR: ${tool} missing and Homebrew not installed." >&2
        echo "       Install Homebrew from https://brew.sh then re-run." >&2
        return 1
      fi
      echo ">> Installing ${tool} via Homebrew..."
      brew install "$(awe_brew_pkg_for "${tool}")" || return 1
    fi
  done

  if [ -n "${ANDROID_NDK_HOME:-}" ] && [ -d "${ANDROID_NDK_HOME}" ]; then
    echo ">> ANDROID_NDK_HOME already set: ${ANDROID_NDK_HOME}"
    return 0
  fi

  local ndk_root="${HOME}/Library/Android/sdk/ndk"
  if [ ! -d "${ndk_root}" ]; then
    echo "ERROR: no NDK dir at ${ndk_root}. Install via Android Studio" >&2
    echo "       (SDK Manager > SDK Tools > NDK) or:" >&2
    echo "       sdkmanager --install 'ndk;28.2.13676358'" >&2
    return 1
  fi

  # Prefer the version mpv_audio_kit pins (known-good for this project), else
  # fall back to the highest installed version.
  local preferred="28.2.13676358"
  local chosen=""
  if [ -d "${ndk_root}/${preferred}" ]; then
    chosen="${preferred}"
  else
    chosen="$(ls -1 "${ndk_root}" | sort -V | tail -1)"
  fi

  if [ -z "${chosen}" ] || [ ! -d "${ndk_root}/${chosen}" ]; then
    echo "ERROR: could not resolve an NDK under ${ndk_root}" >&2
    return 1
  fi

  export ANDROID_NDK_HOME="${ndk_root}/${chosen}"
  echo ">> ANDROID_NDK_HOME set to ${ANDROID_NDK_HOME}"
  return 0
}

awe_setup_prereqs

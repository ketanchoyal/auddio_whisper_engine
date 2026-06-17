#
# auddio_whisper_engine iOS podspec
#
# The native whisper.cpp engine ships as a prebuilt libauddio_whisper.xcframework
# (device arm64 + simulator arm64/x86_64) downloaded from GitHub Releases and
# SHA-256 verified, mirroring the mpv_audio_kit delivery model. The Dart side
# loads it via DynamicLibrary.open. Build it with native/scripts/build_ios.sh.
#
Pod::Spec.new do |s|
  s.name             = 'auddio_whisper_engine'
  s.version          = '0.0.1'
  s.summary          = 'Prebuilt whisper.cpp engine (Metal + CoreML) for Audiio.'
  s.description      = 'On-device chapter transcription with per-word DTW timestamps.'
  s.homepage         = 'https://github.com/ketanchoyal/audiio'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Audiio' => 'audiio.app' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.dependency 'Flutter'

  # CoreML + Foundation: CoreML encoder path. Metal + Accelerate: ggml GPU/BLAS.
  s.frameworks = 'CoreML', 'Foundation', 'Metal', 'Accelerate'

  # ── Prebuilt xcframework ──────────────────────────────────────────────────
  # TODO(release): set RELEASE_TAG + EXPECTED_SHA256 after running
  # native/scripts/build_ios.sh and native/scripts/checksums.sh, then uploading
  # the zip to GitHub Releases. Decide the host repo first (see plan open Qs).
  s.prepare_command = <<-CMD
    RELEASE_TAG="whisper-v0.0.1"
    EXPECTED_SHA256="REPLACE_WITH_IOS_XCFRAMEWORK_SHA256"
    URL="https://github.com/ketanchoyal/audiio/releases/download/${RELEASE_TAG}/libauddio_whisper_ios.xcframework.zip"

    mkdir -p Frameworks
    ZIP_FILE="Frameworks/libauddio_whisper_xcframework.zip"
    DOWNLOAD_NEEDED=1

    if [ -f "Frameworks/libauddio_whisper.xcframework/Info.plist" ] && [ -f "$ZIP_FILE" ]; then
      ACTUAL_SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{ print $1 }')
      if [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ]; then
        DOWNLOAD_NEEDED=0
      else
        rm -rf "Frameworks/libauddio_whisper.xcframework" "$ZIP_FILE"
      fi
    elif [ -d "Frameworks/libauddio_whisper.xcframework" ] && [ ! -f "$ZIP_FILE" ]; then
      DOWNLOAD_NEEDED=0
    fi

    # awe:remote:begin
    if [ $DOWNLOAD_NEEDED -eq 1 ]; then
      curl -L -o "$ZIP_FILE" "$URL"
      ACTUAL_SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{ print $1 }')
      if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo "ERROR: SHA-256 verification failed for $ZIP_FILE"
        rm -f "$ZIP_FILE"
        exit 1
      fi
      unzip -o "$ZIP_FILE" -d Frameworks/
      rm -f "$ZIP_FILE"
    fi
    # awe:remote:end
  CMD

  s.vendored_frameworks = 'Frameworks/libauddio_whisper.xcframework'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end

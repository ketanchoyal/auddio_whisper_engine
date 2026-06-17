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
  s.homepage         = 'https://github.com/ketanchoyal/auddio_whisper_engine'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Audiio' => 'audiio.app' }
  s.source           = { :path => '.' }
  s.platform         = :ios, '15.0'
  s.dependency 'Flutter'

  # CoreML + Foundation: CoreML encoder path. Metal + Accelerate: ggml GPU/BLAS.
  s.frameworks = 'CoreML', 'Foundation', 'Metal', 'Accelerate'

  # ── Prebuilt xcframework ──────────────────────────────────────────────────
  s.prepare_command = <<-CMD
    RELEASE_TAG="whisper-v0.0.1"
    REPO="ketanchoyal/auddio_whisper_engine"
    ASSET="libauddio_whisper_ios.xcframework.zip"
    EXPECTED_SHA256="731ddf817ec2e6af281ea34cded67796ac23b3a102bffb7e56833d67738ed1bc"

    mkdir -p Frameworks
    ZIP_FILE="Frameworks/libauddio_whisper_xcframework.zip"
    DOWNLOAD_NEEDED=1

    if [ -f "Frameworks/auddio_whisper.xcframework/Info.plist" ] && [ -f "$ZIP_FILE" ]; then
      ACTUAL_SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{ print $1 }')
      if [ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ]; then
        DOWNLOAD_NEEDED=0
      else
        rm -rf "Frameworks/auddio_whisper.xcframework" "$ZIP_FILE"
      fi
    elif [ -d "Frameworks/auddio_whisper.xcframework" ] && [ ! -f "$ZIP_FILE" ]; then
      DOWNLOAD_NEEDED=0
    fi

    # awe:remote:begin
    # Private release: gh authenticates (respects GH_TOKEN/GITHUB_TOKEN in CI).
    if [ $DOWNLOAD_NEEDED -eq 1 ]; then
      if ! command -v gh >/dev/null 2>&1; then
        echo "ERROR: gh CLI required for the private release asset. Install gh + 'gh auth login' (or set GH_TOKEN)." >&2
        exit 1
      fi
      gh release download "$RELEASE_TAG" --repo "$REPO" --pattern "$ASSET" --output "$ZIP_FILE" --clobber || {
        echo "ERROR: gh release download failed for $ASSET" >&2
        exit 1
      }
      ACTUAL_SHA256=$(shasum -a 256 "$ZIP_FILE" | awk '{ print $1 }')
      if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
        echo "ERROR: SHA-256 verification failed for $ZIP_FILE"
        rm -f "$ZIP_FILE"
        exit 1
      fi
      unzip -o "$ZIP_FILE" -d Frameworks/
      rm -f "$ZIP_FILE"
      # CocoaPods derives the -framework link name from the xcframework
      # basename, so it MUST equal the inner framework (auddio_whisper.framework).
      # The release zip unzips to libauddio_whisper.xcframework; rename it.
      if [ -d "Frameworks/libauddio_whisper.xcframework" ]; then
        rm -rf "Frameworks/auddio_whisper.xcframework"
        mv "Frameworks/libauddio_whisper.xcframework" "Frameworks/auddio_whisper.xcframework"
      fi
    fi
    # awe:remote:end
  CMD

  s.vendored_frameworks = 'Frameworks/auddio_whisper.xcframework'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end

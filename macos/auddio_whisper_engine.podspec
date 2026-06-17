#
# auddio_whisper_engine macOS podspec
#
# Prebuilt libauddio_whisper.xcframework (arm64 + x86_64) downloaded from
# GitHub Releases and SHA-256 verified. Loaded via DynamicLibrary.open.
# Build it with native/scripts/build_macos.sh.
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
  s.platform         = :osx, '12.0'
  s.dependency 'FlutterMacOS'

  s.frameworks = 'CoreML', 'Foundation', 'Metal', 'Accelerate'

  s.prepare_command = <<-CMD
    RELEASE_TAG="whisper-v0.0.1"
    REPO="ketanchoyal/auddio_whisper_engine"
    ASSET="libauddio_whisper_macos.xcframework.zip"
    EXPECTED_SHA256="8f31fafd34568a47f2eb54ca7ea47e342d4146a6f0afee9365512cd606546f78"

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
      # The macOS release zip unzips to libauddio_whisper.macos.xcframework
      # (the .macos suffix keeps it distinct from the iOS build). CocoaPods
      # derives the -framework link name from the xcframework basename, so it
      # MUST equal the inner framework (auddio_whisper.framework); rename it.
      if [ -d "Frameworks/libauddio_whisper.macos.xcframework" ]; then
        rm -rf "Frameworks/auddio_whisper.xcframework"
        mv "Frameworks/libauddio_whisper.macos.xcframework" "Frameworks/auddio_whisper.xcframework"
      fi
    fi
    # awe:remote:end
  CMD

  s.vendored_frameworks = 'Frameworks/auddio_whisper.xcframework'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end

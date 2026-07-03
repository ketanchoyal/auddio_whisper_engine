# auddio_whisper_engine

Custom whisper.cpp FFI engine for Auddio chapter transcription, with per-word
(DTW) timestamps. Ships as a prebuilt native library (Metal + CoreML on Apple,
CPU/NEON on Android) downloaded from this repo's GitHub Releases at build time
and loaded via `dart:ffi`.

## Releasing a new build

Everything is driven by one script. From the package root:

```bash
native/scripts/release.sh            # bumps the patch version (0.0.1 -> 0.0.2)
native/scripts/release.sh minor      # 0.0.1 -> 0.1.0
native/scripts/release.sh major      # 0.0.1 -> 1.0.0
```

What it does, in order:

1. Reads the current `version:` from `pubspec.yaml` and computes the next one.
2. Builds the native library for all platforms (iOS, macOS, Android).
3. Creates a **new** GitHub Release tagged `whisper-v<version>` and uploads the
   5 binaries (iOS + macOS xcframework zips, and one `.so` per Android ABI).
4. Bumps `pubspec.yaml` to the new version.
5. Regenerates `release.properties` — the single file holding the release tag
   and the 5 SHA-256 checksums.

Each run publishes a distinct version; it never overwrites an existing tag (it
errors out if the tag already exists).

### Prerequisites (macOS)

- Xcode + command line tools (needed for iOS/macOS + CoreML).
- `gh` authenticated (`gh auth login`) — required only for the developer publishing new GitHub releases. Consumers do not need `gh` since the repo is public.
- Android NDK. `release.sh` sources `setup_prereqs.sh`, which auto-installs the
  CLI tools and resolves `ANDROID_NDK_HOME` for you.

### After releasing

Commit the changed files so consumers pick up the new build:

```bash
git add pubspec.yaml release.properties ios/auddio_whisper_engine/Package.swift macos/auddio_whisper_engine/Package.swift
git commit -m "release whisper-v<version>"
git push
```

## How consumers get the binary

`release.properties` and the `Package.swift` manifests are the sources of truth:

- **iOS / macOS (SPM)** — Swift Package Manager downloads the prebuilt binary framework directly from the GitHub Release assets based on the URL and checksum defined in `Package.swift`.
- **iOS / macOS (CocoaPods fallback)** — The podspec's `prepare_command` downloads the xcframework zip via a public HTTPS URL using `curl`, verifies its SHA-256, and vendors it.
- **Android** — `build.gradle.kts` downloads each ABI `.so` via a public HTTPS URL in Kotlin, verifies its SHA-256, and drops it into `jniLibs/`.

No manual SHA editing is needed; everything is handled dynamically or rewritten during the release process.

## Layout

```
lib/                     Dart FFI bindings + AuddioWhisperEngine
native/
  include/, src/         C-ABI bridge over whisper.cpp
  scripts/release.sh     build + publish + regenerate release.properties
  third_party/           vendored whisper.cpp (pinned, fetched by the scripts)
ios/, macos/, android/   platform plugin manifests (read release.properties)
release.properties       generated: tag + SHA-256s (commit this)
```

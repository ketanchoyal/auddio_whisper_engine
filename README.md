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
- `gh` authenticated (`gh auth login`) — the release repo is private.
- Android NDK. `release.sh` sources `setup_prereqs.sh`, which auto-installs the
  CLI tools and resolves `ANDROID_NDK_HOME` for you.

### After releasing

Commit the two changed files so consumers pick up the new build:

```bash
git add pubspec.yaml release.properties
git commit -m "release whisper-v<version>"
git push
```

## How consumers get the binary

`release.properties` is the source of truth. None of the build files hardcode a
tag or checksum — they read it:

- **iOS / macOS** — the podspec's `prepare_command` downloads the xcframework
  for `RELEASE_TAG` via `gh`, verifies its SHA-256, and vendors it.
- **Android** — `build.gradle.kts` downloads each ABI `.so` via `gh`, verifies
  its SHA-256, and drops it into `jniLibs/`.

So updating the engine is just: run `release.sh`, commit, push. No manual SHA
editing anywhere.

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

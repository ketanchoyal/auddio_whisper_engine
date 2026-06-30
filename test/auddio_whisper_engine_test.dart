import 'package:auddio_whisper_engine/auddio_whisper_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke tests for the FFI surface. They require the prebuilt
/// `libauddio_whisper` native library, which is downloaded from GitHub
/// Releases at build time and is NOT present in a plain `flutter test` run.
/// Each test therefore skips itself when the library cannot be opened, so the
/// suite is green before binaries exist and becomes meaningful once they do.
void main() {
  bool libraryAvailable() {
    try {
      AuddioWhisperEngine.open(modelPath: 'nonexistent.bin');
    } on WhisperEngineException {
      // Library loaded; init failed on the bogus path, which is the point.
      return true;
    } catch (_) {
      return false;
    }
    return true;
  }

  test('opening with a missing model throws WhisperEngineException', () {
    if (!libraryAvailable()) {
      markTestSkipped('native libauddio_whisper not available');
      return;
    }
    expect(
      () => AuddioWhisperEngine.open(modelPath: 'definitely_missing.bin'),
      throwsA(isA<WhisperEngineException>()),
    );
  });

  test('result value types carry word-level timing', () {
    const word = WhisperWord(text: 'hello', startMs: 100, endMs: 400);
    const segment = WhisperSegment(
      text: 'hello',
      startMs: 100,
      endMs: 400,
      words: [word],
    );
    expect(segment.words.single.text, 'hello');
    expect(segment.words.single.startMs, 100);
    expect(segment.words.single.endMs, 400);
  });
}

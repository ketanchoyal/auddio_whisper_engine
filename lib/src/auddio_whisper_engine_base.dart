import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'whisper_result.dart';

class AuddioWhisperEngine {
  AuddioWhisperEngine._(this._bindings, this._ctx);

  final WhisperBindings _bindings;
  Pointer<Void> _ctx;

  static AuddioWhisperEngine open({
    required String modelPath,
    bool useGpu = true,
    int dtwAheadsPreset = -1,
    DynamicLibrary? customLibrary,
  }) {
    final bindings = WhisperBindings(customLibrary ?? openWhisperLibrary());
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final ctx = bindings.init(pathPtr.cast<Char>(), useGpu, dtwAheadsPreset);
      if (ctx == nullptr) {
        throw const WhisperEngineException('awe_init returned null');
      }
      return AuddioWhisperEngine._(bindings, ctx);
    } finally {
      calloc.free(pathPtr);
    }
  }

  bool get isDisposed => _ctx == nullptr;

  /// Decodes a time window from an audio file and transcribes it, all in C++.
  ///
  /// This bypasses Dart-side FFmpeg process spawning and temporary WAV file I/O
  /// entirely. The native layer uses platform APIs (ExtAudioFile on Apple,
  /// AMediaCodec on Android) to decode directly to 16kHz mono float32 PCM in
  /// memory, then feeds it to whisper.cpp.
  List<WhisperSegment> transcribeFileWindow({
    required String filePath,
    required int startMs,
    required int durationMs,
    int nThreads = 4,
  }) {
    if (_ctx == nullptr) {
      throw const WhisperEngineException('engine disposed');
    }
    final pathPtr = filePath.toNativeUtf8();
    try {
      final rc = _bindings.transcribeFileWindow(
        _ctx,
        pathPtr.cast<Char>(),
        startMs,
        durationMs,
        nThreads,
      );
      if (rc != 0) {
        throw WhisperEngineException(
          _readError() ?? 'awe_transcribe_file_window rc=$rc',
        );
      }
      return _readSegments();
    } finally {
      calloc.free(pathPtr);
    }
  }

  List<WhisperSegment> _readSegments() {
    final segCount = _bindings.segmentCount(_ctx);
    final segments = <WhisperSegment>[];
    for (var s = 0; s < segCount; s++) {
      final wordCount = _bindings.wordCount(_ctx, s);
      final words = <WhisperWord>[];
      for (var w = 0; w < wordCount; w++) {
        words.add(WhisperWord(
          text: _readString(_bindings.wordText(_ctx, s, w)),
          startMs: _bindings.wordT0Ms(_ctx, s, w),
          endMs: _bindings.wordT1Ms(_ctx, s, w),
        ));
      }
      segments.add(WhisperSegment(
        text: _readString(_bindings.segmentText(_ctx, s)),
        startMs: _bindings.segmentT0Ms(_ctx, s),
        endMs: _bindings.segmentT1Ms(_ctx, s),
        words: words,
      ));
    }
    return segments;
  }

  String? _readError() {
    final ptr = _bindings.lastError(_ctx);
    if (ptr == nullptr) return null;
    return ptr.cast<Utf8>().toDartString();
  }

  String _readString(Pointer<Char> ptr) {
    if (ptr == nullptr) return '';
    return ptr.cast<Utf8>().toDartString();
  }

  void dispose() {
    if (_ctx == nullptr) return;
    _bindings.free(_ctx);
    _ctx = nullptr;
  }
}

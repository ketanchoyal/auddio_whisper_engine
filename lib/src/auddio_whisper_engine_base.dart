import 'dart:ffi';
import 'dart:typed_data';

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
  }) {
    final bindings = WhisperBindings(openWhisperLibrary());
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final ctx = bindings.init(pathPtr.cast<Char>(), useGpu);
      if (ctx == nullptr) {
        throw const WhisperEngineException('awe_init returned null');
      }
      return AuddioWhisperEngine._(bindings, ctx);
    } finally {
      calloc.free(pathPtr);
    }
  }

  bool get isDisposed => _ctx == nullptr;

  List<WhisperSegment> transcribe(
    Float32List samples, {
    int nThreads = 4,
  }) {
    if (_ctx == nullptr) {
      throw const WhisperEngineException('engine disposed');
    }
    if (samples.isEmpty) return const <WhisperSegment>[];

    final buffer = calloc<Float>(samples.length);
    try {
      buffer.asTypedList(samples.length).setAll(0, samples);
      final rc =
          _bindings.transcribe(_ctx, buffer, samples.length, nThreads);
      if (rc != 0) {
        throw WhisperEngineException(_readError() ?? 'awe_transcribe rc=$rc');
      }
      return _readSegments();
    } finally {
      calloc.free(buffer);
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

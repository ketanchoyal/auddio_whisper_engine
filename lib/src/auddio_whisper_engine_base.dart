import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'bindings.dart';
import 'whisper_result.dart';

bool _coreMlLoadedInLastInit = false;

void _nativeLogCapture(int level, Pointer<Char> text, Pointer<Void> userData) {
  if (text != nullptr) {
    try {
      final msg = text.cast<Utf8>().toDartString();
      if (msg.contains('Core ML model loaded')) {
        _coreMlLoadedInLastInit = true;
      } else if (msg.contains('failed to load Core ML model')) {
        _coreMlLoadedInLastInit = false;
      }
    } catch (_) {}
  }
}

class AuddioWhisperEngine {
  AuddioWhisperEngine._(this._bindings, this._ctx, {this.isCoreMlActive = false});

  final WhisperBindings _bindings;
  Pointer<Void> _ctx;
  final bool isCoreMlActive;

  static AuddioWhisperEngine open({
    required String modelPath,
    bool useGpu = true,
    int dtwAheadsPreset = -1,
    DynamicLibrary? customLibrary,
  }) {
    final bindings = WhisperBindings(customLibrary ?? openWhisperLibrary());
    _coreMlLoadedInLastInit = false;
    try {
      final callbackPtr =
          Pointer.fromFunction<WhisperLogCallbackC>(_nativeLogCapture);
      bindings.logSet(callbackPtr, nullptr);
    } catch (_) {}

    final pathPtr = modelPath.toNativeUtf8();
    try {
      final ctx = bindings.init(pathPtr.cast<Char>(), useGpu, dtwAheadsPreset);
      if (ctx == nullptr) {
        throw const WhisperEngineException('awe_init returned null');
      }
      final isCoreMl = _coreMlLoadedInLastInit;
      return AuddioWhisperEngine._(bindings, ctx, isCoreMlActive: isCoreMl);
    } finally {
      calloc.free(pathPtr);
    }
  }

  bool get isDisposed => _ctx == nullptr;

  /// Sets the path to the Silero VAD model (.onnx). When set, subsequent
  /// transcribe calls enable Voice Activity Detection — skipping silence
  /// for faster transcription and mapping token timestamps back to the
  /// original audio timeline. Pass null to disable VAD.
  void setVadModel(String? vadModelPath) {
    if (_ctx == nullptr) return;
    final fn = _bindings.setVadModel;
    if (fn == null) return;
    if (vadModelPath != null && vadModelPath.isNotEmpty) {
      final ptr = vadModelPath.toNativeUtf8();
      fn(_ctx, ptr.cast<Char>());
      calloc.free(ptr);
    } else {
      fn(_ctx, nullptr);
    }
  }

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
    String? initialPrompt,
    String? language,
  }) {
    if (_ctx == nullptr) {
      throw const WhisperEngineException('engine disposed');
    }
    final pathPtr = filePath.toNativeUtf8();
    final promptPtr = (initialPrompt != null && initialPrompt.trim().isNotEmpty)
        ? initialPrompt.toNativeUtf8()
        : null;
    final langPtr = (language != null && language.trim().isNotEmpty)
        ? language.toNativeUtf8()
        : null;

    try {
      final rc = _bindings.transcribeFileWindow(
        _ctx,
        pathPtr.cast<Char>(),
        startMs,
        durationMs,
        nThreads,
        promptPtr != null ? promptPtr.cast<Char>() : nullptr,
        langPtr != null ? langPtr.cast<Char>() : nullptr,
      );
      if (rc != 0) {
        throw WhisperEngineException(
          _readError() ?? 'awe_transcribe_file_window rc=$rc',
        );
      }
      return _readSegments();
    } finally {
      calloc.free(pathPtr);
      if (promptPtr != null) calloc.free(promptPtr);
      if (langPtr != null) calloc.free(langPtr);
    }
  }

  /// Transcribes raw PCM samples directly (no file needed).
  ///
  /// Used for live transcription of streaming audio. The native layer
  /// downmixes to mono, resamples to 16 kHz, appends trailing silence, and
  /// runs whisper — all in C++.
  ///
  /// [samples] are interleaved float32 values in [-1.0, +1.0] at
  /// [sampleRate] Hz with [channels] channels (e.g. from the mpv player's
  /// PCM stream).
  List<WhisperSegment> transcribeSamples({
    required Float32List samples,
    required int sampleRate,
    required int channels,
    int nThreads = 4,
    String? initialPrompt,
    String? language,
  }) {
    if (_ctx == nullptr) {
      throw const WhisperEngineException('engine disposed');
    }
    final promptPtr = (initialPrompt != null && initialPrompt.trim().isNotEmpty)
        ? initialPrompt.toNativeUtf8()
        : null;
    final langPtr = (language != null && language.trim().isNotEmpty)
        ? language.toNativeUtf8()
        : null;

    // Copy the Float32List into native memory (the GC could move the Dart
    // typed-data backing store if we held a Pointer to it directly).
    final samplesPtr = calloc<Float>(samples.length);
    samplesPtr.asTypedList(samples.length).setAll(0, samples);

    try {
      final fn = _bindings.transcribeSamples;
      if (fn == null) {
        throw const WhisperEngineException(
          'awe_transcribe_samples not supported in this build',
        );
      }
      final rc = fn(
        _ctx,
        samplesPtr,
        samples.length,
        sampleRate,
        channels,
        nThreads,
        promptPtr != null ? promptPtr.cast<Char>() : nullptr,
        langPtr != null ? langPtr.cast<Char>() : nullptr,
      );
      if (rc != 0) {
        throw WhisperEngineException(
          _readError() ?? 'awe_transcribe_samples rc=$rc',
        );
      }
      return _readSegments();
    } finally {
      calloc.free(samplesPtr);
      if (promptPtr != null) calloc.free(promptPtr);
      if (langPtr != null) calloc.free(langPtr);
    }
  }

  /// Decodes a time window from an audio file directly in C++ to a Float32List.
  ///
  /// This can be used by any transcription engine (including sherpa_onnx) to
  /// decode audio in memory without spawning FFmpeg or writing WAV files.
  static Float32List decodeAudioWindow({
    required String filePath,
    required int startMs,
    required int durationMs,
    DynamicLibrary? customLibrary,
  }) {
    final bindings = WhisperBindings(customLibrary ?? openWhisperLibrary());
    final pathPtr = filePath.toNativeUtf8();
    
    // Allocate pointers for the return values
    final outSamplesPtr = calloc<Pointer<Float>>();
    final outNSamplesPtr = calloc<Int32>();
    final outErrorPtr = calloc<Pointer<Char>>();
    
    try {
      final rc = bindings.decodeAudioWindow(
        pathPtr.cast<Char>(),
        startMs,
        durationMs,
        outSamplesPtr,
        outNSamplesPtr,
        outErrorPtr,
      );
      
      if (rc != 0) {
        final errPtr = outErrorPtr.value;
        final errMsg = errPtr != nullptr ? errPtr.cast<Utf8>().toDartString() : 'Unknown error';
        if (errPtr != nullptr) calloc.free(errPtr);
        throw WhisperEngineException('awe_decode_audio_window failed (rc=$rc): $errMsg');
      }
      
      final nSamples = outNSamplesPtr.value;
      final samplesPtr = outSamplesPtr.value;
      if (samplesPtr == nullptr || nSamples <= 0) {
        return Float32List(0);
      }
      
      // Copy the float samples into a Dart Float32List
      final list = Float32List(nSamples);
      list.setAll(0, samplesPtr.asTypedList(nSamples));
      
      // Free the natively allocated buffer
      calloc.free(samplesPtr);
      
      return list;
    } finally {
      calloc.free(pathPtr);
      calloc.free(outSamplesPtr);
      calloc.free(outNSamplesPtr);
      calloc.free(outErrorPtr);
    }
  }

  List<WhisperSegment> _readSegments() {
    final segCount = _bindings.segmentCount(_ctx);
    final segments = <WhisperSegment>[];
    final whisperCtx = _ctx != nullptr ? _ctx.cast<Pointer<Void>>().value : nullptr;

    for (var s = 0; s < segCount; s++) {
      final tokenList = <_TokenData>[];
      if (whisperCtx != nullptr) {
        try {
          final nTokens = _bindings.fullNTokens(whisperCtx, s);
          for (var t = 0; t < nTokens; t++) {
            final p = _bindings.fullGetTokenP(whisperCtx, s, t);
            final text =
                _readString(_bindings.fullGetTokenText(whisperCtx, s, t));
            final t0 = _bindings.fullGetTokenT0(whisperCtx, s, t) * 10;
            final t1 = _bindings.fullGetTokenT1(whisperCtx, s, t) * 10;
            tokenList.add(_TokenData(text: text, p: p, t0: t0, t1: t1));
          }
        } catch (_) {
          // Fallback if token inspection fails
        }
      }

      final wordCount = _bindings.wordCount(_ctx, s);
      final words = <WhisperWord>[];
      var tokenSearchIdx = 0;

      for (var w = 0; w < wordCount; w++) {
        final text = _readString(_bindings.wordText(_ctx, s, w));
        final startMs = _bindings.wordT0Ms(_ctx, s, w);
        final endMs = _bindings.wordT1Ms(_ctx, s, w);

        var confidence = 1.0;
        if (tokenList.isNotEmpty) {
          // Find tokens overlapping this word's timestamp window or matching text
          final matchingProbs = <double>[];
          for (var t = 0; t < tokenList.length; t++) {
            final tok = tokenList[t];
            final isSpecial = tok.text.startsWith('[_') ||
                tok.text.startsWith('<|') ||
                tok.text.startsWith(' [');
            if (isSpecial) continue;

            final overlapsTime = (tok.t0 < endMs + 50) && (tok.t1 > startMs - 50);
            if (overlapsTime && tok.p > 0.0) {
              matchingProbs.add(tok.p);
            }
          }

          // Fallback to sequential text search if timestamp overlap yielded no tokens
          if (matchingProbs.isEmpty && tokenSearchIdx < tokenList.length) {
            final cleanWord = text.trim().toLowerCase();
            for (var t = tokenSearchIdx; t < tokenList.length; t++) {
              final tok = tokenList[t];
              final cleanTok = tok.text.trim().toLowerCase();
              if (cleanTok.isNotEmpty && cleanWord.contains(cleanTok) && tok.p > 0.0) {
                matchingProbs.add(tok.p);
                tokenSearchIdx = t + 1;
                break;
              }
            }
          }

          if (matchingProbs.isNotEmpty) {
            // Minimum token probability represents the word's weakest sub-word token
            confidence = matchingProbs.reduce((a, b) => a < b ? a : b).clamp(0.0, 1.0);
          }
        }

        words.add(WhisperWord(
          text: text,
          startMs: startMs,
          endMs: endMs,
          confidence: confidence,
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

class _TokenData {
  const _TokenData({
    required this.text,
    required this.p,
    required this.t0,
    required this.t1,
  });

  final String text;
  final double p;
  final int t0;
  final int t1;
}

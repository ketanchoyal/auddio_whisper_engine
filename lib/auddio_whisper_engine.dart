/// Custom whisper.cpp FFI engine for Auddio chapter transcription.
///
/// On-device speech-to-text with per-word (DTW) timestamps, backed by the
/// prebuilt `libauddio_whisper` native library loaded via dart:ffi. The C-ABI
/// contract lives at `native/include/auddio_whisper_bridge.h`.
library;

export 'src/auddio_whisper_engine_base.dart' show AuddioWhisperEngine;
export 'src/whisper_result.dart'
    show WhisperSegment, WhisperWord, WhisperEngineException;

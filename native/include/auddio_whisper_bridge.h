#ifndef AUDDIO_WHISPER_BRIDGE_H
#define AUDDIO_WHISPER_BRIDGE_H

// C-ABI bridge over whisper.cpp for Auddio chapter transcription.
//
// Design goals:
//   * Plain C ABI so dart:ffi can bind directly (no C++ name mangling).
//   * Per-WORD timestamps via whisper.cpp DTW alignment (the reason this
//     engine exists). Word grouping + timing is done HERE in C++ so the Dart
//     side stays trivial and the FFI boundary stays cheap.
//   * Chapter-relative timestamps in milliseconds (the app adds its own
//     window base offset on the Dart side).
//   * In-memory audio decoding via platform-native APIs (ExtAudioFile on
//     Apple, AMediaCodec on Android) — no FFmpeg, no temp files.
//
// Memory ownership: all `const char*` returned by accessors are owned by the
// awe_context and remain valid until the next awe_transcribe_file_window()
// call on that context or awe_free(). Callers MUST copy strings they need to
// retain. None of these functions are thread-safe for a single context; the
// app drives one context per worker isolate.

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_WIN32)
#define AWE_EXPORT __declspec(dllexport)
#else
#define AWE_EXPORT __attribute__((visibility("default"))) __attribute__((used))
#endif

// Opaque handle wrapping a whisper_context plus the most recent decode result.
typedef struct awe_context awe_context;

// Initializes the engine from a ggml .bin model file.
//   model_path        : absolute path to e.g. ggml-base.en.bin.
//   use_gpu           : enable the GPU backend (Metal on Apple).
//   dtw_aheads_preset : the alignment heads preset to use (from the
//                       whisper_alignment_heads_preset enum). Pass -1 to
//                       automatically detect it based on the model filename.
// Returns NULL on failure.
AWE_EXPORT awe_context* awe_init(const char* model_path, bool use_gpu, int32_t dtw_aheads_preset);


// Decodes a time window from an audio file directly in C++ (using platform
// native APIs: ExtAudioFile on Apple, AMediaCodec on Android), then runs
// whisper transcription on the decoded PCM — all in one call. This bypasses
// Dart-side FFmpeg process spawning and temporary WAV file I/O entirely.
//
//   file_path      : absolute path to the audiobook file (.mp3, .m4a, .m4b, etc.)
//   start_ms       : start offset in the file (milliseconds)
//   duration_ms    : duration of the window to decode and transcribe (milliseconds)
//   n_threads      : number of CPU threads for the whisper decoder
//   initial_prompt : optional context prompt string (or NULL)
//   language       : optional language code (e.g. "en", "es", "auto", or NULL for default "en")
//
// Returns 0 on success, non-zero on failure (inspect awe_last_error).
// Segment/word accessors work identically after this call.
AWE_EXPORT int32_t awe_transcribe_file_window(awe_context* ctx,
                                              const char* file_path,
                                              int64_t start_ms,
                                              int64_t duration_ms,
                                              int32_t n_threads,
                                              const char* initial_prompt,
                                              const char* language);

// Decodes a time window from an audio file directly to a float32 PCM buffer in memory.
//   file_path     : absolute path to the audiobook file (.mp3, .m4a, .m4b, etc.)
//   start_ms      : start offset in the file (milliseconds)
//   duration_ms   : duration of the window to decode (milliseconds)
//   out_samples   : pointer to receive the allocated float* samples buffer (16kHz mono)
//   out_n_samples : pointer to receive the number of samples decoded
//   out_error     : pointer to receive any error message string
//
// Callers must free the returned out_samples buffer using free() when done.
// Returns 0 on success, non-zero on failure.
AWE_EXPORT int32_t awe_decode_audio_window_ffi(const char* file_path,
                                               int64_t start_ms,
                                               int64_t duration_ms,
                                               float** out_samples,
                                               int32_t* out_n_samples,
                                               char** out_error);

// ---- Segment accessors (valid after a successful transcription) -----------
AWE_EXPORT int32_t awe_segment_count(awe_context* ctx);
AWE_EXPORT const char* awe_segment_text(awe_context* ctx, int32_t i_segment);
AWE_EXPORT int64_t awe_segment_t0_ms(awe_context* ctx, int32_t i_segment);
AWE_EXPORT int64_t awe_segment_t1_ms(awe_context* ctx, int32_t i_segment);

// ---- Word accessors (DTW-aligned, reconstructed from tokens in C++) -------
AWE_EXPORT int32_t awe_word_count(awe_context* ctx, int32_t i_segment);
AWE_EXPORT const char* awe_word_text(awe_context* ctx,
                                     int32_t i_segment,
                                     int32_t i_word);
AWE_EXPORT int64_t awe_word_t0_ms(awe_context* ctx,
                                  int32_t i_segment,
                                  int32_t i_word);
AWE_EXPORT int64_t awe_word_t1_ms(awe_context* ctx,
                                  int32_t i_segment,
                                  int32_t i_word);

// Most recent error message for this context (UTF-8), or NULL if none.
AWE_EXPORT const char* awe_last_error(awe_context* ctx);

// Releases the whisper_context and all retained results. Safe to call once.
AWE_EXPORT void awe_free(awe_context* ctx);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // AUDDIO_WHISPER_BRIDGE_H

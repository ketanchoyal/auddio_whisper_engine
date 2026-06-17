#ifndef AUDDIO_WHISPER_BRIDGE_H
#define AUDDIO_WHISPER_BRIDGE_H

// C-ABI bridge over whisper.cpp for Audiio chapter transcription.
//
// Design goals:
//   * Plain C ABI so dart:ffi can bind directly (no C++ name mangling).
//   * Per-WORD timestamps via whisper.cpp DTW alignment (the reason this
//     engine exists). Word grouping + timing is done HERE in C++ so the Dart
//     side stays trivial and the FFI boundary stays cheap.
//   * Chapter-relative timestamps in milliseconds (the app adds its own
//     window base offset on the Dart side).
//
// Audio contract: callers pass mono float32 PCM normalized to [-1, 1] at
// 16 kHz (matches the app's FFmpeg window decode: -ac 1 -ar 16000).
//
// Memory ownership: all `const char*` returned by accessors are owned by the
// awe_context and remain valid until the next awe_transcribe() call on that
// context or awe_free(). Callers MUST copy strings they need to retain. None
// of these functions are thread-safe for a single context; the app drives one
// context per worker isolate.

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
//   model_path : absolute path to e.g. ggml-base.en.bin.
//   use_gpu    : enable the GPU backend (Metal on Apple). Ignored where the
//                binary was built CPU-only (Android).
// CoreML has NO runtime switch: whisper.cpp activates it automatically when the
// binary is built with CoreML AND a compiled `<model>-encoder.mlmodelc` folder
// sits adjacent to this .bin. To disable CoreML (e.g. after a failed warmup),
// the caller must omit/remove that .mlmodelc folder before calling awe_init.
// Returns NULL on failure.
AWE_EXPORT awe_context* awe_init(const char* model_path, bool use_gpu);

// Runs a full transcription pass over [samples, samples+n_samples).
// Configures DTW token timestamps (base.en alignment heads) so word times are
// available afterwards. Returns 0 on success, non-zero on failure (inspect
// awe_last_error). Results are retained on the context until the next call.
AWE_EXPORT int32_t awe_transcribe(awe_context* ctx,
                                  const float* samples,
                                  int32_t n_samples,
                                  int32_t n_threads);

// ---- Segment accessors (valid after a successful awe_transcribe) ----------
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

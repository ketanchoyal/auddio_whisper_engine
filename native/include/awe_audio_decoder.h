#ifndef AWE_AUDIO_DECODER_H
#define AWE_AUDIO_DECODER_H

// Platform-agnostic audio decoder interface.
//
// Each platform (Apple, Android) provides its own implementation of
// awe_decode_audio_window that decodes a time window from an audio file
// directly into a 16kHz mono float32 PCM buffer in memory.
//
// On Apple: uses ExtAudioFile (AudioToolbox) for automatic resampling and
// channel downmixing.
// On Android: uses AMediaExtractor + AMediaCodec (NDK) with manual
// resampling and downmixing.

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Decodes a time window from an audio file to 16kHz mono float32 PCM.
//
//   file_path    : absolute path to the audio file (.mp3, .m4a, .m4b, etc.)
//   start_ms     : start offset in milliseconds from the beginning of the file
//   duration_ms  : duration of the window to decode in milliseconds
//   out_samples  : on success, set to a malloc'd float buffer (caller must free)
//   out_n_samples: on success, set to the number of float samples in out_samples
//   out_error    : on failure, set to a malloc'd error string (caller must free)
//
// Returns 0 on success, non-zero on failure.
int awe_decode_audio_window(const char* file_path,
                            int64_t start_ms,
                            int64_t duration_ms,
                            float** out_samples,
                            int32_t* out_n_samples,
                            char** out_error);

#ifdef __cplusplus
}
#endif

#endif  // AWE_AUDIO_DECODER_H

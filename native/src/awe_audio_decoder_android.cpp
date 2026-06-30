// Android implementation of awe_decode_audio_window.
//
// Uses NDK AMediaExtractor + AMediaCodec to decode audio files. Unlike the
// Apple path, this requires manual int16→float conversion, stereo→mono
// downmixing, and sample rate conversion (if the source is not 16kHz).
//
// Requires Android API level 21+ (app min is 24).

#include "awe_audio_decoder.h"

#include <media/NdkMediaCodec.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaFormat.h>

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static const int32_t kTargetSampleRate = 16000;

static char* make_error(const char* msg) {
  char* err = static_cast<char*>(malloc(strlen(msg) + 1));
  if (err) strcpy(err, msg);
  return err;
}

// Simple linear resampler (adequate for speech, avoids pulling in a DSP lib).
static std::vector<float> resample_linear(const float* input,
                                          int32_t in_count,
                                          int32_t in_rate,
                                          int32_t out_rate) {
  if (in_rate == out_rate || in_count <= 0) {
    return std::vector<float>(input, input + in_count);
  }
  const double ratio = static_cast<double>(in_rate) / out_rate;
  const int32_t out_count = static_cast<int32_t>(
      std::ceil(static_cast<double>(in_count) / ratio));
  std::vector<float> output(out_count);
  for (int32_t i = 0; i < out_count; ++i) {
    double src_idx = i * ratio;
    int32_t idx0 = static_cast<int32_t>(src_idx);
    int32_t idx1 = idx0 + 1;
    if (idx1 >= in_count) idx1 = in_count - 1;
    double frac = src_idx - idx0;
    output[i] = static_cast<float>(input[idx0] * (1.0 - frac) +
                                   input[idx1] * frac);
  }
  return output;
}

int awe_decode_audio_window(const char* file_path,
                            int64_t start_ms,
                            int64_t duration_ms,
                            float** out_samples,
                            int32_t* out_n_samples,
                            char** out_error) {
  if (!file_path || !out_samples || !out_n_samples || !out_error) return -1;
  *out_samples = nullptr;
  *out_n_samples = 0;
  *out_error = nullptr;

  // 1. Create extractor and set data source.
  AMediaExtractor* extractor = AMediaExtractor_new();
  if (!extractor) {
    *out_error = make_error("AMediaExtractor_new failed");
    return -1;
  }

  int fd_status = -1;
  // Use file descriptor path for local files.
  FILE* fp = fopen(file_path, "rb");
  if (!fp) {
    AMediaExtractor_delete(extractor);
    *out_error = make_error("Failed to open audio file");
    return -1;
  }
  fseek(fp, 0, SEEK_END);
  long file_size = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  int fd = fileno(fp);
  fd_status = AMediaExtractor_setDataSourceFd(extractor, fd, 0, file_size);
  // Keep fp open until we're done with the extractor.

  if (fd_status != AMEDIA_OK) {
    fclose(fp);
    AMediaExtractor_delete(extractor);
    *out_error = make_error("AMediaExtractor_setDataSourceFd failed");
    return -1;
  }

  // 2. Find the first audio track.
  int track_count = static_cast<int>(AMediaExtractor_getTrackCount(extractor));
  int audio_track = -1;
  AMediaFormat* track_format = nullptr;

  for (int i = 0; i < track_count; ++i) {
    AMediaFormat* fmt = AMediaExtractor_getTrackFormat(extractor, i);
    const char* mime = nullptr;
    if (AMediaFormat_getString(fmt, AMEDIAFORMAT_KEY_MIME, &mime)) {
      if (mime && strncmp(mime, "audio/", 6) == 0) {
        audio_track = i;
        track_format = fmt;
        break;
      }
    }
    AMediaFormat_delete(fmt);
  }

  if (audio_track < 0) {
    fclose(fp);
    AMediaExtractor_delete(extractor);
    *out_error = make_error("No audio track found in file");
    return -1;
  }

  // 3. Read track properties.
  const char* mime = nullptr;
  AMediaFormat_getString(track_format, AMEDIAFORMAT_KEY_MIME, &mime);

  int32_t source_sample_rate = 44100;
  int32_t source_channels = 2;
  AMediaFormat_getInt32(track_format, AMEDIAFORMAT_KEY_SAMPLE_RATE, &source_sample_rate);
  AMediaFormat_getInt32(track_format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &source_channels);

  // 4. Create and configure decoder.
  AMediaCodec* codec = AMediaCodec_createDecoderByType(mime);
  if (!codec) {
    AMediaFormat_delete(track_format);
    fclose(fp);
    AMediaExtractor_delete(extractor);
    *out_error = make_error("AMediaCodec_createDecoderByType failed");
    return -1;
  }

  media_status_t ms = AMediaCodec_configure(codec, track_format, nullptr, nullptr, 0);
  AMediaFormat_delete(track_format);
  track_format = nullptr;

  if (ms != AMEDIA_OK) {
    AMediaCodec_delete(codec);
    fclose(fp);
    AMediaExtractor_delete(extractor);
    *out_error = make_error("AMediaCodec_configure failed");
    return -1;
  }

  AMediaExtractor_selectTrack(extractor, audio_track);

  // 5. Seek to start_ms.
  AMediaExtractor_seekTo(extractor, start_ms * 1000,
                         AMEDIAEXTRACTOR_SEEK_CLOSEST_SYNC);

  ms = AMediaCodec_start(codec);
  if (ms != AMEDIA_OK) {
    AMediaCodec_delete(codec);
    fclose(fp);
    AMediaExtractor_delete(extractor);
    *out_error = make_error("AMediaCodec_start failed");
    return -1;
  }

  // 6. Decode loop: feed compressed data → collect raw PCM.
  const int64_t end_us = (start_ms + duration_ms) * 1000;
  bool input_done = false;
  bool output_done = false;

  // Accumulate decoded mono float samples at the source sample rate.
  std::vector<float> decoded_mono;
  // Reserve a generous estimate.
  decoded_mono.reserve(static_cast<size_t>(
      (duration_ms * source_sample_rate) / 1000));

  while (!output_done) {
    // Feed input buffers.
    if (!input_done) {
      ssize_t buf_idx = AMediaCodec_dequeueInputBuffer(codec, 2000);
      if (buf_idx >= 0) {
        size_t buf_size = 0;
        uint8_t* buf = AMediaCodec_getInputBuffer(codec, buf_idx, &buf_size);
        ssize_t sample_size = AMediaExtractor_readSampleData(
            extractor, buf, buf_size);
        if (sample_size < 0) {
          // End of stream.
          AMediaCodec_queueInputBuffer(codec, buf_idx, 0, 0, 0,
                                       AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
          input_done = true;
        } else {
          int64_t pts = AMediaExtractor_getSampleTime(extractor);
          AMediaCodec_queueInputBuffer(codec, buf_idx, 0, sample_size,
                                       pts, 0);
          AMediaExtractor_advance(extractor);
          // Stop feeding once we've passed end_us to avoid decoding the
          // entire file.
          if (pts > end_us) {
            input_done = true;
          }
        }
      }
    }

    // Drain output buffers.
    AMediaCodecBufferInfo info;
    ssize_t out_idx = AMediaCodec_dequeueOutputBuffer(codec, &info, 2000);
    if (out_idx >= 0) {
      // Check if this buffer is past our window.
      if (info.presentationTimeUs >= end_us &&
          !(info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM)) {
        AMediaCodec_releaseOutputBuffer(codec, out_idx, false);
        output_done = true;
        continue;
      }

      size_t out_size = 0;
      uint8_t* out_buf = AMediaCodec_getOutputBuffer(codec, out_idx, &out_size);
      if (out_buf && info.size > 0) {
        // The output is typically 16-bit signed integer PCM.
        int32_t n_int16_samples = info.size / 2;
        const int16_t* pcm16 = reinterpret_cast<const int16_t*>(
            out_buf + info.offset);

        // Skip samples before our actual start_ms.
        // presentationTimeUs is the time of the first sample in this buffer.
        int64_t buf_start_us = info.presentationTimeUs;
        int32_t skip_frames = 0;
        if (buf_start_us < start_ms * 1000) {
          int64_t skip_us = start_ms * 1000 - buf_start_us;
          skip_frames = static_cast<int32_t>(
              (skip_us * source_sample_rate) / 1000000);
          skip_frames = std::min(skip_frames, n_int16_samples / source_channels);
        }

        int32_t total_frames = n_int16_samples / source_channels;
        for (int32_t f = skip_frames; f < total_frames; ++f) {
          // Downmix to mono by averaging channels.
          float sum = 0.0f;
          for (int32_t c = 0; c < source_channels; ++c) {
            sum += pcm16[f * source_channels + c] / 32768.0f;
          }
          decoded_mono.push_back(sum / source_channels);
        }
      }

      AMediaCodec_releaseOutputBuffer(codec, out_idx, false);
      if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) {
        output_done = true;
      }
    } else if (out_idx == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
      // Output format changed; re-read sample rate and channels.
      AMediaFormat* new_fmt = AMediaCodec_getOutputFormat(codec);
      if (new_fmt) {
        AMediaFormat_getInt32(new_fmt, AMEDIAFORMAT_KEY_SAMPLE_RATE,
                              &source_sample_rate);
        AMediaFormat_getInt32(new_fmt, AMEDIAFORMAT_KEY_CHANNEL_COUNT,
                              &source_channels);
        AMediaFormat_delete(new_fmt);
      }
    }
    // AMEDIACODEC_INFO_TRY_AGAIN_LATER (-1): just loop.
  }

  // 7. Cleanup codec + extractor.
  AMediaCodec_stop(codec);
  AMediaCodec_delete(codec);
  AMediaExtractor_delete(extractor);
  fclose(fp);

  if (decoded_mono.empty()) {
    *out_error = make_error("Decoded 0 samples from audio file");
    return -1;
  }

  // 8. Resample to 16kHz if needed.
  std::vector<float> final_pcm;
  if (source_sample_rate != kTargetSampleRate) {
    final_pcm = resample_linear(decoded_mono.data(),
                                static_cast<int32_t>(decoded_mono.size()),
                                source_sample_rate, kTargetSampleRate);
  } else {
    final_pcm = std::move(decoded_mono);
  }

  if (final_pcm.empty()) {
    *out_error = make_error("Resampled PCM is empty");
    return -1;
  }

  // 9. Return the buffer.
  float* result = static_cast<float*>(
      malloc(final_pcm.size() * sizeof(float)));
  if (!result) {
    *out_error = make_error("malloc failed for PCM buffer");
    return -1;
  }
  memcpy(result, final_pcm.data(), final_pcm.size() * sizeof(float));
  *out_samples = result;
  *out_n_samples = static_cast<int32_t>(final_pcm.size());
  return 0;
}

#include "auddio_whisper_bridge.h"

#include <exception>
#include <string>
#include <vector>
#include <cstring>

#include "whisper.h"
#include "awe_audio_decoder.h"

namespace {

struct Word {
  std::string text;
  int64_t t0_ms;
  int64_t t1_ms;
};

struct Segment {
  std::string text;
  int64_t t0_ms;
  int64_t t1_ms;
  std::vector<Word> words;
};

// whisper.cpp reports times in centiseconds (10ms units).
inline int64_t cs_to_ms(int64_t cs) { return cs * 10; }

}

struct awe_context {
  whisper_context* ctx = nullptr;
  std::vector<Segment> segments;
  std::string last_error;
};

awe_context* awe_init(const char* model_path, bool use_gpu, int32_t dtw_aheads_preset) {
  // No exception may cross this C ABI boundary: an uncaught C++ throw would
  // unwind into Dart FFI with no handler and abort the whole app.
  try {
    if (model_path == nullptr) return nullptr;
    auto* wrapper = new awe_context();

    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = use_gpu;
    // Must stay false: whisper defaults flash_attn=true, which force-disables
    // dtw_token_timestamps (our whole purpose) and hangs the Metal kernel on
    // pre-Apple7 GPUs (e.g. A12Z) that lack simdgroup matrix-mul.
    cparams.flash_attn = false;
    cparams.dtw_token_timestamps = true;
    
    if (dtw_aheads_preset >= 0) {
      cparams.dtw_aheads_preset = static_cast<whisper_alignment_heads_preset>(dtw_aheads_preset);
    } else {
      // Detect the appropriate alignment heads preset based on the model filename.
      // If the model doesn't match any known preset, we fall back to BASE_EN.
      std::string path_str = model_path;
      if (path_str.find("tiny.en") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_TINY_EN;
      } else if (path_str.find("tiny") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_TINY;
      } else if (path_str.find("base.en") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_BASE_EN;
      } else if (path_str.find("base") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_BASE;
      } else if (path_str.find("small.en") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_SMALL_EN;
      } else if (path_str.find("small") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_SMALL;
      } else if (path_str.find("medium.en") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_MEDIUM_EN;
      } else if (path_str.find("medium") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_MEDIUM;
      } else if (path_str.find("large-v3-turbo") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_LARGE_V3_TURBO;
      } else if (path_str.find("large-v3") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_LARGE_V3;
      } else if (path_str.find("large-v2") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_LARGE_V2;
      } else if (path_str.find("large") != std::string::npos) {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_LARGE_V1;
      } else {
        cparams.dtw_aheads_preset = WHISPER_AHEADS_BASE_EN;
      }
    }

    wrapper->ctx = whisper_init_from_file_with_params(model_path, cparams);
    if (wrapper->ctx == nullptr) {
      wrapper->last_error = "whisper_init_from_file_with_params returned null";
      return wrapper;
    }

    // Warm up on silence so CoreML's one-time first-run compile (5-15s on
    // older GPUs) happens here, not on the caller's first timed window — which
    // would blow its timeout, trigger an engine respawn, and OOM a memory-tight
    // GPU (e.g. A12Z) with two live contexts. Returns fast once compiled.
    {
      whisper_full_params wparams =
          whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
      wparams.n_threads = 1;
      wparams.print_progress = false;
      wparams.print_realtime = false;
      wparams.print_timestamps = false;
      wparams.no_timestamps = true;
      std::vector<float> silence(16000, 0.0f);
      whisper_full(wrapper->ctx, wparams, silence.data(),
                   static_cast<int>(silence.size()));
    }

    return wrapper;
  } catch (...) {
    return nullptr;
  }
}

static int32_t awe_transcribe_impl(awe_context* ctx, const float* samples,
                                   int32_t n_samples, int32_t n_threads) {
  ctx->segments.clear();
  ctx->last_error.clear();

  whisper_full_params params =
      whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
  params.n_threads = n_threads > 0 ? n_threads : 1;
  params.token_timestamps = true;
  params.split_on_word = true;
  params.print_progress = false;
  params.print_realtime = false;
  params.print_timestamps = false;
  params.no_timestamps = false;

  const int rc = whisper_full(ctx->ctx, params, samples, n_samples);
  if (rc != 0) {
    ctx->last_error = "whisper_full failed with code " + std::to_string(rc);
    return rc;
  }

  const int n_segments = whisper_full_n_segments(ctx->ctx);
  ctx->segments.reserve(n_segments);

  for (int s = 0; s < n_segments; ++s) {
    Segment seg;
    const char* seg_text = whisper_full_get_segment_text(ctx->ctx, s);
    seg.text = seg_text != nullptr ? seg_text : "";
    seg.t0_ms = cs_to_ms(whisper_full_get_segment_t0(ctx->ctx, s));
    seg.t1_ms = cs_to_ms(whisper_full_get_segment_t1(ctx->ctx, s));

    const int n_tokens = whisper_full_n_tokens(ctx->ctx, s);
    Word current;
    bool have_current = false;

    auto flush = [&]() {
      if (have_current && !current.text.empty()) {
        seg.words.push_back(current);
      }
      have_current = false;
      current = Word{};
    };

    for (int t = 0; t < n_tokens; ++t) {
      const whisper_token id = whisper_full_get_token_id(ctx->ctx, s, t);
      // Skip special vocab tokens (timestamps, <sot>, <eot>, etc.).
      if (id >= whisper_token_eot(ctx->ctx)) continue;

      const char* raw = whisper_full_get_token_text(ctx->ctx, s, t);
      if (raw == nullptr) continue;
      std::string piece = raw;
      if (piece.empty()) continue;

      const whisper_token_data data =
          whisper_full_get_token_data(ctx->ctx, s, t);
      // Prefer DTW-aligned time; fall back to the heuristic token time.
      const int64_t tok_t0 =
          cs_to_ms(data.t_dtw >= 0 ? data.t_dtw : data.t0);
      const int64_t tok_t1 = cs_to_ms(data.t1);

      // A leading space (whisper BPE word-boundary marker) starts a new word;
      // continuation pieces append to the current word.
      const bool starts_word = piece[0] == ' ';
      if (starts_word) {
        flush();
        piece.erase(0, 1);
        if (piece.empty()) continue;
        current.text = piece;
        current.t0_ms = tok_t0;
        current.t1_ms = std::max(tok_t0, tok_t1);
        have_current = true;
      } else {
        if (!have_current) {
          current.t0_ms = tok_t0;
          current.t1_ms = tok_t0;
          have_current = true;
        }
        current.text += piece;
        current.t1_ms = std::max({current.t0_ms, current.t1_ms, tok_t1});
      }
    }
    flush();

    ctx->segments.push_back(std::move(seg));
  }

  return 0;
}

int32_t awe_transcribe_file_window(awe_context* ctx, const char* file_path,
                                   int64_t start_ms, int64_t duration_ms,
                                   int32_t n_threads) {
  if (ctx == nullptr || ctx->ctx == nullptr || file_path == nullptr) return -1;
  try {
    // Decode the audio window using the platform-native decoder.
    float* samples = nullptr;
    int32_t n_samples = 0;
    char* decode_error = nullptr;

    int rc = awe_decode_audio_window(file_path, start_ms, duration_ms,
                                     &samples, &n_samples, &decode_error);
    if (rc != 0 || samples == nullptr || n_samples <= 0) {
      ctx->segments.clear();
      ctx->last_error = decode_error
          ? std::string("audio decode failed: ") + decode_error
          : "audio decode failed (unknown error)";
      if (decode_error) free(decode_error);
      if (samples) free(samples);
      return -4;
    }
    if (decode_error) free(decode_error);

    // whisper.cpp's median_filter asserts that the filter width (typically 7)
    // is strictly less than the number of audio frames. To prevent a SIGABRT crash
    // on extremely short audio clips/windows (e.g. final window or short files),
    // pad the decoded samples with silence to be at least 2 seconds (32,000 samples).
    int32_t min_samples = 32000;
    if (n_samples < min_samples) {
      float* padded_samples = static_cast<float*>(malloc(min_samples * sizeof(float)));
      if (padded_samples != nullptr) {
        memcpy(padded_samples, samples, n_samples * sizeof(float));
        memset(padded_samples + n_samples, 0, (min_samples - n_samples) * sizeof(float));
        free(samples);
        samples = padded_samples;
        n_samples = min_samples;
      }
    }

    // Transcribe the decoded PCM using the existing implementation.
    int32_t result = awe_transcribe_impl(ctx, samples, n_samples, n_threads);
    free(samples);
    return result;
  } catch (const std::exception& e) {
    ctx->segments.clear();
    ctx->last_error = std::string("native exception in file window: ") + e.what();
    return -2;
  } catch (...) {
    ctx->segments.clear();
    ctx->last_error = "unknown native exception in file window transcription";
    return -3;
  }
}

int32_t awe_decode_audio_window_ffi(const char* file_path,
                                   int64_t start_ms,
                                   int64_t duration_ms,
                                   float** out_samples,
                                   int32_t* out_n_samples,
                                   char** out_error) {
  if (file_path == nullptr || out_samples == nullptr || out_n_samples == nullptr || out_error == nullptr) return -1;
  try {
    return awe_decode_audio_window(file_path, start_ms, duration_ms, out_samples, out_n_samples, out_error);
  } catch (const std::exception& e) {
    *out_samples = nullptr;
    *out_n_samples = 0;
    std::string err = std::string("native exception in decode: ") + e.what();
    *out_error = strdup(err.c_str());
    return -2;
  } catch (...) {
    *out_samples = nullptr;
    *out_n_samples = 0;
    *out_error = strdup("unknown native exception during decode");
    return -3;
  }
}

int32_t awe_segment_count(awe_context* ctx) {
  if (ctx == nullptr) return 0;
  return static_cast<int32_t>(ctx->segments.size());
}

const char* awe_segment_text(awe_context* ctx, int32_t i) {
  if (ctx == nullptr || i < 0 ||
      i >= static_cast<int32_t>(ctx->segments.size())) {
    return nullptr;
  }
  return ctx->segments[i].text.c_str();
}

int64_t awe_segment_t0_ms(awe_context* ctx, int32_t i) {
  if (ctx == nullptr || i < 0 ||
      i >= static_cast<int32_t>(ctx->segments.size())) {
    return 0;
  }
  return ctx->segments[i].t0_ms;
}

int64_t awe_segment_t1_ms(awe_context* ctx, int32_t i) {
  if (ctx == nullptr || i < 0 ||
      i >= static_cast<int32_t>(ctx->segments.size())) {
    return 0;
  }
  return ctx->segments[i].t1_ms;
}

int32_t awe_word_count(awe_context* ctx, int32_t i_seg) {
  if (ctx == nullptr || i_seg < 0 ||
      i_seg >= static_cast<int32_t>(ctx->segments.size())) {
    return 0;
  }
  return static_cast<int32_t>(ctx->segments[i_seg].words.size());
}

const char* awe_word_text(awe_context* ctx, int32_t i_seg, int32_t i_word) {
  if (ctx == nullptr || i_seg < 0 ||
      i_seg >= static_cast<int32_t>(ctx->segments.size())) {
    return nullptr;
  }
  const auto& words = ctx->segments[i_seg].words;
  if (i_word < 0 || i_word >= static_cast<int32_t>(words.size())) return nullptr;
  return words[i_word].text.c_str();
}

int64_t awe_word_t0_ms(awe_context* ctx, int32_t i_seg, int32_t i_word) {
  if (ctx == nullptr || i_seg < 0 ||
      i_seg >= static_cast<int32_t>(ctx->segments.size())) {
    return 0;
  }
  const auto& words = ctx->segments[i_seg].words;
  if (i_word < 0 || i_word >= static_cast<int32_t>(words.size())) return 0;
  return words[i_word].t0_ms;
}

int64_t awe_word_t1_ms(awe_context* ctx, int32_t i_seg, int32_t i_word) {
  if (ctx == nullptr || i_seg < 0 ||
      i_seg >= static_cast<int32_t>(ctx->segments.size())) {
    return 0;
  }
  const auto& words = ctx->segments[i_seg].words;
  if (i_word < 0 || i_word >= static_cast<int32_t>(words.size())) return 0;
  return words[i_word].t1_ms;
}

const char* awe_last_error(awe_context* ctx) {
  if (ctx == nullptr || ctx->last_error.empty()) return nullptr;
  return ctx->last_error.c_str();
}

void awe_free(awe_context* ctx) {
  if (ctx == nullptr) return;
  if (ctx->ctx != nullptr) {
    whisper_free(ctx->ctx);
    ctx->ctx = nullptr;
  }
  delete ctx;
}

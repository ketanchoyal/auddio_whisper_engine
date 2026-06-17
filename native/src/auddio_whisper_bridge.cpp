#include "auddio_whisper_bridge.h"

#include <exception>
#include <string>
#include <vector>

#include "whisper.h"

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

awe_context* awe_init(const char* model_path, bool use_gpu) {
  // No exception may cross this C ABI boundary: an uncaught C++ throw would
  // unwind into Dart FFI with no handler and abort the whole app.
  try {
    if (model_path == nullptr) return nullptr;
    auto* wrapper = new awe_context();

    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = use_gpu;
    cparams.dtw_token_timestamps = true;
    cparams.dtw_aheads_preset = WHISPER_AHEADS_BASE_EN;

    wrapper->ctx = whisper_init_from_file_with_params(model_path, cparams);
    if (wrapper->ctx == nullptr) {
      wrapper->last_error = "whisper_init_from_file_with_params returned null";
      return wrapper;
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
        current.t1_ms = tok_t1;
        have_current = true;
      } else {
        if (!have_current) {
          current.t0_ms = tok_t0;
          have_current = true;
        }
        current.text += piece;
        current.t1_ms = tok_t1;
      }
    }
    flush();

    ctx->segments.push_back(std::move(seg));
  }

  return 0;
}

int32_t awe_transcribe(awe_context* ctx, const float* samples,
                       int32_t n_samples, int32_t n_threads) {
  if (ctx == nullptr || ctx->ctx == nullptr || samples == nullptr) return -1;
  try {
    return awe_transcribe_impl(ctx, samples, n_samples, n_threads);
  } catch (const std::exception& e) {
    ctx->segments.clear();
    ctx->last_error = std::string("native exception: ") + e.what();
    return -2;
  } catch (...) {
    ctx->segments.clear();
    ctx->last_error = "unknown native exception during transcription";
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

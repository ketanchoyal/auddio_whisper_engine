// Apple implementation of awe_decode_audio_window.
//
// Uses ExtAudioFile (AudioToolbox) which handles all system-supported codecs
// (AAC, MP3, ALAC, FLAC, WAV, etc.) and automatically resamples + downmixes
// to our target format (16kHz mono float32) during the read call.
//
// This file is Objective-C++ (.mm) only to allow compilation alongside
// the CoreML .mm files already in the whisper.cpp build; no Obj-C runtime
// features are used — the entire API is plain C.

#include "awe_audio_decoder.h"

#include <AudioToolbox/AudioToolbox.h>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

static const double kTargetSampleRate = 16000.0;

static char* make_error(const char* msg) {
  char* err = static_cast<char*>(malloc(strlen(msg) + 1));
  if (err) strcpy(err, msg);
  return err;
}

static char* make_error_osstatus(const char* prefix, OSStatus status) {
  std::string msg = std::string(prefix) + " (OSStatus " + std::to_string(status) + ")";
  return make_error(msg.c_str());
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

  // 1. Open the audio file.
  CFURLRef file_url = CFURLCreateFromFileSystemRepresentation(
      kCFAllocatorDefault,
      reinterpret_cast<const UInt8*>(file_path),
      static_cast<CFIndex>(strlen(file_path)),
      false);
  if (!file_url) {
    *out_error = make_error("Failed to create CFURL from file path");
    return -1;
  }

  ExtAudioFileRef audio_file = nullptr;
  OSStatus status = ExtAudioFileOpenURL(file_url, &audio_file);
  CFRelease(file_url);
  if (status != noErr || !audio_file) {
    *out_error = make_error_osstatus("ExtAudioFileOpenURL failed", status);
    return -1;
  }

  // 2. Define the target client format: 16kHz, mono, float32 PCM.
  // Setting this property tells ExtAudioFile to automatically resample and
  // downmix during reads — no manual conversion needed.
  AudioStreamBasicDescription client_format = {};
  client_format.mSampleRate       = kTargetSampleRate;
  client_format.mFormatID         = kAudioFormatLinearPCM;
  client_format.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  client_format.mBytesPerPacket   = sizeof(float);
  client_format.mFramesPerPacket  = 1;
  client_format.mBytesPerFrame    = sizeof(float);
  client_format.mChannelsPerFrame = 1;  // mono
  client_format.mBitsPerChannel   = 32;

  status = ExtAudioFileSetProperty(audio_file,
                                   kExtAudioFileProperty_ClientDataFormat,
                                   sizeof(client_format),
                                   &client_format);
  if (status != noErr) {
    ExtAudioFileDispose(audio_file);
    *out_error = make_error_osstatus("Failed to set client format", status);
    return -1;
  }

  // 3. Get the native file data format to determine its sample rate.
  // ExtAudioFileSeek expects the frame index in the file's native sample rate.
  AudioStreamBasicDescription file_format = {};
  UInt32 prop_size = sizeof(file_format);
  status = ExtAudioFileGetProperty(audio_file,
                                   kExtAudioFileProperty_FileDataFormat,
                                   &prop_size,
                                   &file_format);
  if (status != noErr) {
    ExtAudioFileDispose(audio_file);
    *out_error = make_error_osstatus("Failed to get native file format", status);
    return -1;
  }
  double file_sample_rate = file_format.mSampleRate;

  SInt64 start_frame = static_cast<SInt64>((start_ms * file_sample_rate) / 1000.0);
  status = ExtAudioFileSeek(audio_file, start_frame);
  if (status != noErr) {
    ExtAudioFileDispose(audio_file);
    *out_error = make_error_osstatus("ExtAudioFileSeek failed", status);
    return -1;
  }

  // 4. Read exactly duration_ms worth of frames (or less at EOF).
  int64_t total_frames = static_cast<int64_t>((duration_ms * kTargetSampleRate) / 1000.0);
  if (total_frames <= 0) {
    ExtAudioFileDispose(audio_file);
    *out_error = make_error("duration_ms produces 0 frames");
    return -1;
  }

  std::vector<float> pcm;
  pcm.resize(static_cast<size_t>(total_frames));

  // Read in chunks to handle large windows without a single giant alloc.
  static const UInt32 kChunkFrames = 8192;
  int64_t frames_read = 0;

  while (frames_read < total_frames) {
    UInt32 frames_to_read = static_cast<UInt32>(
        std::min(static_cast<int64_t>(kChunkFrames), total_frames - frames_read));

    AudioBufferList buf_list;
    buf_list.mNumberBuffers = 1;
    buf_list.mBuffers[0].mNumberChannels = 1;
    buf_list.mBuffers[0].mDataByteSize = frames_to_read * sizeof(float);
    buf_list.mBuffers[0].mData = pcm.data() + frames_read;

    UInt32 got = frames_to_read;
    status = ExtAudioFileRead(audio_file, &got, &buf_list);
    if (status != noErr) {
      ExtAudioFileDispose(audio_file);
      *out_error = make_error_osstatus("ExtAudioFileRead failed", status);
      return -1;
    }
    if (got == 0) break;  // EOF
    frames_read += got;
  }

  ExtAudioFileDispose(audio_file);

  if (frames_read == 0) {
    *out_error = make_error("Decoded 0 frames from audio file");
    return -1;
  }

  // 5. Return the buffer. Caller (the bridge) frees it.
  pcm.resize(static_cast<size_t>(frames_read));
  float* result = static_cast<float*>(malloc(static_cast<size_t>(frames_read) * sizeof(float)));
  if (!result) {
    *out_error = make_error("malloc failed for PCM buffer");
    return -1;
  }
  memcpy(result, pcm.data(), static_cast<size_t>(frames_read) * sizeof(float));
  *out_samples = result;
  *out_n_samples = static_cast<int32_t>(frames_read);
  return 0;
}

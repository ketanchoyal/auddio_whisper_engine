@TestOn('mac-os || linux')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:auddio_whisper_engine/auddio_whisper_engine.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _ensureModel(String? customPath) async {
  if (customPath != null && File(customPath).existsSync()) {
    return customPath;
  }
  
  // Default to a local cached path in .dart_tool/whisper_models
  final targetDir = Directory('.dart_tool/whisper_models');
  if (!targetDir.existsSync()) {
    targetDir.createSync(recursive: true);
  }
  final modelFile = File('${targetDir.path}/ggml-tiny.en.bin');
  if (modelFile.existsSync() && modelFile.lengthSync() > 10000000) {
    return modelFile.path;
  }

  print('Downloading ggml-tiny.en.bin (~75MB) to ${modelFile.path}...');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin'));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('Failed to download model: HTTP ${response.statusCode}');
    }
    final fileStream = modelFile.openWrite();
    await response.pipe(fileStream);
    print('Download complete.');
    return modelFile.path;
  } catch (e) {
    if (modelFile.existsSync()) {
      try {
        modelFile.deleteSync();
      } catch (_) {}
    }
    rethrow;
  } finally {
    client.close();
  }
}

Future<String> _ensureAudio(String? customPath) async {
  if (customPath != null && File(customPath).existsSync()) {
    return customPath;
  }

  // Default to a local cached jfk.wav in .dart_tool/whisper_models
  final targetDir = Directory('.dart_tool/whisper_models');
  if (!targetDir.existsSync()) {
    targetDir.createSync(recursive: true);
  }
  final audioFile = File('${targetDir.path}/jfk.wav');
  if (audioFile.existsSync() && audioFile.lengthSync() > 10000) {
    return audioFile.path;
  }

  print('Downloading jfk.wav (~160KB) to ${audioFile.path}...');
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(
        'https://github.com/ggerganov/whisper.cpp/raw/master/samples/jfk.wav'));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('Failed to download audio: HTTP ${response.statusCode}');
    }
    final fileStream = audioFile.openWrite();
    await response.pipe(fileStream);
    print('Download complete.');
    return audioFile.path;
  } catch (e) {
    if (audioFile.existsSync()) {
      try {
        audioFile.deleteSync();
      } catch (_) {}
    }
    rethrow;
  } finally {
    client.close();
  }
}

void main() {
  final dylibPath = Platform.environment['AWE_DYLIB'] ?? 'build/output/libauddio_whisper.dylib';
  final modelPathEnv = Platform.environment['AWE_MODEL'];
  final audioPathEnv = Platform.environment['AWE_AUDIO'];

  test('transcribeFileWindow with a real model and audio file', () async {
    // 1. Check if the dylib is available
    var libPath = dylibPath;
    if (!File(libPath).existsSync()) {
      final localDylib = 'native/build/macos/Release/auddio_whisper.framework/auddio_whisper';
      if (File(localDylib).existsSync()) {
        libPath = localDylib;
      } else {
        markTestSkipped(
          'Skipping: Native library not found at "$libPath" or "$localDylib".',
        );
        return;
      }
    }

    // 2. Ensure the audio file is downloaded/available
    late final String audioPath;
    try {
      audioPath = await _ensureAudio(audioPathEnv);
    } catch (e) {
      markTestSkipped('Skipping: Failed to download/ensure audio file: $e');
      return;
    }

    // 3. Ensure the model file is downloaded/available
    late final String modelPath;
    try {
      modelPath = await _ensureModel(modelPathEnv);
    } catch (e) {
      markTestSkipped('Skipping: Failed to download/ensure Whisper model: $e');
      return;
    }

    print('Using dylib: $libPath');
    print('Using model: $modelPath');
    print('Using audio: $audioPath');

    late final AuddioWhisperEngine engine;
    try {
      engine = AuddioWhisperEngine.open(
        modelPath: modelPath,
        useGpu: false, // Use CPU for local test consistency
        customLibrary: DynamicLibrary.open(libPath),
      );
    } catch (e) {
      fail('Failed to initialize Whisper engine: $e');
    }

    try {
      // Transcribe the entire jfk.wav (11 seconds)
      final segments = engine.transcribeFileWindow(
        filePath: audioPath,
        startMs: 0,
        durationMs: 11000,
      );

      print('Transcribed ${segments.length} segments:');
      var fullText = '';
      for (final seg in segments) {
        print('[${seg.startMs}ms - ${seg.endMs}ms]: ${seg.text}');
        fullText += ' ${seg.text}';
        for (final word in seg.words) {
          print('  - "${word.text}" [${word.startMs}ms - ${word.endMs}ms]');
        }
      }

      // Basic assertions
      expect(segments, isNotEmpty, reason: 'Should decode and transcribe some speech');
      expect(fullText.toLowerCase(), contains('americans'));

      for (final seg in segments) {
        expect(seg.text.trim(), isNotEmpty);
        expect(seg.startMs, isNonNegative);
        expect(seg.endMs, greaterThanOrEqualTo(seg.startMs));
        expect(seg.words, isNotEmpty, reason: 'Each segment should have words');
        
        for (final word in seg.words) {
          expect(word.text.trim(), isNotEmpty);
          expect(word.startMs, isNonNegative);
          expect(word.endMs, greaterThanOrEqualTo(word.startMs));
        }
      }
    } finally {
      engine.dispose();
    }
  });
}

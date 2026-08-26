import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:auddio_whisper_engine/auddio_whisper_engine.dart';

typedef WhisperPrintSystemInfoC = Pointer<Char> Function();
typedef WhisperPrintSystemInfoDart = Pointer<Char> Function();

typedef WhisperLogCallbackC = Void Function(Int32, Pointer<Char>, Pointer<Void>);
typedef WhisperLogSetC = Void Function(Pointer<NativeFunction<WhisperLogCallbackC>>, Pointer<Void>);
typedef WhisperLogSetDart = void Function(Pointer<NativeFunction<WhisperLogCallbackC>>, Pointer<Void>);

final List<String> capturedLogs = [];

void _testLogCallback(int level, Pointer<Char> text, Pointer<Void> userData) {
  if (text != nullptr) {
    final str = text.cast<Utf8>().toDartString();
    capturedLogs.add(str);
  }
}

void main() {
  test('test whisper CoreML initialization and logging', () async {
    final dylib = DynamicLibrary.open(
      '${Directory.current.path}/macos/Frameworks/auddio_whisper.xcframework/macos-arm64_x86_64/auddio_whisper.framework/auddio_whisper',
    );

    final logSet = dylib.lookupFunction<WhisperLogSetC, WhisperLogSetDart>('whisper_log_set');
    final callbackPtr = Pointer.fromFunction<WhisperLogCallbackC>(_testLogCallback);
    logSet(callbackPtr, nullptr);

    final modelDir = Directory('.dart_tool/whisper_models');
    final binFile = File('${modelDir.path}/ggml-tiny.en.bin');
    expect(binFile.existsSync(), isTrue);

    final coremlDir = Directory('${modelDir.path}/ggml-tiny.en-encoder.mlmodelc');
    final coremlZip = File('${modelDir.path}/ggml-tiny.en-encoder.mlmodelc.zip');

    if (!coremlDir.existsSync()) {
      if (!coremlZip.existsSync()) {
        final client = HttpClient();
        final req = await client.getUrl(Uri.parse(
            'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-encoder.mlmodelc.zip'));
        final res = await req.close();
        await res.pipe(coremlZip.openWrite());
        client.close();
      }
      await Process.run('unzip', ['-q', coremlZip.path, '-d', modelDir.path]);
    }

    expect(coremlDir.existsSync(), isTrue);

    capturedLogs.clear();
    final engine = AuddioWhisperEngine.open(
      modelPath: binFile.path,
      customLibrary: dylib,
    );

    // ignore: avoid_print
    print('ALL CAPTURED NATIVE LOGS:');
    for (final log in capturedLogs) {
      // ignore: avoid_print
      print('LOG: ${log.trim()}');
    }
    expect(engine.isCoreMlActive, isTrue);

    engine.dispose();
  });
}

import 'dart:ffi';
import 'dart:io';

typedef AweInitC = Pointer<Void> Function(Pointer<Char>, Bool);
typedef AweInitDart = Pointer<Void> Function(Pointer<Char>, bool);

typedef AweTranscribeC = Int32 Function(
    Pointer<Void>, Pointer<Float>, Int32, Int32);
typedef AweTranscribeDart = int Function(
    Pointer<Void>, Pointer<Float>, int, int);

typedef AweSegCountC = Int32 Function(Pointer<Void>);
typedef AweSegCountDart = int Function(Pointer<Void>);

typedef AweSegTextC = Pointer<Char> Function(Pointer<Void>, Int32);
typedef AweSegTextDart = Pointer<Char> Function(Pointer<Void>, int);

typedef AweSegTimeC = Int64 Function(Pointer<Void>, Int32);
typedef AweSegTimeDart = int Function(Pointer<Void>, int);

typedef AweWordCountC = Int32 Function(Pointer<Void>, Int32);
typedef AweWordCountDart = int Function(Pointer<Void>, int);

typedef AweWordTextC = Pointer<Char> Function(Pointer<Void>, Int32, Int32);
typedef AweWordTextDart = Pointer<Char> Function(Pointer<Void>, int, int);

typedef AweWordTimeC = Int64 Function(Pointer<Void>, Int32, Int32);
typedef AweWordTimeDart = int Function(Pointer<Void>, int, int);

typedef AweLastErrorC = Pointer<Char> Function(Pointer<Void>);
typedef AweLastErrorDart = Pointer<Char> Function(Pointer<Void>);

typedef AweFreeC = Void Function(Pointer<Void>);
typedef AweFreeDart = void Function(Pointer<Void>);

class WhisperBindings {
  WhisperBindings(DynamicLibrary lib)
      : init = lib.lookupFunction<AweInitC, AweInitDart>('awe_init'),
        transcribe = lib
            .lookupFunction<AweTranscribeC, AweTranscribeDart>('awe_transcribe'),
        segmentCount = lib
            .lookupFunction<AweSegCountC, AweSegCountDart>('awe_segment_count'),
        segmentText = lib
            .lookupFunction<AweSegTextC, AweSegTextDart>('awe_segment_text'),
        segmentT0Ms = lib
            .lookupFunction<AweSegTimeC, AweSegTimeDart>('awe_segment_t0_ms'),
        segmentT1Ms = lib
            .lookupFunction<AweSegTimeC, AweSegTimeDart>('awe_segment_t1_ms'),
        wordCount = lib
            .lookupFunction<AweWordCountC, AweWordCountDart>('awe_word_count'),
        wordText = lib
            .lookupFunction<AweWordTextC, AweWordTextDart>('awe_word_text'),
        wordT0Ms = lib
            .lookupFunction<AweWordTimeC, AweWordTimeDart>('awe_word_t0_ms'),
        wordT1Ms = lib
            .lookupFunction<AweWordTimeC, AweWordTimeDart>('awe_word_t1_ms'),
        lastError = lib
            .lookupFunction<AweLastErrorC, AweLastErrorDart>('awe_last_error'),
        free = lib.lookupFunction<AweFreeC, AweFreeDart>('awe_free');

  final AweInitDart init;
  final AweTranscribeDart transcribe;
  final AweSegCountDart segmentCount;
  final AweSegTextDart segmentText;
  final AweSegTimeDart segmentT0Ms;
  final AweSegTimeDart segmentT1Ms;
  final AweWordCountDart wordCount;
  final AweWordTextDart wordText;
  final AweWordTimeDart wordT0Ms;
  final AweWordTimeDart wordT1Ms;
  final AweLastErrorDart lastError;
  final AweFreeDart free;
}

DynamicLibrary openWhisperLibrary() {
  if (Platform.isIOS || Platform.isMacOS) {
    // FRAMEWORK TRUE CMake target -> auddio_whisper.framework/auddio_whisper,
    // embedded via the podspec vendored_frameworks.
    return DynamicLibrary.open('auddio_whisper.framework/auddio_whisper');
  }
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libauddio_whisper.so');
  }
  throw UnsupportedError(
    'auddio_whisper_engine: unsupported platform ${Platform.operatingSystem}',
  );
}

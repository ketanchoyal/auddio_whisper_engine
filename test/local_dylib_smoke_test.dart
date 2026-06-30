@TestOn('mac-os')
library;

import 'dart:ffi';
import 'dart:io';

import 'package:auddio_whisper_engine/src/bindings.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

// Opens the locally-built macOS dylib by absolute path (via AWE_DYLIB env) and
// exercises the real C-ABI, with no network/model. Proves the built binary's
// symbols resolve and the FFI calling convention + error path work end-to-end.
void main() {
  final dylibPath = Platform.environment['AWE_DYLIB'];

  test('built dylib exposes a callable awe_* C-ABI', () {
    var path = dylibPath;
    if (path == null || !File(path).existsSync()) {
      final localDylib = 'native/build/macos/Release/auddio_whisper.framework/auddio_whisper';
      if (File(localDylib).existsSync()) {
        path = localDylib;
      } else {
        markTestSkipped('set AWE_DYLIB to the built framework binary path');
        return;
      }
    }

    final bindings = WhisperBindings(DynamicLibrary.open(path));

    final badPath = '/definitely/missing/model.bin'.toNativeUtf8();
    try {
      final ctx = bindings.init(badPath.cast<Char>(), false, -1);
      expect(ctx, isNot(nullptr),
          reason: 'awe_init returns a wrapper even on load failure');

      final err = bindings.lastError(ctx);
      expect(err, isNot(nullptr),
          reason: 'awe_last_error reports the failed model load');

      bindings.free(ctx);
    } finally {
      calloc.free(badPath);
    }
  });
}

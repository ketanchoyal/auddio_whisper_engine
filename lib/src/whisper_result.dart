class WhisperWord {
  const WhisperWord({
    required this.text,
    required this.startMs,
    required this.endMs,
    this.confidence = 1.0,
  });

  final String text;
  final int startMs;
  final int endMs;
  final double confidence;
}

class WhisperSegment {
  const WhisperSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
    required this.words,
  });

  final String text;
  final int startMs;
  final int endMs;
  final List<WhisperWord> words;
}

class WhisperEngineException implements Exception {
  const WhisperEngineException(this.message);
  final String message;

  @override
  String toString() => 'WhisperEngineException: $message';
}

/// Extrae símbolos de ticker del mensaje del usuario para modo explore.
abstract final class TickerExtractor {
  static const _maxTickers = 3;

  static const _stopWords = {
    'I',
    'A',
    'EL',
    'LA',
    'YO',
    'QUE',
    'COMO',
  };

  static final _tickerPattern = RegExp(r'\b[A-Z]{1,5}\b');

  static List<String> extractTickers(String message) {
    final matches = _tickerPattern.allMatches(message);
    final seen = <String>{};
    final result = <String>[];

    for (final match in matches) {
      final ticker = match.group(0)!;
      if (_stopWords.contains(ticker)) continue;
      if (seen.add(ticker)) {
        result.add(ticker);
        if (result.length >= _maxTickers) break;
      }
    }

    return result;
  }
}

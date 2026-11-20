/// Espacia llamadas consecutivas a OpenAI para reducir 429 por ráfagas.
abstract final class OpenAiRequestThrottle {
  static const minInterval = Duration(seconds: 2);

  static DateTime? _lastRequestAt;

  static Future<void> waitIfNeeded() async {
    final last = _lastRequestAt;
    if (last == null) return;

    final elapsed = DateTime.now().difference(last);
    if (elapsed >= minInterval) return;

    await Future.delayed(minInterval - elapsed);
  }

  static void markRequestStarted() {
    _lastRequestAt = DateTime.now();
  }
}

import 'package:flutter/foundation.dart';

/// Desde dónde se abrió el paywall ("analysis_locked_news", "chip_news",
/// "weekly_free_analysis"…).
///
/// La app todavía no tiene telemetría de eventos: por ahora solo queda en
/// memoria (para tests) y en consola en debug. Cuando haya una (Mixpanel,
/// Firebase, una tabla en Supabase), se conecta en [record] y el resto de la
/// app no cambia.
abstract final class PaywallSourceLog {
  static final _recent = <String>[];

  /// Últimas aperturas, más reciente al final (tope chico, solo diagnóstico).
  static List<String> get recent => List.unmodifiable(_recent);

  static void record(String source) {
    _recent.add(source);
    if (_recent.length > 50) _recent.removeAt(0);
    if (kDebugMode) debugPrint('[Paywall] source=$source');
  }

  @visibleForTesting
  static void clear() => _recent.clear();
}

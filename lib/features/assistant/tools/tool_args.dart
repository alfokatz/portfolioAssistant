/// Lectura defensiva de argumentos de tools: el modelo "does not always
/// generate valid JSON, and may hallucinate parameters" (spec de OpenAI),
/// así que nada se castea sin chequear.
abstract final class ToolArgs {
  static final _ticker = RegExp(r'^[A-Z][A-Z0-9.\-]{0,9}$');

  static Map<String, Object?> invalid() => const {
    'status': 'failed',
    'reason': 'invalid_arguments',
  };

  /// Tickers en mayúsculas, sin repetidos, máximo [max].
  static List<String> tickers(
    Map<String, Object?> args, {
    String key = 'tickers',
    int max = 3,
  }) {
    final raw = args[key];
    if (raw is! List) return const [];
    final out = <String>[];
    for (final item in raw) {
      if (item is! String) continue;
      final t = item.trim().replaceFirst(RegExp(r'^\$'), '').toUpperCase();
      if (_ticker.hasMatch(t) && !out.contains(t)) out.add(t);
      if (out.length == max) break;
    }
    return out;
  }

  static String? string(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static double? number(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', '.'));
    return null;
  }

  /// Fecha `YYYY-MM-DD` (o `YYYY-MM`, se toma el día 1).
  static DateTime? date(Map<String, Object?> args, String key) {
    final value = string(args, key);
    if (value == null) return null;
    final normalized =
        RegExp(r'^\d{4}-\d{2}$').hasMatch(value) ? '$value-01' : value;
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null || parsed.year < 1900 || parsed.year > 2200) return null;
    return parsed;
  }

  static List<String> strings(Map<String, Object?> args, String key) {
    final raw = args[key];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is String && item.trim().isNotEmpty) item.trim(),
    ];
  }
}

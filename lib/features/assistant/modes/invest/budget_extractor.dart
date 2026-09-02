/// Extrae un monto en USD del mensaje del usuario.
abstract final class BudgetExtractor {

  static final _budgetPattern = RegExp(
    r'\$?\s*(\d[\d.,]*)'
    r'(?!\d)'
    r'(?:\s*(mill[oó]n(?:es)?|mil\b)|(k|m)\b)?'
    r'(?!\s*(?:años?|anos?|years?|mes(?:es)?|months?))',
    caseSensitive: false,
  );

  /// Ignora números que forman parte de una expresión temporal (p. ej. "5
  /// años") y reconoce multiplicadores en palabras ("mil", "millón/millones")
  /// o abreviados ("k", "m").
  static double? extractBudgetUsd(String message) {
    final match = _budgetPattern.firstMatch(message);
    if (match == null) return null;

    final raw = match.group(1);
    if (raw == null || raw.isEmpty) return null;

    final amount = _parseAmount(raw);
    if (amount == null) return null;

    return amount * _multiplierFor(match.group(2) ?? match.group(3));
  }

  static double _multiplierFor(String? word) {
    if (word == null) return 1;
    final normalized = word.toLowerCase();
    if (normalized.startsWith('mill')) return 1000000;
    if (normalized == 'mil' || normalized == 'k') return 1000;
    if (normalized == 'm') return 1000000;
    return 1;
  }

  static double? _parseAmount(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return null;

    final lastComma = normalized.lastIndexOf(',');
    final lastPeriod = normalized.lastIndexOf('.');

    String digitsOnly;
    if (lastComma > lastPeriod) {
      final afterComma = normalized.substring(lastComma + 1);
      if (afterComma.length == 2) {
        // 1.234,56 o 500,00
        digitsOnly = normalized.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // 1,000 o 1,234,567
        digitsOnly = normalized.replaceAll(',', '');
      }
    } else if (lastPeriod > lastComma) {
      final afterPeriod = normalized.substring(lastPeriod + 1);
      if (afterPeriod.length == 2) {
        // 1,234.56 o 500.00
        digitsOnly = normalized.replaceAll(',', '');
      } else {
        // 1.000 o 1.234.567
        digitsOnly = normalized.replaceAll('.', '');
      }
    } else {
      digitsOnly = normalized.replaceAll(',', '');
    }

    final value = double.tryParse(digitsOnly);
    if (value == null || value <= 0) return null;
    return value;
  }
}

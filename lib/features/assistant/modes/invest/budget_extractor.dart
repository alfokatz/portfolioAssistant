/// Extrae un monto en USD del mensaje del usuario.
abstract final class BudgetExtractor {

  static final _budgetPattern = RegExp(r'\$?\s*(\d[\d.,]*)');

  static double? extractBudgetUsd(String message) {
    final match = _budgetPattern.firstMatch(message);
    if (match == null) return null;

    final raw = match.group(1);
    if (raw == null || raw.isEmpty) return null;

    return _parseAmount(raw);
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

/// Extrae datos de meta financiera del mensaje del usuario.
abstract final class GoalExtractor {
  static const _defaultLabel = 'Mi meta';

  static final _amountPattern = RegExp(
    r'\$?\s*(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?|\d+(?:[.,]\d{2})?)',
  );

  static final _yearsPattern = RegExp(
    r'(?:en|para|dentro de|in|within|by)\s+(\d+)\s+(?:años?|anos?|years?)',
    caseSensitive: false,
  );

  static final _monthsPattern = RegExp(
    r'(?:en|para|dentro de|in|within)\s+(\d+)\s+(?:meses?|months?)',
    caseSensitive: false,
  );

  static final _yearOnlyPattern = RegExp(
    r'(?:para|en|by|for)\s+(\d{4})\b',
    caseSensitive: false,
  );

  static final _monthYearPattern = RegExp(
    r'(?:en|para|by|for)\s+'
    r'(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre|'
    r'january|february|march|april|may|june|july|august|september|october|november|december)'
    r'\s+(?:de\s+)?(\d{4})',
    caseSensitive: false,
  );

  static final _labelPattern = RegExp(
    r'(?:meta|objetivo|goal)\s*(?:de|:)?\s*([a-záéíóúñ\s]{3,40})',
    caseSensitive: false,
  );

  static final _saveForPattern = RegExp(
    r'(?:ahorrar|guardar|save)\s+(?:para|for)\s+(?:un[a]?\s+)?([a-záéíóúñ\s]{3,40})',
    caseSensitive: false,
  );

  static const _monthNumbers = <String, int>{
    'enero': 1,
    'febrero': 2,
    'marzo': 3,
    'abril': 4,
    'mayo': 5,
    'junio': 6,
    'julio': 7,
    'agosto': 8,
    'septiembre': 9,
    'octubre': 10,
    'noviembre': 11,
    'diciembre': 12,
    'january': 1,
    'february': 2,
    'march': 3,
    'april': 4,
    'may': 5,
    'june': 6,
    'july': 7,
    'august': 8,
    'september': 9,
    'october': 10,
    'november': 11,
    'december': 12,
  };

  /// Extrae el monto objetivo en USD del mensaje (mismo patrón que [BudgetExtractor]).
  static double? extractTargetAmount(String message) {
    final match = _amountPattern.firstMatch(message);
    if (match == null) return null;

    final raw = match.group(1);
    if (raw == null || raw.isEmpty) return null;

    return _parseAmount(raw);
  }

  /// Extrae la fecha objetivo del mensaje.
  ///
  /// Soporta patrones como "en 5 años", "para 2030", "en diciembre 2028".
  static DateTime? extractTargetDate(String message, {DateTime? asOf}) {
    final reference = asOf ?? DateTime.now();

    final monthYearMatch = _monthYearPattern.firstMatch(message);
    if (monthYearMatch != null) {
      final monthName = monthYearMatch.group(1)?.toLowerCase();
      final year = int.tryParse(monthYearMatch.group(2) ?? '');
      final month = monthName == null ? null : _monthNumbers[monthName];
      if (month != null && year != null) {
        return DateTime(year, month);
      }
    }

    final yearsMatch = _yearsPattern.firstMatch(message);
    if (yearsMatch != null) {
      final years = int.tryParse(yearsMatch.group(1) ?? '');
      if (years != null && years > 0) {
        return DateTime(reference.year + years, reference.month, reference.day);
      }
    }

    final monthsMatch = _monthsPattern.firstMatch(message);
    if (monthsMatch != null) {
      final months = int.tryParse(monthsMatch.group(1) ?? '');
      if (months != null && months > 0) {
        return _addMonths(reference, months);
      }
    }

    final yearMatch = _yearOnlyPattern.firstMatch(message);
    if (yearMatch != null) {
      final year = int.tryParse(yearMatch.group(1) ?? '');
      if (year != null) {
        return DateTime(year);
      }
    }

    return null;
  }

  /// Extrae una etiqueta descriptiva de la meta; devuelve [_defaultLabel] si no hay match.
  static String extractGoalLabel(String message) {
    final labelMatch = _labelPattern.firstMatch(message);
    if (labelMatch != null) {
      final label = _cleanLabel(labelMatch.group(1));
      if (label != null) return label;
    }

    final saveForMatch = _saveForPattern.firstMatch(message);
    if (saveForMatch != null) {
      final label = _cleanLabel(saveForMatch.group(1));
      if (label != null) return label;
    }

    return _defaultLabel;
  }

  static String? _cleanLabel(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.length < 3) return null;
    return _titleCase(cleaned);
  }

  static String _titleCase(String value) {
    return value
        .split(' ')
        .map(
          (word) =>
              word.isEmpty
                  ? word
                  : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static DateTime _addMonths(DateTime date, int months) {
    final totalMonths = date.year * 12 + date.month - 1 + months;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    return DateTime(year, month, date.day);
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
        digitsOnly = normalized.replaceAll('.', '').replaceAll(',', '.');
      } else {
        digitsOnly = normalized.replaceAll(',', '');
      }
    } else if (lastPeriod > lastComma) {
      final afterPeriod = normalized.substring(lastPeriod + 1);
      if (afterPeriod.length == 2) {
        digitsOnly = normalized.replaceAll(',', '');
      } else {
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

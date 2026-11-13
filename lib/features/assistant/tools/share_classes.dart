/// Empresas que cotizan con más de una clase de acción. "Compré 5 acciones
/// de Alphabet" puede ser GOOGL o GOOG, y el precio y los derechos de voto
/// no son los mismos: Porty no adivina (eval `action-ambiguous-company`).
/// El modelo a veces se saltea `search_symbol` porque "sabe" el ticker, así
/// que la guarda está en las tools de operaciones, no solo en el prompt.
abstract final class ShareClasses {
  static const _families = <Map<String, String>>[
    {
      'GOOGL': 'Alphabet Clase A (con voto)',
      'GOOG': 'Alphabet Clase C (sin voto)',
    },
    {
      'BRK-B': 'Berkshire Hathaway Clase B',
      'BRK-A': 'Berkshire Hathaway Clase A',
    },
    {'FOXA': 'Fox Corp Clase A', 'FOX': 'Fox Corp Clase B'},
    {'NWSA': 'News Corp Clase A', 'NWS': 'News Corp Clase B'},
    {'UAA': 'Under Armour Clase A', 'UA': 'Under Armour Clase C'},
  ];

  /// Qué decirle al modelo cuando la clase es ambigua.
  static const guide =
      'This company trades as several share classes and the user did not '
      'say which one. Do NOT propose any operation. In QaAnswerText, ask '
      'which one they mean, naming EVERY symbol in matches with its '
      'description. Never guess.';

  /// `{status: ambiguous, reason: share_class, matches}` si [ticker] es de
  /// una empresa con varias clases y no queda claro cuál: el usuario no
  /// escribió ninguno de esos tickers y no tiene exactamente una de las
  /// clases en cartera. null si no hay ambigüedad o si no se sabe qué
  /// escribió el usuario ([userText] null).
  static Map<String, Object?>? ambiguity(
    String? ticker, {
    required String? userText,
    required Set<String> held,
  }) {
    if (ticker == null || userText == null) return null;
    final family = _familyOf(_normalize(ticker));
    if (family == null) return null;
    final written = family.keys.any((t) => _mentions(userText, t));
    if (written) return null;
    final heldHere = family.keys.where((t) => held.map(_normalize).contains(t));
    if (heldHere.length == 1 && heldHere.first == _normalize(ticker)) {
      return null;
    }
    return {
      'status': 'ambiguous',
      'reason': 'share_class',
      'matches': [
        for (final e in family.entries)
          {'symbol': e.key, 'description': e.value},
      ],
    };
  }

  static Map<String, String>? _familyOf(String ticker) {
    for (final f in _families) {
      if (f.containsKey(ticker)) return f;
    }
    return null;
  }

  /// BRK.B, brk-b → BRK-B.
  static String _normalize(String t) =>
      t.trim().toUpperCase().replaceAll('.', '-');

  /// El ticker escrito tal cual (en mayúsculas, como palabra): "GOOG" no
  /// cuenta dentro de "GOOGL", y "Fox" (el nombre) no es "FOX".
  static bool _mentions(String text, String ticker) {
    final variants = {
      ticker,
      ticker.replaceAll('-', '.'),
      ticker.replaceAll('-', ''),
    };
    return variants.any(
      (v) => RegExp(
        '(^|[^A-Za-z0-9])${RegExp.escape(v)}(?![A-Za-z0-9])',
      ).hasMatch(text),
    );
  }
}

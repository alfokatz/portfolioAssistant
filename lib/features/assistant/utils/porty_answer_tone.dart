import 'package:genui/genui.dart';

/// Si una respuesta de Porty trae una mala noticia sobre la cartera, para
/// que el avatar no sonría al terminarla (ver `PortyMood.doneSpeaking`).
///
/// Solo cuenta la cartera entera: su variación en el período, su P&L total
/// o lo realizado con las ventas, en negativo; o un texto que dice que la
/// cartera bajó o que el usuario perdió. Una posición en rojo o el día
/// negativo de una acción no cuentan: si no, Porty casi nunca sonreiría.
///
/// Si una card trae el resultado de la cartera, decide ese número: el texto
/// no lo contradice ("cuánto ganaste o perdiste" sobre una cartera en verde
/// dejaba a Porty triste, bug 2026-10-06).
abstract final class PortyAnswerTone {
  /// Campos de cada card que son el resultado de la cartera entera (ver los
  /// schemas del catálogo). Solo se miran en el nivel de la card, no en sus
  /// listas de posiciones.
  static const _portfolioResultFields = {
    'QaPeriodChange': ['changeAbs', 'changePct'],
    'QaPositionsSnapshot': ['pnlAbs', 'pnlPct'],
    'QaPnLBreakdown': ['gainLoss', 'gainLossPercent'],
    'QaClosedPositionList': ['totalPnlAbs', 'totalPnlPct'],
  };

  /// "Tu cartera bajó 3 %", "el portfolio cayó", "perdiste 40 dólares",
  /// "tus inversiones están en rojo".
  static final _portfolioLoss = RegExp(
    r'\b(cartera|portfolio|portafolio|inversiones)\b[^.!?]{0,40}?'
    r'\b(baj[oó]|bajaron|cay[oó]|cayeron|perdi[oó]|perdieron|retroced|'
    r'en rojo|en negativo)',
    caseSensitive: false,
  );
  static final _youLost = RegExp(
    r'\b(perdiste|est[aá]s perdiendo|vas perdiendo)\b',
    caseSensitive: false,
  );

  /// Lo que nombra la pérdida sin afirmarla: "cuánto ganaste o perdiste",
  /// "si perdiste o ganaste", "no perdiste". Se saca antes de buscar.
  static final _notALoss = RegExp(
    r'\b(gan\w*\s+o\s+perd\w*|perd\w*\s+o\s+gan\w*|no\s+perd\w*)',
    caseSensitive: false,
  );

  static bool showsLoss(SurfaceDefinition? definition) {
    if (definition == null) return false;
    // null: ninguna card trae el resultado de la cartera.
    bool? cardsLoss;
    var textLoss = false;
    for (final component in definition.components.values) {
      final props = component.properties;
      for (final field in _portfolioResultFields[component.type] ?? const []) {
        final value = props[field];
        if (value is num) cardsLoss = (cardsLoss ?? false) || value < 0;
      }
      if (component.type == 'QaAnswerText' && textShowsLoss(props['text'])) {
        textLoss = true;
      }
    }
    return cardsLoss ?? textLoss;
  }

  static bool textShowsLoss(Object? text) {
    if (text is! String) return false;
    final claim = text.replaceAll(_notALoss, '');
    return _portfolioLoss.hasMatch(claim) || _youLost.hasMatch(claim);
  }
}

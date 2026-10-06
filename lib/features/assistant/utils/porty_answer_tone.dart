import 'package:genui/genui.dart';

/// Si una respuesta de Porty muestra una mala noticia, para que el avatar
/// no sonría al terminarla (ver `PortyMood.doneSpeaking`).
///
/// No hay una señal explícita del modelo, así que se mira lo que la
/// respuesta MUESTRA: cualquier variación negativa en las cards (cambio,
/// P&L, ganancia/pérdida), un aviso de advertencia, o un texto que habla
/// de caídas o con un porcentaje negativo. Ante la duda cuenta como mala
/// noticia: el costo de no sonreír es nulo, el de sonreír ante una pérdida
/// no.
abstract final class PortyAnswerTone {
  /// Campos numéricos de las cards que son una variación (ver los schemas
  /// del catálogo: `changePct`, `dayChangePct`, `pnlAbs`, `gainLoss`,
  /// `totalPnlPct`, `changeAbs`…).
  static final _deltaKey = RegExp(
    r'change|pnl|gainloss|delta',
    caseSensitive: false,
  );

  /// "-3,2 %", "−1.5%", "(-4 %)".
  static final _negativePercent = RegExp(r'(^|[\s(])[-−]\s?\d+([.,]\d+)?\s?%');

  static final _lossWords = RegExp(
    r'\b(baj[oó]|bajaron|cay[oó]|cayeron|ca[ií]da|perd[ií]|perdi[oó]|'
    r'perdiste|p[eé]rdidas?|retroced|en rojo|fell|dropped|lost|losses?)',
    caseSensitive: false,
  );

  static bool showsLoss(SurfaceDefinition? definition) {
    if (definition == null) return false;
    for (final component in definition.components.values) {
      final props = component.properties;
      if (_hasNegativeDelta(props)) return true;
      if (component.type == 'QaTipBanner' && props['warning'] == true) {
        return true;
      }
      if (component.type == 'QaAnswerText' && textShowsLoss(props['text'])) {
        return true;
      }
    }
    return false;
  }

  static bool textShowsLoss(Object? text) =>
      text is String &&
      (_negativePercent.hasMatch(text) || _lossWords.hasMatch(text));

  static bool _hasNegativeDelta(Object? node) {
    if (node is Map) {
      for (final MapEntry(:key, :value) in node.entries) {
        if (value is num && value < 0 && _deltaKey.hasMatch('$key')) {
          return true;
        }
        if (_hasNegativeDelta(value)) return true;
      }
    } else if (node is List) {
      for (final item in node) {
        if (_hasNegativeDelta(item)) return true;
      }
    }
    return false;
  }
}

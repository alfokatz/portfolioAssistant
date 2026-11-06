import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';

/// Hacia dónde se movió la cartera (define el color del widget).
enum WidgetDirection {
  up,
  down,
  flat;

  /// Debajo de este |%| se considera que no se movió.
  static const flatThreshold = 0.3;

  static WidgetDirection fromPercent(double percent) {
    if (percent.abs() < flatThreshold) return WidgetDirection.flat;
    return percent > 0 ? WidgetDirection.up : WidgetDirection.down;
  }

  String get wire => name;
}

/// La frase descriptiva del widget. Sale solo de las plantillas aprobadas
/// por compliance (docs/specs/home-widget-product.md, "Revisión de
/// compliance"): nunca recomienda, da una causa, juzga ni proyecta, y no
/// dice "hoy" sobre datos de otro día. Cualquier plantilla nueva vuelve a
/// pasar por compliance.
abstract final class WidgetPhrase {
  /// [topTicker] ya viene en `null` cuando los montos están ocultos o falta
  /// el dato: acá nunca se decide qué se muestra, solo qué plantilla va.
  static String resolve({
    required DayMovePeriod period,
    required WidgetDirection direction,
    required String? topTicker,
    required WidgetTexts texts,
  }) {
    if (period == DayMovePeriod.lastClose)
      return texts.get('phrase_last_close');
    switch (direction) {
      case WidgetDirection.flat:
        return texts.get('phrase_barely_moved');
      case WidgetDirection.up:
        return topTicker == null
            ? texts.get('phrase_up')
            : texts.get('phrase_up_with', {'ticker': topTicker});
      case WidgetDirection.down:
        return topTicker == null
            ? texts.get('phrase_down')
            : texts.get('phrase_down_with', {'ticker': topTicker});
    }
  }

  /// Datos de más de 24 h o de otro día.
  static String stale(WidgetTexts texts) => texts.get('phrase_stale');
}

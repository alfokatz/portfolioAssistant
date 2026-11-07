import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';

/// Lo que eligió el usuario en la hoja de crear alerta.
enum PriceAlertMode { above, below, percent }

/// Por qué el formulario no es válido (clave de traducción).
enum PriceAlertFormError {
  invalidNumber('price_alert_error_number'),
  alreadyAbove('price_alert_error_already_above'),
  alreadyBelow('price_alert_error_already_below'),
  percentRange('price_alert_error_percent_range'),
  noPrice('price_alert_error_no_price');

  const PriceAlertFormError(this.key);
  final String key;
}

/// "1.234,5" o "1,234.5" o "750" → número. null si no se entiende.
double? parseUserNumber(String raw) {
  var text = raw.trim().replaceAll(RegExp(r'[\s$%]'), '');
  if (text.isEmpty) return null;
  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');
  if (lastComma > lastDot) {
    // La coma es el decimal: los puntos son miles.
    text = text.replaceAll('.', '').replaceAll(',', '.');
  } else {
    text = text.replaceAll(',', '');
  }
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;
  return value;
}

/// Arma el borrador o devuelve el error. [currentPrice] es el precio de
/// ahora: una alerta que ya se cumple no tiene sentido.
({PriceAlertDraft? draft, PriceAlertFormError? error}) buildPriceAlertDraft({
  required String symbol,
  required PriceAlertMode mode,
  required String input,
  required bool percentUp,
  required bool repeatDaily,
  required double? currentPrice,
  String source = 'app',
}) {
  final value = parseUserNumber(input);
  if (value == null || value <= 0) {
    return (draft: null, error: PriceAlertFormError.invalidNumber);
  }
  switch (mode) {
    case PriceAlertMode.above:
      if (currentPrice != null && value <= currentPrice) {
        return (draft: null, error: PriceAlertFormError.alreadyAbove);
      }
      return (
        draft: PriceAlertDraft(
          symbol: symbol,
          condition: PriceAlertCondition.above,
          target: value,
          referencePrice: currentPrice,
          repeatDaily: repeatDaily,
          source: source,
        ),
        error: null,
      );
    case PriceAlertMode.below:
      if (currentPrice != null && value >= currentPrice) {
        return (draft: null, error: PriceAlertFormError.alreadyBelow);
      }
      return (
        draft: PriceAlertDraft(
          symbol: symbol,
          condition: PriceAlertCondition.below,
          target: value,
          referencePrice: currentPrice,
          repeatDaily: repeatDaily,
          source: source,
        ),
        error: null,
      );
    case PriceAlertMode.percent:
      if (currentPrice == null) {
        return (draft: null, error: PriceAlertFormError.noPrice);
      }
      if (value < 1 || value > 90) {
        return (draft: null, error: PriceAlertFormError.percentRange);
      }
      return (
        draft: PriceAlertDraft(
          symbol: symbol,
          condition:
              percentUp
                  ? PriceAlertCondition.pctUp
                  : PriceAlertCondition.pctDown,
          target: value,
          referencePrice: currentPrice,
          repeatDaily: repeatDaily,
          source: source,
        ),
        error: null,
      );
  }
}

/// Un objetivo "redondo" a [pct]% del precio actual, para las sugerencias.
double suggestedTarget(double currentPrice, double pct) {
  final raw = currentPrice * (1 + pct / 100);
  final step =
      raw >= 1000
          ? 10.0
          : raw >= 100
          ? 1.0
          : raw >= 10
          ? 0.5
          : 0.05;
  final rounded = (raw / step).round() * step;
  return double.parse(rounded.toStringAsFixed(2));
}

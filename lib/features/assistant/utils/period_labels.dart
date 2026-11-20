import 'package:portfolio_assistant/config/translate/app_language.dart';

/// Rótulo de cada período de las tools ("último día", "last 7 days"), en
/// minúscula para ir en mitad de frase. Viaja en `label_es` (el nombre del
/// campo quedó de cuando la app era solo en español; el modelo lo copia a
/// `periodLabel` de las cards) en el idioma de la app.
abstract final class PeriodLabels {
  static const durations = <String, Duration>{
    'day': Duration(days: 1),
    'week': Duration(days: 7),
    'month': Duration(days: 30),
    'quarter': Duration(days: 90),
    'year': Duration(days: 365),
  };

  static const _es = {
    'day': 'último día',
    'week': 'últimos 7 días',
    'month': 'últimos 30 días',
    'quarter': 'últimos 90 días',
    'year': 'último año',
  };

  static const _en = {
    'day': 'last day',
    'week': 'last 7 days',
    'month': 'last 30 days',
    'quarter': 'last 90 days',
    'year': 'last year',
  };

  static String of(String period, {String? language}) =>
      ((language ?? AppLanguage.code) == 'en' ? _en : _es)[period] ?? period;
}

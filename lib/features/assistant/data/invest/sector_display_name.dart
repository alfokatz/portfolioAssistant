import 'package:portfolio_assistant/config/translate/app_language.dart';

/// Etiquetas de sector en español para el snapshot y el LLM. El español es
/// el valor canónico (comparaciones, cachés); para MOSTRARLO en la UI usá
/// [localize], que lo pasa al idioma de la app.
abstract final class SectorDisplayName {
  static const _translations = <String, String>{
    'Technology': 'Tecnología',
    'Financials': 'Finanzas',
    'Financial Services': 'Finanzas',
    'Healthcare': 'Salud',
    'Health Care': 'Salud',
    'Energy': 'Energía',
    'Consumer': 'Consumo cíclico',
    'Consumer Cyclical': 'Consumo cíclico',
    'Consumer Defensive': 'Consumo defensivo',
    'Consumer Staples': 'Consumo básico',
    'Industrials': 'Industriales',
    'Real Estate': 'Bienes raíces',
    'Utilities': 'Servicios públicos',
    'Communication Services': 'Comunicaciones',
    'Basic Materials': 'Materiales básicos',
    'Other': 'Sin clasificar',
  };

  static const unclassified = 'Sin clasificar';

  static String fromRaw(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return unclassified;
    return _translations[trimmed] ?? trimmed;
  }

  /// En inglés, el nombre de cada sector canónico (español).
  static const _english = <String, String>{
    'Tecnología': 'Technology',
    'Finanzas': 'Financials',
    'Salud': 'Healthcare',
    'Energía': 'Energy',
    'Consumo cíclico': 'Consumer Cyclical',
    'Consumo defensivo': 'Consumer Defensive',
    'Consumo básico': 'Consumer Staples',
    'Industriales': 'Industrials',
    'Bienes raíces': 'Real Estate',
    'Servicios públicos': 'Utilities',
    'Comunicaciones': 'Communication Services',
    'Materiales básicos': 'Basic Materials',
    'Sin clasificar': 'Unclassified',
  };

  /// [sector] (canónico, en español) en el idioma de la app, para la UI.
  /// Un nombre que no está en la tabla (ya venía en inglés) queda igual.
  static String localize(String sector, {String? language}) =>
      (language ?? AppLanguage.code) == 'en'
          ? _english[sector] ?? sector
          : sector;
}

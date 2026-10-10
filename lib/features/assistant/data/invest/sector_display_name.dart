/// Etiquetas de sector en español para el snapshot y el LLM.
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
}

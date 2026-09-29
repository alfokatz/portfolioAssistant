import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/presentation/base/theme/portfolio_colors.dart';

/// Tokens del kit de widgets GenUI de Porty: la escala tipográfica, los
/// colores derivados y los formatos numéricos que comparten TODAS las cards
/// del catálogo. Ningún widget del catálogo debería declarar un `TextStyle`
/// suelto — si falta un estilo, se agrega acá.
///
/// Todo número usa cifras tabulares, para que columnas y valores que se
/// actualizan (scrub del gráfico, contadores) no bailen de ancho.
abstract final class QaText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Número protagonista de una card (precio, valor del portfolio, meta).
  static const display = TextStyle(
    color: PortfolioColors.textPrimary,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.9,
    height: 1.1,
    fontFeatures: _tabular,
  );

  /// Número destacado secundario (una sola métrica grande dentro de un bloque).
  static const displaySm = TextStyle(
    color: PortfolioColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.15,
    fontFeatures: _tabular,
  );

  /// Título de la card: ticker, nombre de la meta.
  static const title = TextStyle(
    color: PortfolioColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.25,
  );

  /// Texto de lectura dentro de una card (titulares, tesis, resúmenes).
  static const body = TextStyle(
    color: PortfolioColors.textPrimary,
    fontSize: 14,
    height: 1.4,
  );

  static const bodyStrong = TextStyle(
    color: PortfolioColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// Valor de una métrica en una grilla/fila.
  static const value = TextStyle(
    color: PortfolioColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.2,
    fontFeatures: _tabular,
  );

  static const valueSm = TextStyle(
    color: PortfolioColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    fontFeatures: _tabular,
  );

  /// Rótulo de una métrica ("Market cap", "Próximo reporte").
  static const label = TextStyle(
    color: PortfolioColors.textSecondary,
    fontSize: 12,
    height: 1.3,
  );

  /// Encabezado de sección dentro de una card ("VALUACIÓN", "HISTORIAL").
  static const eyebrow = TextStyle(
    color: PortfolioColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    height: 1.2,
  );

  /// Metadatos: fuente y fecha de una noticia, notas al pie.
  static const caption = TextStyle(
    color: PortfolioColors.textSecondary,
    fontSize: 11,
    height: 1.3,
    fontFeatures: _tabular,
  );
}

abstract final class QaPalette {
  /// Paleta categórica para series (segmentos de barras, donuts, leyendas).
  /// Tonos editoriales cálidos que conviven con el terracota de la app — el
  /// orden importa: los primeros tienen más contraste entre sí.
  static const categorical = [
    Color(0xFFD98E5D), // terracota (acento)
    Color(0xFF2F3437), // carbón
    Color(0xFF7A9E7E), // salvia
    Color(0xFFC9B79C), // arena
    Color(0xFF6F8FAF), // azul polvo
    Color(0xFFA86A46), // terracota oscuro
  ];

  static Color series(int index) => categorical[index % categorical.length];

  /// Fondo tenue de superficies internas (bloques dentro de una card).
  static const inset = Color(0xFFF7F6F3);

  static const track = Color(0x0F000000); // 6% — fondo de barras/anillos

  static const profitTint = Color(0x1A346538); // profit @ 10%
  static const lossTint = Color(0x1A9F2F2D); // loss @ 10%
  static const accentTint = Color(0x1FD98E5D); // acento @ 12%

  static Color trend(num value) =>
      value >= 0 ? PortfolioColors.profit : PortfolioColors.loss;

  static Color trendTint(num value) => value >= 0 ? profitTint : lossTint;
}

/// Espaciado y geometría del kit.
abstract final class QaSpace {
  static const cardPadding = 16.0;
  static const cardRadius = 16.0;
  static const insetRadius = 12.0;
  static const chipRadius = 8.0;
  static const gap = 12.0;
  static const sectionGap = 16.0;
}

/// Formatos numéricos compartidos. Mantener acá los criterios (cuántos
/// decimales, cuándo compactar) para que "$1.4K" o "+2.1%" se lean igual
/// en todas las cards.
abstract final class QaFormat {
  static final _usd0 = NumberFormat.currency(symbol: '\$', decimalDigits: 0);
  static final _usd2 = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
  static final _compact = NumberFormat.compactCurrency(
    symbol: '\$',
    decimalDigits: 1,
  );

  /// Precio de un activo: siempre dos decimales.
  static String price(num value) => _usd2.format(value);

  /// Montos de portfolio/presupuesto: sin decimales hasta 100K, compacto
  /// después ("$1.2M").
  static String money(num value) =>
      value.abs() >= 100000 ? _compact.format(value) : _usd0.format(value);

  static String moneyCompact(num value) => _compact.format(value);

  /// Monto con signo explícito ("+$428", "-$7").
  static String signedMoney(num value) {
    final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
    return '$sign${money(value.abs())}';
  }

  static String signedPrice(num value) {
    final sign = value > 0 ? '+' : (value < 0 ? '-' : '');
    return '$sign${price(value.abs())}';
  }

  /// Porcentaje con signo ("+4.06%"). [digits] = decimales.
  static String signedPct(num value, {int digits = 2}) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(digits)}%';
  }

  static String pct(num value, {int digits = 1}) =>
      '${value.toStringAsFixed(digits)}%';

  /// "1 posición" / "3 posiciones".
  static String plural(int count, String singular, String plural) =>
      '$count ${count == 1 ? singular : plural}';
}

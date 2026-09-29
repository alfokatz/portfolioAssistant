import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_extension.dart';

/// Colores del kit resueltos para el tema activo (claro u oscuro).
///
/// El catálogo arranca en funciones estáticas y estilos que no reciben
/// `BuildContext`, así que los tokens no pueden salir de
/// `Theme.of(context)` en cada uso. En cambio, el host de las surfaces
/// (`PortfolioQaAssistantSurface`) fija el brillo con [resolve] antes de
/// construirlas, y las fuerza a reconstruirse cuando cambia el tema. Todo lo
/// de adentro lee estos getters. Mismos nombres que `PortfolioColors`, para
/// que la migración sea mecánica. Los valores salen de `CustomColors`
/// (light/dark), la misma fuente que el resto de la app.
abstract final class QaColors {
  static CustomColors _c = CustomColors.light;
  static bool _dark = false;

  static bool get isDark => _dark;

  /// Lo llama el host de las surfaces en cada build.
  static void resolve(Brightness brightness) {
    _dark = brightness == Brightness.dark;
    _c = _dark ? CustomColors.dark : CustomColors.light;
  }

  static Color get textPrimary => _c.textPrimary;
  static Color get textSecondary => _c.textSecondary;
  static Color get accentBlue => _c.accentBlue;
  static Color get accentWarm => _c.accentWarm;
  static Color get surfaceCard => _c.surfaceCard;
  static Color get surfaceElevated => _c.surfaceElevated;
  static Color get border => _c.border;
  static Color get profit => _c.profit;
  static Color get loss => _c.loss;
  static Color get profitContainer => _c.profitContainer;
  static Color get lossContainer => _c.lossContainer;
  static Color get aiCardBorder => _c.aiCardBorder;
}

/// Tokens del kit de widgets GenUI de Porty: la escala tipográfica, los
/// colores derivados y los formatos numéricos que comparten TODAS las cards
/// del catálogo. Ningún widget del catálogo debería declarar un `TextStyle`
/// suelto — si falta un estilo, se agrega acá.
///
/// Todo número usa cifras tabulares, para que columnas y valores que se
/// actualizan (scrub del gráfico, contadores) no bailen de ancho. Son
/// getters (no `const`) porque el color depende del tema — ver [QaColors].
abstract final class QaText {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Número protagonista de una card (precio, valor del portfolio, meta).
  static TextStyle get display => TextStyle(
    color: QaColors.textPrimary,
    fontSize: 30,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.9,
    height: 1.1,
    fontFeatures: _tabular,
  );

  /// Número destacado secundario (una sola métrica grande dentro de un bloque).
  static TextStyle get displaySm => TextStyle(
    color: QaColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    height: 1.15,
    fontFeatures: _tabular,
  );

  /// Título de la card: ticker, nombre de la meta.
  static TextStyle get title => TextStyle(
    color: QaColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.25,
  );

  /// Texto de lectura dentro de una card (titulares, tesis, resúmenes).
  static TextStyle get body =>
      TextStyle(color: QaColors.textPrimary, fontSize: 14, height: 1.4);

  static TextStyle get bodyStrong => TextStyle(
    color: QaColors.textPrimary,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  /// Valor de una métrica en una grilla/fila.
  static TextStyle get value => TextStyle(
    color: QaColors.textPrimary,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.2,
    fontFeatures: _tabular,
  );

  static TextStyle get valueSm => TextStyle(
    color: QaColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    height: 1.2,
    fontFeatures: _tabular,
  );

  /// Rótulo de una métrica ("Market cap", "Próximo reporte").
  static TextStyle get label =>
      TextStyle(color: QaColors.textSecondary, fontSize: 12, height: 1.3);

  /// Encabezado de sección dentro de una card ("VALUACIÓN", "HISTORIAL").
  static TextStyle get eyebrow => TextStyle(
    color: QaColors.textSecondary,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    height: 1.2,
  );

  /// Metadatos: fuente y fecha de una noticia, notas al pie.
  static TextStyle get caption => TextStyle(
    color: QaColors.textSecondary,
    fontSize: 11,
    height: 1.3,
    fontFeatures: _tabular,
  );
}

abstract final class QaPalette {
  /// Paleta categórica para series (segmentos de barras, donuts, leyendas).
  /// Tonos editoriales cálidos que conviven con el terracota de la app — el
  /// orden importa: los primeros tienen más contraste entre sí. En oscuro el
  /// "carbón" pasa a un gris claro (si no, desaparece sobre la card).
  static const _categoricalLight = [
    Color(0xFFD98E5D), // terracota (acento)
    Color(0xFF2F3437), // carbón
    Color(0xFF7A9E7E), // salvia
    Color(0xFFC9B79C), // arena
    Color(0xFF6F8FAF), // azul polvo
    Color(0xFFA86A46), // terracota oscuro
  ];
  static const _categoricalDark = [
    Color(0xFFE3A472), // terracota (acento dark)
    Color(0xFFD6D6DA), // gris claro
    Color(0xFF8DB592), // salvia
    Color(0xFFCDBB9F), // arena
    Color(0xFF86A6C6), // azul polvo
    Color(0xFFB9805C), // terracota oscuro
  ];

  static List<Color> get categorical =>
      QaColors.isDark ? _categoricalDark : _categoricalLight;

  static Color series(int index) => categorical[index % categorical.length];

  /// Fondo tenue de superficies internas (bloques dentro de una card).
  static Color get inset =>
      QaColors.isDark ? const Color(0xFF222222) : const Color(0xFFF7F6F3);

  /// Fondo de barras/anillos (6%).
  static Color get track =>
      QaColors.isDark ? const Color(0x14FFFFFF) : const Color(0x0F000000);

  static Color get profitTint => QaColors.profit.withValues(alpha: 0.12);
  static Color get lossTint => QaColors.loss.withValues(alpha: 0.12);
  static Color get accentTint => QaColors.accentBlue.withValues(alpha: 0.14);

  static Color trend(num value) => value >= 0 ? QaColors.profit : QaColors.loss;

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

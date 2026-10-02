import 'package:intl/intl.dart';

/// Formato de números de la app: dólares como en la Home (el
/// `NumberFormat.currency` sin locale explícito, o sea `Intl.defaultLocale`)
/// y porcentajes con el mismo separador decimal.
///
/// Hoy nadie fija `Intl.defaultLocale` (easy_localization 3.0.8 no lo hace),
/// así que sale "$2,058.00" también en español. Si algún día se fija, la Home
/// y el informe cambian juntos: por eso no se pasa un locale acá.
abstract final class AppNumberFormat {
  /// El formato de dólares de la Home (hero, filas de posiciones).
  static NumberFormat currency() =>
      NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  static String money(double value) => currency().format(value);

  /// "+$8.25" / "-$8.25".
  static String signedMoney(double value) =>
      '${value < 0 ? '-' : '+'}${currency().format(value.abs())}';

  /// "+0.4%"; con [signed] en `false`, "0.4%".
  static String percent(double value, {int decimals = 1, bool signed = true}) {
    final f = NumberFormat.decimalPatternDigits(decimalDigits: decimals);
    final sign = !signed ? '' : (value < 0 ? '-' : '+');
    return '$sign${f.format(signed ? value.abs() : value)}%';
  }
}

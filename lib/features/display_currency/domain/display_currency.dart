import 'package:intl/intl.dart';

/// En qué moneda quiere ver el usuario su cartera, además de en dólares.
/// Porty valúa todo en dólares (las cotizaciones de Yahoo de lo que se
/// carga son en USD): esto es una conversión para mostrar.
enum DisplayCurrency {
  usd('USD', '\$', 2),
  uyu('UYU', '\$U ', 0),
  ars('ARS', 'AR\$ ', 0),
  brl('BRL', 'R\$ ', 2),
  mxn('MXN', 'MX\$ ', 2),
  clp('CLP', 'CLP\$ ', 0),
  cop('COP', 'COL\$ ', 0),
  pen('PEN', 'S/ ', 2),
  eur('EUR', '€', 2),
  gbp('GBP', '£', 2);

  const DisplayCurrency(this.code, this.symbol, this.decimals);

  /// ISO 4217.
  final String code;

  /// Prefijo para mostrar montos ("$U ", "R$ ").
  final String symbol;

  /// Decimales con los que se muestra (los pesos grandes, sin centavos).
  final int decimals;

  bool get isUsd => this == DisplayCurrency.usd;

  /// Cotización en Yahoo: unidades de esta moneda por dólar (`UYU=X`).
  String get yahooSymbol => '$code=X';

  /// Clave de traducción del nombre ("Peso uruguayo").
  String get labelKey => 'currency_name_$name';

  static DisplayCurrency fromCode(String? code) => DisplayCurrency.values
      .firstWhere((c) => c.code == code, orElse: () => DisplayCurrency.usd);

  NumberFormat get format =>
      NumberFormat.currency(symbol: symbol, decimalDigits: decimals);

  String money(double value) => format.format(value);

  /// "+$U 1.234" / "-$U 1.234".
  String signedMoney(double value) =>
      '${value < 0 ? '-' : '+'}${format.format(value.abs())}';
}

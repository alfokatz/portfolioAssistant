import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';

/// Montos en dólares mostrados en la moneda que eligió el usuario, con el
/// tipo de cambio de hoy. Porty valúa en dólares; esto es solo cómo se
/// muestra. Los porcentajes no cambian (todo se multiplica por lo mismo).
class DisplayMoney {
  const DisplayMoney(this.currency, this.rate);

  /// Dólares tal cual (también mientras no hay tipo de cambio).
  static const usd = DisplayMoney(DisplayCurrency.usd, 1);

  final DisplayCurrency currency;

  /// Unidades de [currency] por dólar.
  final double rate;

  bool get isUsd => currency.isUsd;

  /// "$27,499.84" / "$U 1,116,741".
  String money(double usd) => currency.money(usd * rate);

  /// "+$637.96" / "-$U 25,906".
  String signedMoney(double usd) => currency.signedMoney(usd * rate);
}

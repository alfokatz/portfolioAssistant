import 'package:intl/intl.dart';
import 'package:portfolio_assistant/features/assistant/catalog/kit/qa_tokens.dart';
import 'package:portfolio_assistant/features/display_currency/domain/display_currency.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';

/// Un monto de una meta en su moneda. En dólares, como siempre
/// ([QaFormat.money]); en otra moneda, con su símbolo y sin centavos
/// ("$U 1,000,000"): son montos de una meta, no precios.
String goalMoney(DisplayCurrency currency, num value) =>
    currency.isUsd
        ? QaFormat.money(value)
        : NumberFormat.currency(
          symbol: currency.symbol,
          decimalDigits: 0,
        ).format(value).trim();

extension GoalMoneyFormat on UserGoal {
  /// Un monto de esta meta, en su moneda.
  String money(num value) => goalMoney(currency, value);
}

extension GoalHoldingMoneyFormat on UserGoal {
  /// El valor de una inversión (en dólares, como se cotiza) en la moneda de
  /// la meta. Sin tipo de cambio todavía, en dólares: mejor un número en otra
  /// moneda que ninguno.
  String holdingMoney(num usd) =>
      currency.isUsd || fxMissing
          ? QaFormat.money(usd)
          : goalMoney(currency, usd * fxRate!);
}

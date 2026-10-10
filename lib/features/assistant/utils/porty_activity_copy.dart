import 'package:easy_localization/easy_localization.dart';
import 'package:portfolio_assistant/features/assistant/tools/market_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/alert_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/advice_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/turn_activity.dart';

/// La frase que muestra el header de Porty para una [TurnActivity]. Nunca
/// expone nombres de tools ni argumentos crudos: como mucho un ticker ya
/// validado. Varias tools en paralelo se resumen en una sola frase.
abstract final class PortyActivityCopy {
  static String describe(TurnActivity activity) => switch (activity.phase) {
    TurnPhase.idle => 'porty_status_idle'.tr(),
    TurnPhase.thinking => 'porty_status_thinking'.tr(),
    TurnPhase.composing => 'porty_status_composing'.tr(),
    TurnPhase.runningTools => _tools(activity.calls),
  };

  static String _tools(List<PendingToolCall> calls) {
    final names = {for (final call in calls) call.name};
    final tickers =
        <String>{
          for (final call in calls) ...ToolArgs.tickers(call.args, max: 6),
        }.toList();

    if (names.length == 1) return _single(names.first, tickers);
    // Distintas tools sobre la misma acción ("¿cómo viene NVDA?" → precio,
    // números, noticias): se nombra la acción. Si no, frase genérica.
    if (tickers.length == 1 && names.every(_marketTools.contains)) {
      return 'porty_status_analyzing'.tr(namedArgs: {'ticker': tickers.first});
    }
    return 'porty_status_gathering'.tr();
  }

  static String _single(String name, List<String> tickers) {
    final one = tickers.length == 1 ? {'ticker': tickers.first} : null;
    switch (name) {
      case 'get_quote':
        if (one != null) return 'porty_status_quote'.tr(namedArgs: one);
        if (tickers.length == 2) {
          return 'porty_status_quote_pair'.tr(
            namedArgs: {'first': tickers[0], 'second': tickers[1]},
          );
        }
        return 'porty_status_quote_many'.tr();
      case 'get_fundamentals':
        return one != null
            ? 'porty_status_fundamentals'.tr(namedArgs: one)
            : 'porty_status_fundamentals_many'.tr();
      case 'get_earnings':
        return one != null
            ? 'porty_status_earnings'.tr(namedArgs: one)
            : 'porty_status_earnings_many'.tr();
      case 'get_news':
        return one != null
            ? 'porty_status_news'.tr(namedArgs: one)
            : 'porty_status_news_many'.tr();
      case 'search_symbol':
        return 'porty_status_search'.tr();
      case 'get_portfolio_details':
        return 'porty_status_portfolio'.tr();
      case GetInvestCandidatesTool.toolName:
        return 'porty_status_invest'.tr();
      case GetGoalProjectionTool.toolName:
        return 'porty_status_goal_projection'.tr();
      case 'save_goal':
        return 'porty_status_save_goal'.tr();
      case GetDividendsTool.toolName:
        return one != null
            ? 'porty_status_dividends'.tr(namedArgs: one)
            : 'porty_status_dividends_many'.tr();
      case GetMonthlyBuyPlanTool.toolName:
        return 'porty_status_buy_plan'.tr();
      case ActionTools.proposeBuy:
      case ActionTools.proposeSell:
      case ActionTools.proposeDelete:
        return 'porty_status_action'.tr();
      case AlertTools.proposePriceAlert:
        return 'porty_status_alert'.tr();
      case AlertTools.listPriceAlerts:
        return 'porty_status_alerts_list'.tr();
      default:
        return 'porty_status_gathering'.tr();
    }
  }

  static const _marketTools = {
    'get_quote',
    'get_fundamentals',
    'get_earnings',
    'get_news',
    GetDividendsTool.toolName,
  };
}

import 'package:portfolio_assistant/features/assistant/utils/investor_profile_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/assistant_tool_context.dart';
import 'package:portfolio_assistant/features/assistant/tools/memory_tools.dart';
import 'package:portfolio_assistant/features/assistant/tools/tool_args.dart';
import 'package:portfolio_assistant/features/assistant/utils/portfolio_context_builder.dart';
import 'package:portfolio_assistant/features/assistant/utils/position_periods_builder.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Resumen compacto de la cartera que va en el mensaje del turno actual (no
/// es una tool): la mayoría de las preguntas son sobre la propia cartera y
/// así se responden en una sola llamada. Lo pesado (variación por período
/// de cada tenencia, detalle de cerradas) queda detrás de
/// [GetPortfolioDetailsTool].
abstract final class PortfolioBrief {
  static const label = 'PORTFOLIO_BRIEF';

  /// El perfil de inversor dentro del brief (ver
  /// [InvestorProfileContext.brief]).
  static const userProfileKey = 'user_profile';

  /// Qué pasó con las operaciones que propuso Porty (confirmadas,
  /// canceladas…): la cartera del brief ya refleja las confirmadas.
  static const actionsKey = 'actions_this_conversation';

  /// Lo que Porty sabe del usuario (ver `MemoryTools`).
  static const userMemoryKey = 'user_memory';

  /// Cuántos datos de la memoria viajan por turno (los más recientes).
  static const maxMemoriesInBrief = 30;

  static Map<String, Object?> build(AssistantToolContext ctx) {
    final map = PortfolioContextBuilder.buildMap(
      ctx.summary,
      history: ctx.history,
      closedPositions: ctx.closedPositions,
      asOf: ctx.now,
    );
    map
      ..remove('position_periods')
      ..remove('closed_positions')
      ..['closed_positions_count'] = ctx.closedPositions.length;
    final profile = InvestorProfileContext.brief(ctx.investorProfile, ctx.now);
    if (profile != null) map[userProfileKey] = profile;
    final memories = ctx.userMemories.take(maxMemoriesInBrief).toList();
    if (memories.isNotEmpty) {
      map[userMemoryKey] = [
        for (final (i, m) in memories.indexed)
          {
            'id': MemoryTools.refOf(i),
            'fact': m.content,
            'category': m.category.storageValue,
            'since': InvestorProfileContext.formatDate(m.updatedAt),
          },
      ];
    }
    if (ctx.actionsThisConversation.isNotEmpty) {
      map[actionsKey] = ctx.actionsThisConversation;
    }
    return map;
  }
}

/// Variación por período de cada tenencia y detalle de posiciones cerradas.
class GetPortfolioDetailsTool implements DataTool {
  GetPortfolioDetailsTool(this.ctx);

  final AssistantToolContext ctx;

  @override
  String get name => 'get_portfolio_details';

  @override
  String get description =>
      'Details of the user\'s OWN portfolio that are not in PORTFOLIO_BRIEF: '
      '"position_periods" = price change per period (day, week, month, '
      'quarter, year: change_pct, change_abs, price_start, price_end, '
      'has_sufficient_history, label_es) for their open positions — needed '
      'for a held ticker + explicit time window, or "which of my stocks rose '
      'most this week"; "closed_positions" = every closed trade (ticker, '
      'quantity, avg_purchase_price, close_price, cost_basis, proceeds, '
      'pnl_abs, pnl_pct, close_date). Pass tickers to limit '
      'position_periods to some holdings.';

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'include': {
        'type': 'array',
        'items': {
          'type': 'string',
          'enum': ['position_periods', 'closed_positions'],
        },
        'minItems': 1,
      },
      'tickers': {
        'type': 'array',
        'description': 'Optional: only these held tickers (position_periods).',
        'items': {'type': 'string'},
      },
    },
    'required': ['include'],
    'additionalProperties': false,
  };

  @override
  Future<Map<String, Object?>> run(Map<String, Object?> args) async {
    final include = ToolArgs.strings(args, 'include').toSet();
    if (include.isEmpty) return ToolArgs.invalid();
    final only = ToolArgs.tickers(args, max: 50).toSet();
    final result = <String, Object?>{'status': 'ok', 'as_of': ctx.asOf};

    if (include.contains('position_periods')) {
      final summary = ctx.summary;
      result['position_periods'] =
          summary == null || summary.valuations.isEmpty
              ? const <String, Object?>{}
              : await PositionPeriodsBuilder.build(
                summary: summary,
                quoteRepository: ctx.data.quoteRepository,
                onlyTickers:
                    only.isEmpty
                        ? null
                        : {
                          for (final v in summary.valuations)
                            if (only.contains(v.position.ticker.toUpperCase()))
                              v.position.ticker,
                        },
              );
    }
    if (include.contains('closed_positions')) {
      final full = PortfolioContextBuilder.buildMap(
        ctx.summary,
        closedPositions: ctx.closedPositions,
        asOf: ctx.now,
      );
      result['closed_positions'] = full['closed_positions'];
      result['closed_pnl_total_abs'] = full['closed_pnl_total_abs'];
      result['closed_pnl_total_cost_basis'] =
          full['closed_pnl_total_cost_basis'];
      result['closed_pnl_total_pct'] = full['closed_pnl_total_pct'];
    }
    return result;
  }
}

import 'dart:convert';

import 'package:portfolio_assistant/features/assistant/models/action_proposal.dart';
import 'package:portfolio_assistant/features/assistant/tools/action_tools.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';
import 'package:portfolio_assistant/features/genui_core/utils/a2ui_response_normalizer.dart';
import 'package:portfolio_assistant/features/genui_core/utils/llm_json_sanitizer.dart';

/// Rechaza una respuesta que muestra un widget de datos sin el resultado de
/// tool que lo respalda — el modelo inventando números desde su
/// entrenamiento. Pasó en evals: "Market cap de Apple" respondido con
/// QaFundamentals sin llamar get_fundamentals. Ver
/// `OpenAIGenUiService.answerCheck`.
///
/// Los widgets de la cartera propia (QaPositionsSnapshot, QaPeriodChange,
/// QaPnLBreakdown…) se alimentan de PORTFOLIO_BRIEF y no requieren tool.
abstract final class AssistantGroundingCheck {
  /// Widget → tools cuyo resultado `ok` lo respalda (cualquiera de ellas).
  static const _requires = <String, Set<String>>{
    'QaPriceChart': {'get_quote'},
    'QaTickerSnapshot': {'get_quote'},
    'QaCompareChart': {'get_quote'},
    'QaTickerMove': {'get_quote', 'get_portfolio_details'},
    'QaMetricStrip': {'get_quote', 'get_portfolio_details'},
    // El detalle por operación cerrada solo viene de la tool (el brief trae
    // totales): sin ella el modelo inventa filas ("VOO -3%" sin haberla
    // cerrado — visto en evals).
    'QaClosedPositionList': {'get_portfolio_details'},
    'QaFundamentals': {'get_fundamentals'},
    // Precio o fundamentals del ticker como mínimo (con Premium, las
    // fundamentals vienen locked y el análisis se arma con el precio).
    'QaCompanyAnalysis': {'get_quote', 'get_fundamentals'},
    'QaEarningsCalendar': {'get_earnings'},
    'QaEtfHoldings': {'get_etf_holdings'},
    'QaNewsSummary': {'get_news'},
    'QaBudgetSplit': {'get_invest_candidates'},
    'QaInvestOption': {'get_invest_candidates'},
    'QaInvestConfirm': {'get_invest_candidates'},
    'QaGoalCard': {'get_goal_projection'},
    'QaProjectionStrip': {'get_goal_projection'},
    'QaProjectionChart': {'get_goal_projection'},
    'QaMilestoneList': {'get_goal_projection'},
    'QaActionProposal': ActionTools.names,
  };

  /// Widgets cuyo `ticker` tiene que haber sido pedido a la tool.
  static const _perTicker = {
    'QaPriceChart',
    'QaTickerSnapshot',
    'QaFundamentals',
    'QaEarningsCalendar',
    'QaCompanyAnalysis',
    'QaEtfHoldings',
  };

  static String? check(String rawAnswer, List<ToolCallRecord> visibleCalls) {
    final problems = <String>[];
    for (final component in components(rawAnswer)) {
      final type = component['component'];
      final tools = _requires[type];
      if (tools == null) continue;
      final backing = visibleCalls.where(
        (c) => tools.contains(c.name) && c.status == 'ok',
      );
      final ticker = component['ticker'];
      final proposalId = component['proposalId'];
      final missing =
          type == 'QaActionProposal'
              // La propuesta exacta: un id inventado no muestra nada.
              ? !backing.any(
                (c) => c.result[ActionProposal.toolResultIdKey] == proposalId,
              )
              : _perTicker.contains(type) && ticker is String
              ? !backing.any(
                (c) => _tickersOf(c).contains(ticker.toUpperCase()),
              )
              : backing.isEmpty;
      if (missing) {
        problems.add(
          '$type${ticker is String ? ' ($ticker)' : ''} needs ${tools.join(' or ')}',
        );
      }
    }
    if (problems.isEmpty) return null;
    return 'Your answer shows data that no tool result in this conversation '
        'supports: ${problems.join('; ')}. Never use numbers from memory. '
        'Call the needed tool(s) now, then answer again with A2UI using only '
        'the tool results.';
  }

  static Set<String> _tickersOf(ToolCallRecord call) => {
    for (final t in (call.args['tickers'] as List? ?? const []))
      '$t'.toUpperCase(),
  };

  /// Componentes de los `updateComponents` de la respuesta (con o sin
  /// fences de markdown).
  static Iterable<Map<String, dynamic>> components(String raw) sync* {
    // El modelo suele mandar JSON indentado en varias líneas: el normalizer
    // re-emite cada mensaje A2UI en una sola línea.
    final normalized = A2uiResponseNormalizer.normalize(
      LlmJsonSanitizer.sanitize(raw),
      surfaceId: '_check',
    );
    for (final line in normalized.split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map) continue;
        final update = decoded['updateComponents'];
        final components = update is Map ? update['components'] : null;
        if (components is List) {
          yield* components.whereType<Map<String, dynamic>>();
        }
      } catch (_) {
        // Si no parsea, el sanitizer/normalizer se encarga después.
      }
    }
  }
}

import 'dart:convert';

import 'package:portfolio_assistant/features/assistant/data/plan/buy_plan_builder.dart';
import 'package:portfolio_assistant/features/assistant/data/plan/goal_projection_builder.dart';
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
    'QaAllocationPlan': {'get_allocation_plan'},
    'QaWatchlist': {'get_watchlist'},
    'QaWeeklyReport': {'get_weekly_report'},
    'QaNewsSummary': {'get_news'},
    'QaSourceComparison': {'compare_sources'},
    'QaBudgetSplit': {'get_invest_candidates'},
    'QaInvestOption': {'get_invest_candidates'},
    'QaInvestConfirm': {'get_invest_candidates'},
    'QaSavingsPlan': {'get_goal_projection', 'get_monthly_buy_plan'},
    'QaBuyPlan': {'get_monthly_buy_plan'},
    'QaActionProposal': ActionTools.proposalTools,
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
      final planId = component['planId'];
      final buyPlanId = component['buyPlanId'];
      final missing =
          type == 'QaActionProposal'
              // La propuesta exacta: un id inventado no muestra nada.
              ? !backing.any(
                (c) => c.result[ActionProposal.toolResultIdKey] == proposalId,
              )
              : type == 'QaBuyPlan'
              ? !backing.any(
                (c) => c.result[BuyPlanBuilder.buyPlanIdKey] == buyPlanId,
              )
              : type == 'QaSavingsPlan'
              // Ídem el plan: sin el plan_id real la card queda vacía.
              ? !backing.any(
                (c) => c.result[GoalProjectionBuilder.planIdKey] == planId,
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

  /// Tickers que [call] pidió Y devolvió con datos. Los que el plan dejó
  /// `locked` (por ticker en `get_quote`, en `locked_tickers` en los demás)
  /// no respaldan una card: una consulta mixta (uno propio, uno ajeno sin
  /// consultas gratis) vuelve `ok` y, sin esto, dejaba pasar la card del
  /// ajeno con números de memoria.
  static Set<String> _tickersOf(ToolCallRecord call) {
    final lockedTickers = {
      for (final t in (call.result['locked_tickers'] as List? ?? const []))
        '$t'.toUpperCase(),
    };
    final entries = call.result['tickers'];
    if (entries is Map) {
      for (final MapEntry(:key, :value) in entries.entries) {
        if (value is Map && value['status'] == 'locked') {
          lockedTickers.add('$key'.toUpperCase());
        }
      }
    }
    return {
      for (final t in (call.args['tickers'] as List? ?? const []))
        if (!lockedTickers.contains('$t'.toUpperCase())) '$t'.toUpperCase(),
    };
  }

  /// Tools cuyo resultado puede nombrar un medio: de ahí sale lo que la prosa
  /// puede atribuir ("según Reuters").
  static const _outletSources = {
    'get_news',
    'compare_sources',
    'get_daily_brief',
    'get_weekly_report',
    'search_web',
  };

  /// "según X" / "according to X" y "X dice" / "X says": el medio que nombra
  /// la prosa. Un nombre es una o más palabras con mayúscula inicial.
  static const _nameWord = r"[A-ZÁÉÍÓÚÑ][\p{L}\p{N}&.'’-]*";
  static final _outletByPhrase = RegExp(
    r'(?:[Ss]eg[uú]n|[Aa]ccording\s+to)\s+'
    '($_nameWord(?:\\s+$_nameWord){0,3})',
    unicode: true,
  );
  static final _outletAsSubject = RegExp(
    '($_nameWord(?:\\s+$_nameWord){0,3})\\s+'
    r'(?:dice|informa|reporta|cuenta|señala|destaca|asegura|afirma|says|'
    r'reports|reported|notes|highlights|claims)\b',
    unicode: true,
  );

  static const _articles = {'the', 'el', 'la', 'los', 'las'};

  /// Palabras con mayúscula que no son un medio ("Esto dice", "Según Porty").
  static const _notOutlets = {
    'porty', 'esto', 'eso', 'todo', 'nada', 'él', 'ella', 'ellos', 'nadie',
    'alguien', 'cada', 'uno', 'otro', 'ninguno', 'ambos', 'this', 'that',
    'it', 'he', 'she', 'they', 'each', 'one', 'both', 'nobody', 'everyone',
    'the', 'el', 'la', 'los', 'las', 'un', 'una', 'gold', 'premium', 'free',
  };

  /// Medios que la prosa de la respuesta atribuye y que ningún resultado de
  /// noticias del turno (`outlets` de `compare_sources`, `source` de
  /// `get_news`, el brief…) ni la noticia desde la que se abrió el chat
  /// ([pinnedContext]) menciona: el modelo los puso de memoria. Se mira la
  /// primera palabra del nombre ("Reuters Business" → "Reuters"), así que es
  /// laxo a propósito: solo atrapa un medio que no aparece en ningún lado.
  static List<String> unlistedOutlets(
    Iterable<Map<String, dynamic>> components,
    List<ToolCallRecord> calls, {
    String? pinnedContext,
  }) {
    final candidates = <String>[];
    for (final c in components) {
      final text = switch (c['component']) {
        'QaAnswerText' => c['text'],
        'QaTipBanner' => c['message'],
        _ => null,
      };
      if (text is! String) continue;
      for (final re in [_outletByPhrase, _outletAsSubject]) {
        for (final m in re.allMatches(text)) {
          candidates.add(m.group(1)!);
        }
      }
    }
    if (candidates.isEmpty) return const [];

    final haystack = _normalized(
      '${pinnedContext ?? ''} '
      '${jsonEncode([for (final c in calls) if (_outletSources.contains(c.name)) c.result])}',
    );
    final out = <String>[];
    for (final name in candidates) {
      final words = name.split(RegExp(r'\s+'));
      // Artículos al principio ("The Wall Street Journal").
      var i = 0;
      while (i < words.length - 1 && _articles.contains(words[i].toLowerCase())) {
        i++;
      }
      final first = words[i];
      if (_notOutlets.contains(first.toLowerCase())) continue;
      final needle = _normalized(first).trim();
      if (needle.length < 3) continue;
      if (!haystack.contains(' $needle ') && !out.contains(name)) {
        out.add(name);
      }
    }
    return out;
  }

  /// En minúsculas, sin tildes y con todo lo que no es letra o número hecho
  /// espacio (y espacios a los costados), para buscar palabras enteras.
  static String _normalized(String text) {
    const from = 'áàäâéèëêíìïîóòöôúùüûñ';
    const to = 'aaaaeeeeiiiioooouuuun';
    final lower = text.toLowerCase();
    final buffer = StringBuffer(' ');
    for (final rune in lower.runes) {
      final ch = String.fromCharCode(rune);
      final i = from.indexOf(ch);
      buffer.write(i >= 0 ? to[i] : ch);
    }
    return '${buffer.toString().replaceAll(RegExp(r'[^a-z0-9]+'), ' ')} ';
  }

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

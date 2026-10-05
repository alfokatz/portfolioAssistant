import 'dart:convert';

import 'package:portfolio_assistant/features/assistant/catalog/widgets/analysis_widgets.dart';
import 'package:portfolio_assistant/features/assistant/data/analysis/company_analysis_data.dart';
import 'package:portfolio_assistant/features/assistant/data/market/etf_holdings_data.dart';
import 'package:portfolio_assistant/features/assistant/utils/analysis_prose_check.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_grounding_check.dart';
import 'package:portfolio_assistant/features/assistant/utils/assistant_layout_guard.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';

/// Revisión de la respuesta final de Porty, en dos momentos del turno:
///
/// 1. [check] (`answerCheck` del servicio), sobre la respuesta cruda:
///    - un widget de datos sin la tool que lo respalda → corrección que
///      obliga a llamar la tool ([AssistantGroundingCheck]);
///    - texto del análisis con números que no están en las tools, o con
///      consejo de compra/venta → corrección para reescribir (sin tools);
///    El modelo tiene UNA oportunidad de corregir.
/// 2. [postProcess], sobre la respuesta ya normalizada: guard de layout y,
///    si el modelo no corrigió, se sacan las oraciones problemáticas (y las
///    de la intro que repiten números de la card). Un número inventado nunca
///    llega a la pantalla.
abstract final class AssistantAnswerReview {
  /// Widgets de texto/decoración: su texto no es "una card con números".
  static const _nonData = {'Column', 'Text', 'QaAnswerText', 'QaTipBanner'};

  static AnswerCorrection? check(String raw, TurnEvidence evidence) {
    final grounding = AssistantGroundingCheck.check(raw, evidence.calls);
    if (grounding != null) return AnswerCorrection(grounding);

    final components = AssistantGroundingCheck.components(raw).toList();
    final missing = _missingAnalysisTools(components, evidence);
    if (missing != null) return AnswerCorrection(missing);
    final skipped = _analysisNotShown(components, evidence);
    if (skipped != null) {
      return AnswerCorrection(skipped, requiresTools: false);
    }
    final problems = <String>[];
    for (final c in components) {
      if (c['component'] != 'QaCompanyAnalysis') continue;
      final data = CompanyAnalysisData.from(evidence, '${c['ticker'] ?? ''}');
      final backing = data.backingNumbers.toList();
      for (final text in _prose(c)) {
        for (final s in AnalysisProseCheck.sentences(text)) {
          problems.addAll(AnalysisProseCheck.problemsIn(s, backing));
        }
      }
    }
    // La intro que repite los números de la card NO dispara una ronda
    // extra: costaba 2-5 s en ~1 de cada 5 respuestas (medido en evals) y
    // el arreglo es mecánico — [postProcess] saca esas oraciones.
    if (problems.isEmpty) return null;
    final original = _dataTypes(components);
    return AnswerCorrection(
      'Fix your answer text (the data is fine, do not call tools): '
      '${problems.join('; ')}. Every number you write must come from a tool '
      'result of this conversation; no buy/sell advice. Answer again with '
      'the same widgets.',
      requiresTools: false,
      rejectRewrite:
          (rewritten) =>
              !_dataTypes(
                AssistantGroundingCheck.components(rewritten).toList(),
              ).containsAll(original),
    );
  }

  static String postProcess(String normalized, TurnEvidence evidence) {
    final guarded = AssistantLayoutGuard.enforce(normalized);
    return [
      for (final line in guarded.split('\n')) _sanitizeLine(line, evidence),
    ].join('\n');
  }

  static String _sanitizeLine(String line, TurnEvidence evidence) {
    if (line.trim().isEmpty) return line;
    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return line;
      message = decoded;
    } catch (_) {
      return line;
    }
    final update = message['updateComponents'];
    final list = update is Map ? update['components'] : null;
    if (list is! List) return line;
    final components = list.whereType<Map<String, dynamic>>().toList();
    var changed = false;

    for (final c in components) {
      if (c['component'] != 'QaCompanyAnalysis') continue;
      final data = CompanyAnalysisData.from(evidence, '${c['ticker'] ?? ''}');
      final backing = data.backingNumbers.toList();
      String clean(Object? v) =>
          v is String ? AnalysisProseCheck.clean(v, backing) : '';
      for (final field in const ['summary', 'newsTake']) {
        if (c[field] is String) {
          final cleaned = clean(c[field]);
          if (cleaned != c[field]) {
            c[field] = cleaned;
            changed = true;
          }
        }
      }
      final points = c['keyPoints'];
      if (points is List) {
        final kept = [
          for (final p in points)
            if (p is Map && clean(p['text']).isNotEmpty)
              {...p, 'text': clean(p['text'])},
        ];
        if (kept.length != points.length ||
            jsonEncode(kept) != jsonEncode(points)) {
          c['keyPoints'] = kept;
          changed = true;
        }
      }
      final metrics = c['metrics'];
      if (metrics is List) {
        final cleaned = [
          for (final m in metrics)
            if (m is Map) {...m, 'explanation': clean(m['explanation'])},
        ];
        if (jsonEncode(cleaned) != jsonEncode(metrics)) {
          c['metrics'] = cleaned;
          changed = true;
        }
      }
    }

    // El layout pide siempre una frase de intro; si al reescribir el modelo
    // la omitió, va una neutra (sin números) delante de la card.
    final analysis = components.where(
      (c) => c['component'] == 'QaCompanyAnalysis',
    );
    final root = components.where((c) => c['id'] == 'root').firstOrNull;
    if (analysis.isNotEmpty &&
        root != null &&
        root['children'] is List &&
        !components.any((c) => c['component'] == 'QaAnswerText')) {
      const id = 'analysisIntro';
      list.add({
        'id': id,
        'component': 'QaAnswerText',
        'text': 'Este es el análisis de ${analysis.first['ticker']}.',
      });
      root['children'] = [id, ...(root['children'] as List)];
      changed = true;
    }

    if (_withGoldTeaser(list, components, root, evidence)) {
      changed = true;
    }

    final widgetNumbers = _widgetNumbers(components, evidence);
    if (widgetNumbers != null) {
      for (final c in components) {
        if (c['component'] != 'QaAnswerText' || c['text'] is! String) continue;
        final text = c['text'] as String;
        final kept = AnalysisProseCheck.sentences(text).where(
          (s) => AnalysisProseCheck.repeatedNumbers(s, widgetNumbers) == 0,
        );
        final next =
            kept.isNotEmpty ? kept.join(' ') : _fallbackIntro(components);
        if (next != text) {
          c['text'] = next;
          changed = true;
        }
      }
    }
    return changed ? jsonEncode(message) : line;
  }

  static const _goldSources = {'get_fundamentals', 'get_earnings', 'get_news'};

  /// Si en ESTE turno una fuente de Gold vino `locked` y la respuesta quedó
  /// en solo texto, agrega un `QaGoldTeaser` después del texto: lo bloqueado
  /// se ve (y se toca para abrir el paywall) en vez de desaparecer detrás de
  /// un "no está incluido en tu plan". Uno solo por respuesta.
  static bool _withGoldTeaser(
    List list,
    List<Map<String, dynamic>> components,
    Map<String, dynamic>? root,
    TurnEvidence evidence,
  ) {
    if (root == null || root['children'] is! List) return false;
    if (components.any((c) => !_nonData.contains(c['component']))) {
      return false;
    }
    String? ticker;
    for (final call in evidence.turnCalls) {
      if (!_goldSources.contains(call.name) || call.status != 'locked')
        continue;
      final tickers = call.args['tickers'];
      if (tickers is List && tickers.isNotEmpty) {
        ticker = '${tickers.first}'.toUpperCase();
        break;
      }
    }
    if (ticker == null) return false;
    const id = 'goldTeaser';
    list.add({'id': id, 'component': 'QaGoldTeaser', 'ticker': ticker});
    final children = List.of(root['children'] as List);
    final introAt = children.indexWhere(
      (child) => components.any(
        (c) => c['id'] == child && c['component'] == 'QaAnswerText',
      ),
    );
    children.insert(introAt < 0 ? 0 : introAt + 1, id);
    root['children'] = children;
    return true;
  }

  /// Las 4 fuentes del análisis. Un resultado locked/empty/failed cuenta
  /// como consultado (la card muestra el aviso u omite la sección); lo que
  /// no se puede es armar el análisis sin haberla pedido.
  static const analysisTools = [
    'get_quote',
    'get_fundamentals',
    'get_earnings',
    'get_news',
  ];

  static Set<Object?> _dataTypes(List<Map<String, dynamic>> components) => {
    for (final c in components)
      if (!_nonData.contains(c['component'])) c['component'],
  };

  static String? _missingAnalysisTools(
    List<Map<String, dynamic>> components,
    TurnEvidence evidence,
  ) {
    for (final c in components) {
      if (c['component'] != 'QaCompanyAnalysis') continue;
      final ticker = '${c['ticker'] ?? ''}'.toUpperCase();
      final missing = [
        for (final tool in analysisTools)
          if (!evidence.calls.any(
            (call) =>
                call.name == tool &&
                (call.args['tickers'] as List? ?? const []).any(
                  (x) => '$x'.toUpperCase() == ticker,
                ),
          ))
            tool,
      ];
      if (missing.isEmpty) continue;
      return 'QaCompanyAnalysis ($ticker) needs every source: call '
          '${missing.join(', ')} for $ticker now, in ONE parallel round, then '
          'answer again with the same widget.';
    }
    return null;
  }

  /// El modelo pidió en ESTE turno las 4 fuentes del análisis para un mismo
  /// ticker (ninguna otra pregunta lo hace) pero respondió con otra card.
  /// Pasa sobre todo cuando parte viene locked (Premium): cae a un gráfico
  /// de precio. Se infiere del comportamiento, no de palabras de la pregunta.
  static String? _analysisNotShown(
    List<Map<String, dynamic>> components,
    TurnEvidence evidence,
  ) {
    if (components.any((c) => c['component'] == 'QaCompanyAnalysis')) {
      return null;
    }
    Set<String> tickersOf(String tool) => {
      for (final call in evidence.turnCalls)
        if (call.name == tool)
          for (final t in (call.args['tickers'] as List? ?? const []))
            '$t'.toUpperCase(),
    };
    final common = analysisTools
        .map(tickersOf)
        .reduce((a, b) => a.intersection(b));
    if (common.length != 1) return null;
    final ticker = common.single;
    return 'You fetched all four analysis sources for $ticker: this is '
        '[W:ANALYSIS]. Answer with QaCompanyAnalysis for $ticker (the card '
        'marks locked sources itself), not another widget.';
  }

  /// Si se sacaron todas las oraciones de la intro: una que explica qué
  /// muestra la card de abajo y cómo leerla, sin datos. Nunca un "esto es
  /// lo que encontré" vacío.
  static String _fallbackIntro(List<Map<String, dynamic>> components) {
    for (final c in components) {
      if (_nonData.contains(c['component'])) continue;
      final intro = _describe(c);
      if (intro != null) return intro;
    }
    return 'Te dejo el detalle abajo.';
  }

  static String? _describe(Map<String, dynamic> c) {
    final rawTicker = c['ticker'];
    final ticker =
        rawTicker is String && rawTicker.trim().isNotEmpty
            ? rawTicker.trim().toUpperCase()
            : null;
    final of = ticker ?? 'la acción';
    return switch (c['component']) {
      'QaCompanyAnalysis' => 'Este es el análisis de $of.',
      'QaTickerSnapshot' =>
        'Este es el precio actual de $of y cómo se movió en el día, la semana '
            'y el mes.',
      'QaTickerMove' =>
        'Así se movió el precio de $of en el período que pediste, del '
            'inicio al cierre.',
      'QaPriceChart' =>
        'Este es el gráfico de precio de $of; podés cambiar el período '
            'desde el mismo gráfico.',
      'QaCompareChart' =>
        'Este gráfico compara cuánto subió o bajó cada una desde el inicio '
            'del período, en porcentaje.',
      'QaMetricStrip' =>
        'Comparé lado a lado cómo se movió el precio de cada una en el '
            'período.',
      'QaComparisonRow' =>
        'Comparé ${c['leftTicker'] ?? 'las dos'} y '
            '${c['rightTicker'] ?? 'la otra'} lado a lado; se resalta la '
            'mayor.',
      'QaPositionsSnapshot' =>
        'Esta es la foto actual de tus posiciones: cuánto valen hoy y cuánto '
            'ganaste o perdiste desde la compra.',
      'QaPeriodChange' =>
        'Así cambió el valor de tu portfolio en el período que pediste.',
      'QaTopMovers' =>
        'Comparé tus posiciones: a la izquierda la que mejor le fue y a la '
            'derecha la que peor.',
      'QaConcentrationBar' =>
        'Esto muestra qué parte de tu portfolio ocupa cada acción, de mayor '
            'a menor.',
      'QaPnLBreakdown' =>
        'Este desglose va de lo que invertiste a lo que vale hoy, y el '
            'resultado entre ambos.',
      'QaPositionList' =>
        'Estas son tus posiciones, ordenadas por cuánto pesan en tu '
            'portfolio.',
      'QaClosedPositionList' =>
        'Estas son tus posiciones cerradas y lo que ganaste o perdiste en '
            'cada una.',
      'QaFundamentals' =>
        'Estos son los indicadores de $of que tienen que ver con tu pregunta.',
      'QaEtfHoldings' =>
        'Estas son las principales posiciones de ${ticker ?? 'el fondo'}, con '
            'cuánto pesa cada una, y cómo se reparte entre sectores.',
      'QaEarningsCalendar' =>
        'Esto resume los resultados de $of: su próximo reporte y cómo le fue '
            'frente a lo que esperaba el mercado.',
      'QaNewsSummary' =>
        'Estos son los titulares más recientes de $of, cada uno resumido en '
            'una línea.',
      'QaInvestOption' =>
        'Estas son algunas ideas para mirar, cada una con su a favor, su en '
            'contra y qué tan bien encaja con tu perfil.',
      'QaBudgetSplit' =>
        'Así se podría repartir el presupuesto entre estas acciones, a modo '
            'de ejemplo.',
      'QaInvestConfirm' =>
        'Este es el resumen de la simulación; no se hace ninguna operación '
            'real.',
      'QaGoalCard' =>
        'Esta es tu meta: cuánto querés juntar, para cuándo y cuánto llevás.',
      'QaProjectionStrip' =>
        'Esto proyecta tu meta con el ahorro mensual que venís haciendo.',
      'QaProjectionChart' =>
        'Este gráfico muestra cómo crecería tu ahorro hasta la fecha de la '
            'meta.',
      'QaMilestoneList' => 'Estos son los hitos en el camino a tu meta.',
      _ => null,
    };
  }

  static Iterable<String> _prose(Map<String, dynamic> c) sync* {
    for (final field in const ['summary', 'newsTake']) {
      if (c[field] is String) yield c[field] as String;
    }
    for (final p in (c['keyPoints'] as List? ?? const [])) {
      if (p is Map && p['text'] is String) yield p['text'] as String;
    }
    for (final m in (c['metrics'] as List? ?? const [])) {
      if (m is Map && m['explanation'] is String) {
        yield m['explanation'] as String;
      }
    }
  }

  /// Los números que muestra la card de datos de la respuesta (null si no
  /// hay card). El análisis los toma de las tools; el resto, de su JSON.
  static List<double>? _widgetNumbers(
    List<Map<String, dynamic>> components,
    TurnEvidence evidence,
  ) {
    final data = [
      for (final c in components)
        if (!_nonData.contains(c['component'])) c,
    ];
    if (data.isEmpty) return null;
    final out = <double>[];
    for (final c in data) {
      if (c['component'] == 'QaCompanyAnalysis') {
        final d = CompanyAnalysisData.from(evidence, '${c['ticker'] ?? ''}');
        out.addAll(d.backingNumbers);
        // Las métricas que la card muestra, además de todo lo de las tools.
        for (final m in AnalysisMetric.values) {
          final v = d.metric(m.key);
          if (v != null) out.add(v);
        }
      } else if (c['component'] == 'QaEtfHoldings') {
        // Como el análisis: los pesos los pone la app, no están en el JSON.
        final d = EtfHoldingsData.from(evidence, '${c['ticker'] ?? ''}');
        if (d != null) out.addAll(d.backingNumbers);
      } else {
        for (final n in AnalysisProseCheck.numbersIn(jsonEncode(c))) {
          out.add(n.value);
        }
      }
    }
    return out;
  }
}

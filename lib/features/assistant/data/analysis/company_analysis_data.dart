import 'dart:convert';

import 'package:portfolio_assistant/features/assistant/data/invest/profile_candidate_matcher.dart';
import 'package:portfolio_assistant/features/genui_core/services/openai_genui_service.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/data_tool.dart';

/// Estado de una fuente de datos del análisis para un ticker.
enum AnalysisSourceStatus {
  /// Hay datos utilizables.
  ok,

  /// El plan del usuario no la incluye (se muestra "incluido en Gold").
  locked,

  /// No se pidió, falló o vino vacía: la sección se omite sin aviso.
  missing,
}

/// Todo lo que el análisis de una empresa necesita, sacado de los
/// resultados de tools del turno ([TurnEvidence]) — nunca de lo que escribió
/// el modelo. Así cada número de la card sale de un dato real por
/// construcción; el modelo solo aporta el texto (resumen, puntos clave,
/// explicaciones), que se valida aparte (`AnalysisProseCheck`).
///
/// Si una tool se llamó varias veces en la conversación, gana la más
/// reciente con dato para el ticker.
class CompanyAnalysisData {
  CompanyAnalysisData._({
    required this.ticker,
    required this.quote,
    required this.quoteStatus,
    required this.fundamentals,
    required this.fundamentalsStatus,
    required this.earnings,
    required this.earningsStatus,
    required this.news,
    required this.newsStatus,
    required this.position,
  });

  factory CompanyAnalysisData.from(TurnEvidence evidence, String ticker) {
    final t = ticker.toUpperCase();
    Map<String, Object?>? quote;
    Map<String, Object?>? fundamentals;
    Map<String, Object?>? earnings;
    List<Map<String, Object?>>? news;
    var quoteStatus = AnalysisSourceStatus.missing;
    var fundamentalsStatus = AnalysisSourceStatus.missing;
    var earningsStatus = AnalysisSourceStatus.missing;
    var newsStatus = AnalysisSourceStatus.missing;

    bool asksFor(ToolCallRecord call) {
      final tickers = call.args['tickers'];
      return tickers is List && tickers.any((x) => '$x'.toUpperCase() == t);
    }

    for (final call in evidence.calls) {
      if (!asksFor(call)) continue;
      final result = call.result;
      final locked = call.status == 'locked';
      switch (call.name) {
        case 'get_quote':
          final entry = _map(_map(result['tickers'])?[t]);
          if (entry == null) break;
          if (entry['status'] == 'locked') {
            quoteStatus = AnalysisSourceStatus.locked;
          } else if (entry['fetch_ok'] == true) {
            quote = entry;
            quoteStatus = AnalysisSourceStatus.ok;
          }
        case 'get_fundamentals':
          if (locked) {
            fundamentalsStatus = AnalysisSourceStatus.locked;
            break;
          }
          final entry = _map(_map(result['fundamentals'])?[t]);
          if (entry != null && entry.isNotEmpty) {
            fundamentals = entry;
            fundamentalsStatus = AnalysisSourceStatus.ok;
          }
        case 'get_earnings':
          if (locked) {
            earningsStatus = AnalysisSourceStatus.locked;
            break;
          }
          final entry = _map(_map(result['earnings'])?[t]);
          if (entry != null && entry.isNotEmpty) {
            earnings = entry;
            earningsStatus = AnalysisSourceStatus.ok;
          }
        case 'get_news':
          if (locked) {
            newsStatus = AnalysisSourceStatus.locked;
            break;
          }
          final items = [
            for (final n in (result['news'] as List? ?? const []))
              if (_map(n) case final m?)
                if ('${m['ticker']}'.toUpperCase() == t) m,
          ];
          if (items.isNotEmpty) {
            news = items;
            newsStatus = AnalysisSourceStatus.ok;
          }
      }
    }

    return CompanyAnalysisData._(
      ticker: t,
      quote: quote,
      quoteStatus: quoteStatus,
      fundamentals: fundamentals,
      fundamentalsStatus: fundamentalsStatus,
      earnings: earnings,
      earningsStatus: earningsStatus,
      news: news ?? const [],
      newsStatus: newsStatus,
      position: _positionFrom(evidence.pinnedContext, t),
    );
  }

  final String ticker;
  final Map<String, Object?>? quote;
  final AnalysisSourceStatus quoteStatus;
  final Map<String, Object?>? fundamentals;
  final AnalysisSourceStatus fundamentalsStatus;
  final Map<String, Object?>? earnings;
  final AnalysisSourceStatus earningsStatus;
  final List<Map<String, Object?>> news;
  final AnalysisSourceStatus newsStatus;

  /// La posición del usuario en este ticker (de PORTFOLIO_BRIEF), si la tiene.
  final Map<String, Object?>? position;

  bool get hasAnyData =>
      quote != null ||
      fundamentals != null ||
      earnings != null ||
      news.isNotEmpty;

  String? get companyName => _str(fundamentals?['company_name']);
  String? get industry => _str(fundamentals?['industry']);
  double? get currentPrice => _num(quote?['current_price']);

  /// Variación del período más largo con historia suficiente entre mes y
  /// semana (el mes da más contexto; si no hay, la semana).
  ({double pct, String label})? get periodChange {
    final periods = _map(quote?['periods']);
    for (final key in const ['month', 'week', 'day']) {
      final p = _map(periods?[key]);
      final pct = _num(p?['change_pct']);
      if (p == null || pct == null) continue;
      if (p['has_sufficient_history'] == false) continue;
      return (pct: pct, label: _str(p['label_es']) ?? '');
    }
    return null;
  }

  double? get week52High => _num(fundamentals?['week_52_high']);
  double? get week52Low => _num(fundamentals?['week_52_low']);
  double? get beta => _num(fundamentals?['beta']);

  /// Mismo cálculo que los candidatos de inversión.
  String? get riskLevel => ProfileCandidateMatcher.riskLevelForBeta(beta);

  Map<String, Object?>? get nextReport => _map(earnings?['next_report']);
  Map<String, Object?>? get latestResult => _map(earnings?['latest_result']);

  double? metric(String key) => _num(fundamentals?[key]);

  /// Todos los números que respaldan este análisis: los de cada resultado
  /// de tool del ticker y los de su posición. Lo usa el chequeo de números
  /// del texto del modelo.
  Iterable<double> get backingNumbers sync* {
    for (final source in [quote, fundamentals, earnings, position]) {
      if (source != null) yield* _numbersIn(source);
    }
    for (final n in news) {
      yield* _numbersIn(n);
    }
  }

  static Iterable<double> _numbersIn(Object? value) sync* {
    if (value is num) {
      yield value.toDouble();
    } else if (value is String) {
      // Fechas ISO ("2026-10-20") y rótulos ("T3 FY26", "20 oct 2026"): el
      // modelo puede nombrar el día, el año o el trimestre.
      for (final m in RegExp(r'\d+(?:[.,]\d+)?').allMatches(value)) {
        final parsed = double.tryParse(m.group(0)!.replaceAll(',', '.'));
        if (parsed != null) yield parsed;
      }
    } else if (value is Map) {
      for (final v in value.values) {
        yield* _numbersIn(v);
      }
    } else if (value is List) {
      for (final v in value) {
        yield* _numbersIn(v);
      }
    }
  }

  static Map<String, Object?>? _positionFrom(String? pinned, String ticker) {
    if (pinned == null) return null;
    final start = pinned.indexOf('{');
    if (start < 0) return null;
    try {
      final brief = jsonDecode(pinned.substring(start));
      final positions = brief is Map ? brief['positions'] : null;
      if (positions is! List) return null;
      for (final p in positions) {
        if (p is Map && '${p['ticker']}'.toUpperCase() == ticker) {
          return p.cast<String, Object?>();
        }
      }
    } catch (_) {}
    return null;
  }

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : null;

  static double? _num(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _str(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

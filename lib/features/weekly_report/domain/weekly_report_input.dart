import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_relevance.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';

/// Un titular de la semana sobre una acción de la cartera. El LLM lo elige
/// por [id]; medio, fecha y link los muestra la app tal cual.
class WeeklyNewsItem {
  const WeeklyNewsItem({
    required this.id,
    required this.ticker,
    required this.headline,
    required this.source,
    required this.url,
    required this.publishedAt,
  });

  /// `n1`, `n2`… en orden de importancia.
  final String id;
  final String ticker;
  final String headline;
  final String source;
  final String url;
  final DateTime publishedAt;
}

/// Un reporte de resultados en la semana siguiente.
class UpcomingEarnings {
  const UpcomingEarnings({
    required this.ticker,
    required this.date,
    this.timingLabel,
    this.epsEstimate,
  });

  final String ticker;
  final DateTime date;

  /// "Antes de la apertura", "Después del cierre"…
  final String? timingLabel;

  /// Ganancia por acción que espera el mercado (Finnhub).
  final double? epsEstimate;
}

/// Cómo le fue a la cartera contra el S&P 500, en palabras. Lo decide la
/// app: el modelo nunca compara números.
enum MarketComparison { better, slightlyBetter, similar, slightlyWorse, worse }

/// Todo lo que entra al informe de una semana, ya calculado. Lo único que
/// el LLM agrega es prosa que referencia estos datos.
class WeeklyReportInput {
  const WeeklyReportInput({
    required this.numbers,
    required this.news,
    required this.upcomingEarnings,
    required this.newsFailed,
    required this.earningsFailed,
    this.investors = const [],
    this.investorsFailed = false,
  });

  final WeeklyPortfolioNumbers numbers;
  final List<WeeklyNewsItem> news;
  final List<UpcomingEarnings> upcomingEarnings;

  /// La fuente falló (distinto de "no hubo noticias").
  final bool newsFailed;
  final bool earningsFailed;

  /// Super investors ya filtrados para el informe
  /// ([InvestorPulseRelevance.selectForReport]): vacío = no hay sección.
  final List<RelatedPulseItem> investors;
  final bool investorsFailed;

  /// Filas de "Qué movió tu cartera" como mucho.
  static const maxRows = 5;

  /// Debajo de este movimiento semanal (en %), una posición "casi no se
  /// movió": va agrupada en una línea y no necesita un "por qué".
  static const smallMovePct = 0.5;

  /// "Por qué" como mucho (las de más impacto).
  static const maxWhy = 3;

  /// Menos que esto contra el S&P 500 (en puntos porcentuales) es "casi
  /// igual que el mercado".
  static const similarMarketPp = 0.5;

  /// Desde esto es "mejor/peor" a secas, no "un poco".
  static const clearMarketPp = 2.0;

  /// Movimiento de una posición en la semana: el del precio si se conoce;
  /// si no, el de la posición del usuario.
  static double moveOf(WeeklyPositionMove p) => p.pricePct ?? p.positionPct;

  /// Las posiciones que van como fila: las de más impacto que se movieron
  /// al menos [smallMovePct]. Con una sola posición, esa siempre.
  List<WeeklyPositionMove> get rows {
    final positions = numbers.positions;
    if (positions.length == 1) return positions;
    return [
      for (final p in positions)
        if (moveOf(p).abs() >= smallMovePct && p.contributionPp != 0) p,
    ].take(maxRows).toList();
  }

  /// Las que no entraron como fila (se resumen en una línea).
  int get othersCount => numbers.positions.length - rows.length;

  /// Si todas las que quedaron afuera se movieron menos de [smallMovePct].
  bool get othersAllSmall {
    final shown = {for (final r in rows) r.ticker};
    return numbers.positions
        .where((p) => !shown.contains(p.ticker))
        .every((p) => moveOf(p).abs() < smallMovePct);
  }

  /// A cuáles Porty les escribe un "por qué".
  List<String> get explainTickers =>
      [
        for (final r in rows)
          if (moveOf(r).abs() >= smallMovePct) r.ticker,
      ].take(maxWhy).toList();

  MarketComparison? get marketComparison {
    final diff = numbers.vsSp500Pp;
    if (diff == null) return null;
    if (diff.abs() < similarMarketPp) return MarketComparison.similar;
    if (diff >= clearMarketPp) return MarketComparison.better;
    if (diff > 0) return MarketComparison.slightlyBetter;
    if (diff <= -clearMarketPp) return MarketComparison.worse;
    return MarketComparison.slightlyWorse;
  }

  /// La concentración merece un comentario: cartera de 4 o más posiciones
  /// con una que pesa un cuarto o más, o una que ganó 5 puntos de peso en 4
  /// semanas.
  bool get isConcentrationNotable {
    final c = numbers.concentration;
    if (c == null) return false;
    final before = c.weightFourWeeksAgo;
    final grew = before != null && c.weightNow - before >= 0.05;
    return grew || (numbers.positions.length >= 4 && c.weightNow >= 0.25);
  }

  /// El tema de "Para aprender", elegido por lo que pasó en la semana del
  /// usuario (el modelo solo lo redacta). `null` = esta semana no hay un
  /// tema que salga de sus datos: la sección no aparece (mejor nada que un
  /// concepto genérico).
  String? get learnTopic {
    final comparison = marketComparison;
    return [
      if (upcomingEarnings.isNotEmpty) 'earnings',
      if (comparison == MarketComparison.worse ||
          comparison == MarketComparison.slightlyWorse)
        'sp500_comparison',
      if (numbers.newMoney > 0) 'new_money',
      if (isConcentrationNotable) 'concentration',
      if (investors.any(
        (r) => r.item.isFiling && r.item.action != 'quarterly_portfolio',
      ))
        'sec_filing',
      if (numbers.tradingDays > 0 && numbers.tradingDays < 5) 'short_week',
    ].firstOrNull;
  }

  /// Datos para el LLM: categorías y textos, sin cifras. La prosa del
  /// informe no lleva números (los pone la app), así que tampoco se le dan:
  /// lo que no está, no se puede copiar mal.
  Map<String, Object?> toPromptJson() {
    final n = numbers;
    final rows = this.rows;
    final explain = explainTickers.toSet();
    final mostUp = rows.where((r) => r.contributionPp > 0).firstOrNull;
    final mostDown = rows.where((r) => r.contributionPp < 0).firstOrNull;
    final comparison = marketComparison;
    return {
      'portfolio': {
        'direction': _direction(n.changePct),
        if (comparison != null) 'vs_market': _comparisonKey(comparison),
        if (n.sp500Pct != null) 'market_direction': _direction(n.sp500Pct!),
        if (n.newMoney > 0) 'added_money_this_week': true,
        if (n.tradingDays > 0 && n.tradingDays < 5) 'short_week': true,
      },
      'positions': [
        for (final r in rows)
          {
            'ticker': r.ticker,
            'direction': _direction(moveOf(r)),
            if (numbers.sp500Pct != null)
              'vs_market': _positionVsMarket(moveOf(r), numbers.sp500Pct!),
            if (rows.length > 1 && identical(r, mostUp)) 'role': 'added_most',
            if (rows.length > 1 && identical(r, mostDown))
              'role': 'subtracted_most',
            'needs_why': explain.contains(r.ticker),
            if (r.boughtThisWeek) 'bought_this_week': true,
          },
      ],
      if (othersCount > 0)
        'other_positions': othersAllSmall ? 'barely_moved' : 'smaller_impact',
      'news': [
        for (final item in news)
          {
            'id': item.id,
            'ticker': item.ticker,
            'headline': item.headline,
            'source': item.source,
          },
      ],
      'investors': [for (final r in investors) _investorJson(r)],
      'upcoming_earnings': [
        for (final e in upcomingEarnings)
          {
            'ticker': e.ticker,
            if (e.timingLabel != null) 'timing': e.timingLabel,
          },
      ],
      'learn_topic': learnTopic,
    };
  }

  static String _comparisonKey(MarketComparison c) => switch (c) {
    MarketComparison.better => 'better',
    MarketComparison.slightlyBetter => 'slightly_better',
    MarketComparison.similar => 'similar',
    MarketComparison.slightlyWorse => 'slightly_worse',
    MarketComparison.worse => 'worse',
  };

  /// Cómo se movió una posición respecto del S&P 500, en palabras: para que
  /// "se movió junto con el mercado" no se diga de una que subió el triple.
  static String _positionVsMarket(double move, double market) {
    final mine = _direction(move);
    final theirs = _direction(market);
    if (mine == 'flat' && theirs == 'flat') return 'with_market';
    if (mine != theirs) return 'against_market';
    final diff = move.abs() - market.abs();
    if (diff >= clearMarketPp) return 'more_than_market';
    if (diff <= -clearMarketPp) return 'less_than_market';
    return 'with_market';
  }

  static String _direction(double pct) =>
      pct > 0.15
          ? 'up'
          : pct < -0.15
          ? 'down'
          : 'flat';

  static Map<String, Object?> _investorJson(RelatedPulseItem r) {
    final i = r.item;
    return {
      'id': i.id,
      'who': i.investorName,
      if (i.organization != null) 'organization': i.organization,
      if (i.isFiling) ...{
        'kind': 'sec_filing',
        'action': i.action,
        if (i.issuerName != null) 'company': i.issuerName,
        if (i.issuerTicker != null) 'company_ticker': i.issuerTicker,
      } else ...{
        'kind': 'news_headline',
        'headline': i.headline,
        if (i.source != null) 'source': i.source,
      },
      // Explícito: "no la tiene" se respeta mejor que la ausencia del campo.
      'user_holds': r.relatedTickers.isNotEmpty,
      if (r.relatedTickers.isNotEmpty) 'related_holdings': r.relatedTickers,
    };
  }
}

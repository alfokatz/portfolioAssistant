import 'package:portfolio_assistant/features/weekly_report/domain/investor_pulse_relevance.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';

/// Un titular de la semana sobre una acción de la cartera. El LLM lo elige
/// por [id]; título, medio, fecha y link los muestra la app tal cual.
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
  });

  final String ticker;
  final DateTime date;

  /// "Antes de la apertura", "Después del cierre"…
  final String? timingLabel;
}

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

  /// La fuente falló (distinto de "no hubo noticias"): la UI puede ofrecer
  /// reintentar en vez de decir que no pasó nada.
  final bool newsFailed;
  final bool earningsFailed;

  /// Super investors y voces del mercado, ya ordenados (lo que toca la
  /// cartera primero) y acotados.
  final List<RelatedPulseItem> investors;
  final bool investorsFailed;

  /// Cuántas posiciones van al prompt como máximo (las de más impacto). El
  /// resto no cambia la historia de la semana y solo suma tokens.
  static const maxPromptPositions = 15;

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

  /// El tema de "para aprender" de esta semana. Lo elige la app (el modelo
  /// solo lo redacta): primero lo específico de la semana; si no hay nada,
  /// rota por semana entre los temas generales para no repetir siempre el
  /// mismo.
  String get learnTopic {
    final specific = [
      if (upcomingEarnings.isNotEmpty) 'earnings',
      if (investors.any(
        (r) => r.item.isFiling && r.item.action != 'quarterly_portfolio',
      ))
        'sec_filing',
      if (investors.any((r) => r.item.action == 'quarterly_portfolio'))
        'quarterly_portfolio',
      if (numbers.newMoney > 0) 'new_money',
      if (numbers.tradingDays > 0 && numbers.tradingDays < 5) 'short_week',
      if (isConcentrationNotable) 'concentration',
    ];
    if (specific.isNotEmpty) return specific.first;
    final general = [
      if (numbers.sp500Pct != null) 'sp500_comparison',
      'contribution',
      if (news.isNotEmpty) 'reading_news',
    ];
    final weekIndex =
        numbers.week.monday.toUtc().millisecondsSinceEpoch ~/
        const Duration(days: 7).inMilliseconds;
    return general[weekIndex % general.length];
  }

  /// Datos para el LLM: cifras ya redondeadas como las va a mostrar la app,
  /// para que si alguna aparece en la prosa coincida con la pantalla.
  Map<String, Object?> toPromptJson() {
    final n = numbers;
    return {
      'week': {
        'from': _ymd(n.week.monday),
        'to': _ymd(n.week.friday),
        'trading_days': n.tradingDays,
      },
      'portfolio': {
        'change_pct': _pct(n.changePct),
        'change_abs': _money(n.changeAbs),
        'value_end': _money(n.valueEnd),
        if (n.newMoney > 0) 'new_money': _money(n.newMoney),
        if (n.sp500Pct != null) 'sp500_pct': _pct(n.sp500Pct!),
        if (n.vsSp500Pp != null) 'vs_sp500_pp': _pct(n.vsSp500Pp!),
      },
      'positions': [
        for (final p in n.positions.take(maxPromptPositions))
          {
            'ticker': p.ticker,
            'weight_pct': _pct(p.weightEnd * 100),
            'contribution_pp': _pct(p.contributionPp),
            if (p.pricePct != null) 'price_pct': _pct(p.pricePct!),
            if (p.boughtThisWeek) 'bought_this_week': true,
          },
      ],
      // Solo si es notable (lo decide la app): con 2 o 3 posiciones siempre
      // hay una que pesa más de un cuarto y no es noticia.
      if (n.concentration != null && isConcentrationNotable)
        'concentration': {
          'ticker': n.concentration!.ticker,
          'weight_pct': _pct(n.concentration!.weightNow * 100),
          if (n.concentration!.weightFourWeeksAgo != null)
            'weight_pct_4_weeks_ago': _pct(
              n.concentration!.weightFourWeeksAgo! * 100,
            ),
        },
      if (n.closedThisWeek.isNotEmpty)
        'closed_this_week': [
          for (final c in n.closedThisWeek)
            {'ticker': c.ticker, 'pnl_pct': _pct(c.pnlPercent)},
        ],
      'news': [
        for (final item in news)
          {
            'id': item.id,
            'ticker': item.ticker,
            'headline': item.headline,
            'source': item.source,
            'date': _ymd(item.publishedAt.toLocal()),
          },
      ],
      'investors': [for (final r in investors) _investorJson(r)],
      'learn_topic': learnTopic,
      'upcoming_earnings': [
        for (final e in upcomingEarnings)
          {
            'ticker': e.ticker,
            'date': _ymd(e.date),
            if (e.timingLabel != null) 'timing': e.timingLabel,
          },
      ],
    };
  }

  static Map<String, Object?> _investorJson(RelatedPulseItem r) {
    final i = r.item;
    return {
      'id': i.id,
      'who': i.investorName,
      if (i.organization != null) 'organization': i.organization,
      'voice': i.isMarketVoice ? 'market_voice' : 'investor',
      'date': _ymd(i.date),
      if (i.isFiling) ...{
        'kind': 'sec_filing',
        'form': i.form,
        'action': i.action,
        if (i.issuerName != null) 'issuer': i.issuerName,
        if (i.issuerTicker != null) 'issuer_ticker': i.issuerTicker,
        if (i.shares != null) 'shares': i.shares!.round(),
        if (i.period != null) 'period_end': _ymd(i.period!),
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

  static double _pct(double v) => double.parse(v.toStringAsFixed(2));
  static double _money(double v) => double.parse(v.toStringAsFixed(2));
  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

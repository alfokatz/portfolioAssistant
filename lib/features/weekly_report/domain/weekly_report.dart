import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_portfolio_numbers.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';

/// Qué versión del informe se muestra.
enum WeeklyReportVariant {
  /// Con el texto de Porty (Gold, o la degustación de Free/Premium).
  full,

  /// Solo números: sin Gold y con la degustación ya usada. La pantalla
  /// muestra el teaser de Gold.
  numbersLocked,

  /// Solo números porque la generación falló (sin teaser: ya tiene acceso).
  numbersUnavailable,
}

/// El papel de una posición en la semana (etiqueta de la fila).
enum MoverRole { addedMost, subtractedMost }

/// El informe listo para mostrar: los datos de la semana con la prosa de
/// Porty pegada a cada uno. Es también lo que se guarda en
/// `weekly_reports.payload`: otro dispositivo lo muestra igual sin
/// recalcular ni volver a llamar al LLM.
class WeeklyReport {
  const WeeklyReport({
    required this.week,
    required this.variant,
    required this.courtesy,
    required this.changePct,
    required this.changeAbs,
    required this.valueEnd,
    required this.newMoney,
    required this.tradingDays,
    required this.daily,
    required this.movers,
    required this.othersCount,
    required this.othersAllSmall,
    required this.news,
    required this.investors,
    required this.upcomingEarnings,
    this.sp500Pct,
    this.comparison,
    this.reading,
    this.learn,
  });

  /// v2 (2026-10-03): estructura de 3 preguntas (cómo, por qué, qué viene).
  /// Un payload v1 no se lee: se recalculan los números.
  static const schemaVersion = 2;

  final ReportWeek week;
  final WeeklyReportVariant variant;
  final bool courtesy;

  final double changePct;
  final double changeAbs;

  /// Al cierre del viernes (puede diferir del total de la Home, que es al
  /// precio actual).
  final double valueEnd;
  final double newMoney;
  final int tradingDays;
  final double? sp500Pct;
  final MarketComparison? comparison;

  /// Para el gráfico: viernes anterior (0 %) + cada rueda.
  final List<WeeklyDayPoint> daily;

  final List<ReportMover> movers;

  /// Posiciones que no entraron como fila, y si todas se movieron poco.
  final int othersCount;
  final bool othersAllSmall;

  final List<ReportNews> news;
  final List<ReportInvestor> investors;
  final List<ReportEarnings> upcomingEarnings;

  final String? reading;
  final ReportLearn? learn;

  bool get hasProse => variant == WeeklyReportVariant.full;

  /// Junta los datos con la prosa validada.
  factory WeeklyReport.compose({
    required WeeklyReportInput input,
    required WeeklyReportDraft draft,
    required WeeklyReportVariant variant,
    bool courtesy = false,
  }) {
    final n = input.numbers;
    final whyByTicker = {for (final m in draft.movers) m.ticker: m};
    final newsById = {for (final item in input.news) item.id: item};
    final investorsById = {for (final r in input.investors) r.item.id: r};
    // La variante bloqueada nunca lleva datos de Gold (earnings, noticias,
    // inversores), aunque el input los traiga.
    final goldData = variant != WeeklyReportVariant.numbersLocked;
    final rows = input.rows;
    final mostUp = rows.where((r) => r.contributionPp > 0).firstOrNull;
    final mostDown = rows.where((r) => r.contributionPp < 0).firstOrNull;

    ReportNews? newsFor(String? id, {String? title}) {
      final item = id == null ? null : newsById[id];
      if (item == null) return null;
      return ReportNews(
        ticker: item.ticker,
        title: title ?? item.headline,
        source: item.source,
        url: item.url,
        date: item.publishedAt.toLocal(),
      );
    }

    return WeeklyReport(
      week: n.week,
      variant: variant,
      courtesy: courtesy,
      changePct: n.changePct,
      changeAbs: n.changeAbs,
      valueEnd: n.valueEnd,
      newMoney: n.newMoney,
      tradingDays: n.tradingDays,
      sp500Pct: n.sp500Pct,
      comparison: input.marketComparison,
      daily: n.daily,
      movers: [
        for (final p in rows)
          ReportMover(
            ticker: p.ticker,
            movePct: WeeklyReportInput.moveOf(p),
            contributionPp: p.contributionPp,
            boughtThisWeek: p.boughtThisWeek,
            role:
                rows.length < 2
                    ? null
                    : identical(p, mostUp)
                    ? MoverRole.addedMost
                    : identical(p, mostDown)
                    ? MoverRole.subtractedMost
                    : null,
            why: whyByTicker[p.ticker]?.why,
            source: newsFor(whyByTicker[p.ticker]?.newsId),
          ),
      ],
      othersCount: input.othersCount,
      othersAllSmall: input.othersAllSmall,
      news: [
        if (goldData)
          for (final h in draft.headlines)
            if (newsFor(h.newsId, title: h.title) case final item?) item,
      ],
      investors: [
        if (goldData)
          for (final d in draft.investors)
            if (investorsById[d.itemId] case final r?)
              ReportInvestor(
                who: r.item.investorName,
                organization: r.item.organization,
                isFiling: r.item.isFiling,
                form: r.item.form,
                source: r.item.isFiling ? 'SEC' : r.item.source,
                url: r.item.url,
                date: r.item.date,
                relatedTickers: r.relatedTickers,
                take: d.take,
              ),
      ],
      upcomingEarnings: [
        if (goldData)
          for (final e in input.upcomingEarnings)
            ReportEarnings(
              ticker: e.ticker,
              date: e.date,
              timingLabel: e.timingLabel,
              epsEstimate: e.epsEstimate,
            ),
      ],
      reading: draft.reading,
      learn:
          draft.learn == null
              ? null
              : ReportLearn(
                concept: draft.learn!.concept,
                text: draft.learn!.text,
              ),
    );
  }

  Map<String, Object?> toJson() => {
    'v': schemaVersion,
    'week': week.key,
    'variant': variant.name,
    'courtesy': courtesy,
    'change_pct': changePct,
    'change_abs': changeAbs,
    'value_end': valueEnd,
    'new_money': newMoney,
    'trading_days': tradingDays,
    'sp500_pct': sp500Pct,
    'comparison': comparison?.name,
    'daily': [
      for (final p in daily)
        {'day': _ymd(p.day), 'p': p.portfolioPct, 's': p.sp500Pct},
    ],
    'movers': [for (final m in movers) m.toJson()],
    'others_count': othersCount,
    'others_all_small': othersAllSmall,
    'news': [for (final n in news) n.toJson()],
    'investors': [for (final i in investors) i.toJson()],
    'upcoming_earnings': [for (final e in upcomingEarnings) e.toJson()],
    'reading': reading,
    'learn': learn?.toJson(),
  };

  /// `null` si el payload es de otra versión o está roto: la app recalcula
  /// los números en vez de mostrar algo a medias.
  static WeeklyReport? tryParse(Map<String, Object?> j) {
    try {
      if (j['v'] != schemaVersion) return null;
      final week = DateTime.tryParse('${j['week']}');
      if (week == null || week.weekday != DateTime.monday) return null;
      List<Map<String, Object?>> list(String key) => [
        for (final e in (j[key] as List?) ?? const [])
          if (e is Map) e.cast<String, Object?>(),
      ];
      final learn = j['learn'];
      return WeeklyReport(
        week: ReportWeek.ofMonday(week),
        variant: WeeklyReportVariant.values.firstWhere(
          (v) => v.name == j['variant'],
          orElse: () => WeeklyReportVariant.numbersUnavailable,
        ),
        courtesy: j['courtesy'] == true,
        changePct: _num(j['change_pct'])!,
        changeAbs: _num(j['change_abs'])!,
        valueEnd: _num(j['value_end'])!,
        newMoney: _num(j['new_money']) ?? 0,
        tradingDays: _num(j['trading_days'])?.toInt() ?? 5,
        sp500Pct: _num(j['sp500_pct']),
        comparison:
            MarketComparison.values
                .where((c) => c.name == j['comparison'])
                .firstOrNull,
        daily: [
          for (final p in list('daily'))
            WeeklyDayPoint(
              day: _date(p['day']),
              portfolioPct: _num(p['p'])!,
              sp500Pct: _num(p['s']),
            ),
        ],
        movers: list('movers').map(ReportMover.fromJson).toList(),
        othersCount: _num(j['others_count'])?.toInt() ?? 0,
        othersAllSmall: j['others_all_small'] != false,
        news: list('news').map(ReportNews.fromJson).toList(),
        investors: list('investors').map(ReportInvestor.fromJson).toList(),
        upcomingEarnings:
            list('upcoming_earnings').map(ReportEarnings.fromJson).toList(),
        reading: j['reading'] as String?,
        learn:
            learn is Map
                ? ReportLearn(
                  concept: learn['concept'] as String,
                  text: learn['text'] as String,
                )
                : null,
      );
    } catch (_) {
      return null;
    }
  }
}

double? _num(Object? v) => (v as num?)?.toDouble();

DateTime _date(Object? v) {
  final d = DateTime.parse('$v');
  return DateTime(d.year, d.month, d.day);
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

class ReportMover {
  const ReportMover({
    required this.ticker,
    required this.movePct,
    required this.contributionPp,
    required this.boughtThisWeek,
    this.role,
    this.why,
    this.source,
  });

  final String ticker;

  /// Movimiento semanal de la acción.
  final double movePct;

  /// Cuánto empujó (o frenó) a la cartera: lo dibuja la barra, no se
  /// muestra como número.
  final double contributionPp;
  final bool boughtThisWeek;
  final MoverRole? role;
  final String? why;

  /// La noticia en la que se apoya el "por qué".
  final ReportNews? source;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'move_pct': movePct,
    'contribution_pp': contributionPp,
    'bought_this_week': boughtThisWeek,
    'role': role?.name,
    'why': why,
    'source': source?.toJson(),
  };

  static ReportMover fromJson(Map<String, Object?> j) => ReportMover(
    ticker: j['ticker'] as String,
    movePct: _num(j['move_pct'])!,
    contributionPp: _num(j['contribution_pp'])!,
    boughtThisWeek: j['bought_this_week'] == true,
    role: MoverRole.values.where((r) => r.name == j['role']).firstOrNull,
    why: j['why'] as String?,
    source:
        j['source'] is Map
            ? ReportNews.fromJson((j['source'] as Map).cast<String, Object?>())
            : null,
  );
}

class ReportNews {
  const ReportNews({
    required this.ticker,
    required this.title,
    required this.source,
    required this.url,
    required this.date,
  });

  final String ticker;

  /// En "Noticias de la semana", el titular en español de Porty; como
  /// fuente de un "por qué", el original.
  final String title;
  final String source;
  final String url;
  final DateTime date;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'title': title,
    'source': source,
    'url': url,
    'date': _ymd(date),
  };

  static ReportNews fromJson(Map<String, Object?> j) => ReportNews(
    ticker: j['ticker'] as String,
    title: j['title'] as String,
    source: j['source'] as String,
    url: j['url'] as String,
    date: _date(j['date']),
  );
}

class ReportInvestor {
  const ReportInvestor({
    required this.who,
    required this.isFiling,
    required this.url,
    required this.date,
    required this.relatedTickers,
    required this.take,
    this.organization,
    this.form,
    this.source,
  });

  final String who;
  final String? organization;
  final bool isFiling;
  final String? form;
  final String? source;
  final String url;
  final DateTime date;
  final List<String> relatedTickers;
  final String take;

  Map<String, Object?> toJson() => {
    'who': who,
    'organization': organization,
    'filing': isFiling,
    'form': form,
    'source': source,
    'url': url,
    'date': _ymd(date),
    'related': relatedTickers,
    'take': take,
  };

  static ReportInvestor fromJson(Map<String, Object?> j) => ReportInvestor(
    who: j['who'] as String,
    organization: j['organization'] as String?,
    isFiling: j['filing'] == true,
    form: j['form'] as String?,
    source: j['source'] as String?,
    url: j['url'] as String,
    date: _date(j['date']),
    relatedTickers: [for (final t in (j['related'] as List?) ?? const []) '$t'],
    take: j['take'] as String,
  );
}

class ReportEarnings {
  const ReportEarnings({
    required this.ticker,
    required this.date,
    this.timingLabel,
    this.epsEstimate,
  });

  final String ticker;
  final DateTime date;
  final String? timingLabel;
  final double? epsEstimate;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'date': _ymd(date),
    'timing': timingLabel,
    'eps': epsEstimate,
  };

  static ReportEarnings fromJson(Map<String, Object?> j) => ReportEarnings(
    ticker: j['ticker'] as String,
    date: _date(j['date']),
    timingLabel: j['timing'] as String?,
    epsEstimate: _num(j['eps']),
  );
}

class ReportLearn {
  const ReportLearn({required this.concept, required this.text});
  final String concept;
  final String text;

  Map<String, Object?> toJson() => {'concept': concept, 'text': text};
}

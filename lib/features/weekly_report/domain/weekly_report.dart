import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
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

/// El informe listo para mostrar: los datos de la semana con la prosa de
/// Porty ya pegada a cada uno. Es también lo que se guarda en
/// `weekly_reports.payload`, así otro dispositivo lo muestra igual sin
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
    required this.movers,
    required this.news,
    required this.investors,
    required this.upcomingEarnings,
    this.sp500Pct,
    this.concentration,
    this.headline,
    this.learn,
    this.followUpQuestion,
    this.closing,
  });

  static const schemaVersion = 1;

  /// Cuántos movers muestra el informe (los de más impacto).
  static const maxMovers = 3;

  final ReportWeek week;
  final WeeklyReportVariant variant;
  final bool courtesy;

  final double changePct;
  final double changeAbs;
  final double valueEnd;
  final double newMoney;
  final int tradingDays;
  final double? sp500Pct;

  final List<ReportMover> movers;
  final ReportConcentration? concentration;
  final List<ReportNews> news;
  final List<ReportInvestor> investors;
  final List<ReportEarnings> upcomingEarnings;

  final String? headline;
  final ReportLearn? learn;
  final String? followUpQuestion;
  final String? closing;

  double? get vsSp500Pp => sp500Pct == null ? null : changePct - sp500Pct!;
  bool get hasProse => variant == WeeklyReportVariant.full;

  /// Junta los datos con la prosa validada. Solo entra lo que Porty eligió
  /// (noticias, inversores); los movers van siempre (los números son de la
  /// app), con su "por qué" si lo hay.
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
    final c = n.concentration;
    // La variante bloqueada nunca lleva datos de Gold (earnings, noticias,
    // inversores), aunque el input los traiga.
    final goldData = variant != WeeklyReportVariant.numbersLocked;

    ReportNews? newsFor(String? id) {
      final item = id == null ? null : newsById[id];
      if (item == null) return null;
      return ReportNews(
        ticker: item.ticker,
        headline: item.headline,
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
      movers: [
        for (final p in n.positions
            .where((p) => p.contributionPp != 0)
            .take(maxMovers))
          ReportMover(
            ticker: p.ticker,
            pricePct: p.pricePct,
            contributionPp: p.contributionPp,
            boughtThisWeek: p.boughtThisWeek,
            why: whyByTicker[p.ticker]?.why,
            news: newsFor(whyByTicker[p.ticker]?.newsId),
          ),
      ],
      concentration:
          c != null && input.isConcentrationNotable
              ? ReportConcentration(
                ticker: c.ticker,
                weightNow: c.weightNow,
                weightFourWeeksAgo: c.weightFourWeeksAgo,
              )
              : null,
      news: [
        if (goldData)
          for (final d in draft.news)
            if (newsFor(d.newsId) case final item?) item.withTake(d.take),
      ],
      investors: [
        if (goldData)
          for (final d in draft.investors)
            if (investorsById[d.itemId] case final r?)
              ReportInvestor(
                who: r.item.investorName,
                organization: r.item.organization,
                isMarketVoice: r.item.isMarketVoice,
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
            ),
      ],
      headline: draft.headline,
      learn:
          draft.learn == null
              ? null
              : ReportLearn(
                concept: draft.learn!.concept,
                text: draft.learn!.text,
              ),
      followUpQuestion: draft.followUpQuestion,
      closing: draft.closing,
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
    'movers': [for (final m in movers) m.toJson()],
    'concentration': concentration?.toJson(),
    'news': [for (final n in news) n.toJson()],
    'investors': [for (final i in investors) i.toJson()],
    'upcoming_earnings': [for (final e in upcomingEarnings) e.toJson()],
    'headline': headline,
    'learn': learn?.toJson(),
    'follow_up_question': followUpQuestion,
    'closing': closing,
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
      final concentration = j['concentration'];
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
        movers: list('movers').map(ReportMover.fromJson).toList(),
        concentration:
            concentration is Map
                ? ReportConcentration.fromJson(
                  concentration.cast<String, Object?>(),
                )
                : null,
        news: list('news').map(ReportNews.fromJson).toList(),
        investors: list('investors').map(ReportInvestor.fromJson).toList(),
        upcomingEarnings:
            list('upcoming_earnings').map(ReportEarnings.fromJson).toList(),
        headline: j['headline'] as String?,
        learn:
            learn is Map
                ? ReportLearn(
                  concept: learn['concept'] as String,
                  text: learn['text'] as String,
                )
                : null,
        followUpQuestion: j['follow_up_question'] as String?,
        closing: j['closing'] as String?,
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
    required this.contributionPp,
    required this.boughtThisWeek,
    this.pricePct,
    this.why,
    this.news,
  });

  final String ticker;
  final double? pricePct;
  final double contributionPp;
  final bool boughtThisWeek;
  final String? why;

  /// La noticia con la que Porty relacionó el movimiento.
  final ReportNews? news;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'price_pct': pricePct,
    'contribution_pp': contributionPp,
    'bought_this_week': boughtThisWeek,
    'why': why,
    'news': news?.toJson(),
  };

  static ReportMover fromJson(Map<String, Object?> j) => ReportMover(
    ticker: j['ticker'] as String,
    pricePct: _num(j['price_pct']),
    contributionPp: _num(j['contribution_pp'])!,
    boughtThisWeek: j['bought_this_week'] == true,
    why: j['why'] as String?,
    news:
        j['news'] is Map
            ? ReportNews.fromJson((j['news'] as Map).cast<String, Object?>())
            : null,
  );
}

class ReportConcentration {
  const ReportConcentration({
    required this.ticker,
    required this.weightNow,
    this.weightFourWeeksAgo,
  });

  final String ticker;
  final double weightNow;
  final double? weightFourWeeksAgo;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'weight_now': weightNow,
    'weight_4w': weightFourWeeksAgo,
  };

  static ReportConcentration fromJson(Map<String, Object?> j) =>
      ReportConcentration(
        ticker: j['ticker'] as String,
        weightNow: _num(j['weight_now'])!,
        weightFourWeeksAgo: _num(j['weight_4w']),
      );
}

class ReportNews {
  const ReportNews({
    required this.ticker,
    required this.headline,
    required this.source,
    required this.url,
    required this.date,
    this.take,
  });

  final String ticker;
  final String headline;
  final String source;
  final String url;
  final DateTime date;
  final String? take;

  ReportNews withTake(String take) => ReportNews(
    ticker: ticker,
    headline: headline,
    source: source,
    url: url,
    date: date,
    take: take,
  );

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'headline': headline,
    'source': source,
    'url': url,
    'date': _ymd(date),
    'take': take,
  };

  static ReportNews fromJson(Map<String, Object?> j) => ReportNews(
    ticker: j['ticker'] as String,
    headline: j['headline'] as String,
    source: j['source'] as String,
    url: j['url'] as String,
    date: _date(j['date']),
    take: j['take'] as String?,
  );
}

class ReportInvestor {
  const ReportInvestor({
    required this.who,
    required this.isMarketVoice,
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
  final bool isMarketVoice;
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
    'market_voice': isMarketVoice,
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
    isMarketVoice: j['market_voice'] == true,
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
  });

  final String ticker;
  final DateTime date;
  final String? timingLabel;

  Map<String, Object?> toJson() => {
    'ticker': ticker,
    'date': _ymd(date),
    'timing': timingLabel,
  };

  static ReportEarnings fromJson(Map<String, Object?> j) => ReportEarnings(
    ticker: j['ticker'] as String,
    date: _date(j['date']),
    timingLabel: j['timing'] as String?,
  );
}

class ReportLearn {
  const ReportLearn({required this.concept, required this.text});
  final String concept;
  final String text;

  Map<String, Object?> toJson() => {'concept': concept, 'text': text};
}

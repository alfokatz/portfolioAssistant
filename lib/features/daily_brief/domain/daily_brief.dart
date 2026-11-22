import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';

/// `full` = con Porty (Premium, Gold o cortesía); `numbers` = solo los
/// números de la app (Free) o, sin respuesta de Porty, lo que se pudo armar.
enum DailyBriefVariant {
  full,
  numbers;

  static DailyBriefVariant fromWire(Object? v) =>
      v == 'full' ? DailyBriefVariant.full : DailyBriefVariant.numbers;
}

/// Un hecho de mercado: el texto viene del pulso validado del servidor y la
/// `connection` (opcional) de Porty.
class BriefMarketLine {
  const BriefMarketLine({
    required this.text,
    required this.sourceIds,
    this.topicId,
    this.connection,
  });

  final String text;
  final List<String> sourceIds;
  final String? topicId;
  final String? connection;

  Map<String, Object?> toJson() => {
    'topic_id': topicId,
    'text': text,
    'source_ids': sourceIds,
    'connection': connection,
  };

  static BriefMarketLine? tryParse(Object? raw) {
    final fact = BriefMarketFact.tryParse(raw);
    if (fact == null) return null;
    final connection = (raw as Map)['connection'];
    return BriefMarketLine(
      text: fact.text,
      sourceIds: fact.sourceIds,
      topicId: fact.topicId,
      connection:
          connection is String && connection.trim().isNotEmpty
              ? connection
              : null,
    );
  }
}

/// Una señal de la cartera (concentración…), la misma que `morning_brief`.
class BriefSignal {
  const BriefSignal({required this.kind, this.ticker, this.weightPct});

  final String kind;
  final String? ticker;
  final double? weightPct;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'ticker': ticker,
    'weight_pct': weightPct,
  };

  static BriefSignal? tryParse(Object? raw) {
    if (raw is! Map || raw['kind'] is! String) return null;
    return BriefSignal(
      kind: raw['kind'] as String,
      ticker: raw['ticker'] is String ? raw['ticker'] as String : null,
      weightPct:
          raw['weight_pct'] is num
              ? (raw['weight_pct'] as num).toDouble()
              : null,
    );
  }
}

/// El aviso de plan de Free: dice qué plan trae lo que falta, sin ticker.
class BriefTeaser {
  const BriefTeaser({required this.kind, required this.requiredPlan});

  final String kind;
  final String requiredPlan;

  static const heldNews = BriefTeaser(
    kind: 'held_news',
    requiredPlan: 'premium',
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'required_plan': requiredPlan,
  };

  static BriefTeaser? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final kind = raw['kind'];
    final plan = raw['required_plan'];
    if (kind is! String || plan is! String) return null;
    return BriefTeaser(kind: kind, requiredPlan: plan);
  }
}

/// El brief de un día (`daily_briefs.payload`, spec §3.4). Los números los
/// pone la app; la prosa, Porty; los hechos de mercado, el servidor.
class DailyBrief {
  const DailyBrief({
    required this.day,
    required this.lang,
    required this.variant,
    required this.asOf,
    required this.numbers,
    this.why = const [],
    this.heldNews = const [],
    this.watchNews = const [],
    this.market = const [],
    this.earnings = const [],
    this.signals = const [],
    this.teaser,
    this.sources = const {},
    this.courtesy = false,
    this.courtesyNumber,
    this.courtesyTotal,
  });

  static const payloadVersion = 1;

  /// `YYYY-MM-DD` local.
  final String day;
  final String lang;
  final DailyBriefVariant variant;
  final DateTime asOf;
  final DailyBriefNumbers numbers;
  final List<BriefLine> why;
  final List<BriefLine> heldNews;
  final List<BriefLine> watchNews;
  final List<BriefMarketLine> market;
  final List<BriefEarning> earnings;
  final List<BriefSignal> signals;
  final BriefTeaser? teaser;
  final Map<String, BriefSource> sources;

  /// De regalo (no viaja en el payload: lo dice el claim).
  final bool courtesy;
  final int? courtesyNumber;
  final int? courtesyTotal;

  /// La fuente de un titular o hecho, si la hay.
  BriefSource? sourceOf(String? id) => id == null ? null : sources[id];

  /// Arma el brief con lo que se tiene. Con [variant] `numbers` no hay
  /// prosa de Porty: `market` queda en 1 hecho sin conexión y va el aviso de
  /// plan. Con `full`, solo entra lo que Porty escribió **y** tiene medio y
  /// link: nada se muestra sin fuente.
  static DailyBrief compose({
    required String day,
    required String lang,
    required DateTime now,
    required DailyBriefNumbers numbers,
    required DailyBriefBundle bundle,
    required DailyBriefVariant variant,
    DailyBriefProse prose = DailyBriefProse.empty,
    bool courtesy = false,
    int? courtesyNumber,
    int? courtesyTotal,
    bool? withTeaser,
  }) {
    final full = variant == DailyBriefVariant.full;
    final byId = {for (final h in bundle.mine) h.id: h};
    final heldIds = {for (final h in bundle.held) h.id};
    final watchIds = {for (final h in bundle.watch) h.id};
    List<BriefLine> keep(List<BriefLine> lines, Set<String> allowed) => [
      for (final l in lines)
        if (l.newsId != null && allowed.contains(l.newsId)) l,
    ];
    // "Por qué" puede colgar de un titular de cartera, nunca de la watchlist.
    final why = full ? keep(prose.why, heldIds) : const <BriefLine>[];
    final held = full ? keep(prose.held, heldIds) : const <BriefLine>[];
    final watch = full ? keep(prose.watch, watchIds) : const <BriefLine>[];

    final facts = bundle.market
        .where((f) => f.sourceIds.any(bundle.sources.containsKey))
        .take(full ? 3 : 1);
    final market = [
      for (final f in facts)
        BriefMarketLine(
          text: f.text,
          sourceIds: [
            for (final id in f.sourceIds)
              if (bundle.sources.containsKey(id)) id,
          ],
          topicId: f.topicId,
          connection:
              full && f.topicId != null
                  ? _clean(prose.connections[f.topicId])
                  : null,
        ),
    ];

    final sources = <String, BriefSource>{};
    for (final line in [...why, ...held, ...watch]) {
      final h = byId[line.newsId];
      if (h == null) continue;
      sources[h.id] = BriefSource(
        title: h.title,
        source: h.source,
        domain: h.domain,
        url: h.url,
        publishedAt: h.publishedAt,
        imageUrl: h.imageUrl,
      );
    }
    for (final m in market) {
      for (final id in m.sourceIds) {
        sources[id] = bundle.sources[id]!;
      }
    }

    return DailyBrief(
      day: day,
      lang: lang,
      variant: variant,
      asOf: now,
      numbers: numbers,
      why: why,
      heldNews: held,
      watchNews: watch,
      market: market,
      earnings: full ? bundle.earnings : const [],
      teaser: (withTeaser ?? !full) ? BriefTeaser.heldNews : null,
      sources: sources,
      courtesy: courtesy,
      courtesyNumber: courtesyNumber,
      courtesyTotal: courtesyTotal,
    );
  }

  static String? _clean(String? text) =>
      text == null || text.trim().isEmpty ? null : text.trim();

  /// El payload de `complete_daily_brief` (§3.4). `audio` siempre `null`.
  Map<String, Object?> toJson() => {
    'v': payloadVersion,
    'day': day,
    'lang': lang,
    'variant': variant.name,
    'as_of': asOf.toUtc().toIso8601String(),
    'numbers': numbers.toJson(),
    'why': [for (final l in why) l.toJson()],
    'held_news': [for (final l in heldNews) l.toJson()],
    'watch_news': [for (final l in watchNews) l.toJson()],
    'market': [for (final m in market) m.toJson()],
    'earnings': [for (final e in earnings) e.toJson()],
    'signals': [for (final s in signals) s.toJson()],
    'teaser': teaser?.toJson(),
    'sources': {for (final e in sources.entries) e.key: e.value.toJson()},
    'audio': null,
  };

  /// `null` si es de otra versión o le faltan los números: la app recalcula.
  /// [courtesy] viene del claim, no del payload.
  static DailyBrief? tryParse(
    Map<String, Object?> json, {
    bool courtesy = false,
    int? courtesyNumber,
    int? courtesyTotal,
  }) {
    if (json['v'] != payloadVersion) return null;
    final day = json['day'];
    final numbers = DailyBriefNumbers.tryParse(json['numbers']);
    if (day is! String || numbers == null) return null;
    List<T> list<T>(String key, T? Function(Object?) parse) {
      final raw = json[key];
      return raw is List ? raw.map(parse).whereType<T>().toList() : <T>[];
    }

    final sources = json['sources'];
    return DailyBrief(
      day: day,
      lang: json['lang'] == 'en' ? 'en' : 'es',
      variant: DailyBriefVariant.fromWire(json['variant']),
      asOf: DateTime.tryParse('${json['as_of']}') ?? DateTime.now(),
      numbers: numbers,
      why: list('why', BriefLine.tryParse),
      heldNews: list('held_news', BriefLine.tryParse),
      watchNews: list('watch_news', BriefLine.tryParse),
      market: list('market', BriefMarketLine.tryParse),
      earnings: list('earnings', BriefEarning.tryParse),
      signals: list('signals', BriefSignal.tryParse),
      teaser: BriefTeaser.tryParse(json['teaser']),
      sources: {
        if (sources is Map)
          for (final e in sources.entries)
            if (e.key is String)
              if (BriefSource.tryParse(e.value) case final s?)
                e.key as String: s,
      },
      courtesy: courtesy,
      courtesyNumber: courtesyNumber,
      courtesyTotal: courtesyTotal,
    );
  }
}

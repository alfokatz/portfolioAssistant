import 'dart:convert';

import 'package:portfolio_assistant/domain/entities/company_news_item.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/company_news_repository.dart';
import 'package:portfolio_assistant/domain/subscription/plan_matrix.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// No se pudo traer algo (red, servidor). Quien llama se queda con la caché
/// anterior: el usuario nunca ve un error por esto.
class WidgetItemsFailure implements Exception {
  const WidgetItemsFailure(this.reason);

  final String reason;

  @override
  String toString() => 'WidgetItemsFailure($reason)';
}

/// Conteos para los avisos del plan siguiente (fase 2 de backend:
/// `headlines?count_only=1` y `sec?endpoint=earnings_count`). Hasta que
/// exista, [NoWidgetCountsClient] devuelve `null` y los avisos salen sin
/// número (solo Android).
abstract interface class WidgetCountsClient {
  Future<WidgetTeaserCounts?> fetch(List<String> tickers, {DateTime? now});
}

class NoWidgetCountsClient implements WidgetCountsClient {
  const NoWidgetCountsClient();

  @override
  Future<WidgetTeaserCounts?> fetch(
    List<String> tickers, {
    DateTime? now,
  }) async => null;
}

/// Todo lo que cambia entre una consulta y otra.
class WidgetItemsRequest {
  const WidgetItemsRequest({
    required this.uid,
    required this.holdings,
    required this.tier,
    required this.teasersEnabled,
    required this.platform,
    required this.now,
    this.planUntil,
    this.force = false,
  });

  final String uid;
  final List<WidgetHolding> holdings;
  final SubscriptionTier tier;
  final bool teasersEnabled;
  final WidgetPlatform platform;
  final DateTime now;
  final DateTime? planUntil;

  /// Saltea el freno de 30 min.
  final bool force;
}

/// Trae noticias y fechas de resultados del top 5 de la cartera, elige lo
/// que va al widget y lo deja en la caché privada. Solo el camino v2
/// (`headlines` + `sec`): nada de Finnhub. Ver Am.4.3 de la spec.
class WidgetItemsRepository {
  WidgetItemsRepository({
    required this.news,
    required this.earnings,
    required SharedPreferences prefs,
    this.counts = const NoWidgetCountsClient(),
  }) : cache = WidgetItemsCache(prefs),
       _prefs = prefs;

  static const minInterval = Duration(minutes: 30);
  static const earningsTtl = Duration(hours: 12);

  /// Después de una falla (sin red, 429) no se vuelve a pedir enseguida:
  /// cada publish (Home, ajuste, idioma, plan) usaría la caché.
  static const failureBackoff = Duration(minutes: 5);

  /// Cuánto se "garantiza" un plan pago sin volver a abrir la app: el estado
  /// de suscripción no trae vencimiento, así que pasado este plazo el nativo
  /// esconde lo pago hasta la próxima apertura con sesión.
  static const paidPlanGrace = Duration(hours: 24);

  DateTime? _lastFailureAt;

  final CompanyNewsRepository news;
  final EarningsSource earnings;
  final WidgetCountsClient counts;
  final WidgetItemsCache cache;
  final SharedPreferences _prefs;

  /// Lo guardado para [uid], tal cual (sin pedir nada).
  WidgetItemsCacheEntry? cached(String uid) => cache.read(uid: uid);

  /// Vuelve a pedir si pasó el freno o cambió el top 5, el plan o el aviso.
  /// Lanza [WidgetItemsFailure] si falla; la caché anterior queda intacta.
  Future<WidgetItemsCacheEntry> refresh(WidgetItemsRequest r) async {
    final top = WidgetItemsSelector.universe(r.holdings);
    final topKey = ([for (final h in top) h.ticker.toUpperCase()]
      ..sort()).join(',');
    final previous = cache.read(uid: r.uid);
    if (previous != null &&
        !r.force &&
        r.now.difference(previous.checkedAt) < minInterval &&
        !r.now.isBefore(previous.checkedAt) &&
        previous.top == topKey &&
        previous.tier == r.tier.name &&
        previous.teasersEnabled == r.teasersEnabled) {
      return previous;
    }
    final lastFailure = _lastFailureAt;
    if (!r.force &&
        lastFailure != null &&
        r.now.difference(lastFailure) < failureBackoff &&
        !r.now.isBefore(lastFailure)) {
      throw const WidgetItemsFailure('backoff');
    }
    try {
      final entry = await _fetch(r, top, topKey);
      _lastFailureAt = null;
      return entry;
    } catch (_) {
      _lastFailureAt = r.now;
      rethrow;
    }
  }

  Future<WidgetItemsCacheEntry> _fetch(
    WidgetItemsRequest r,
    List<WidgetHolding> top,
    String topKey,
  ) async {
    final tickers = [for (final h in top) h.ticker];
    var fetchedNews = const <CompanyNewsItem>[];
    if (tickers.isNotEmpty && PlanMatrix.allowsNewsFor(r.tier, held: true)) {
      fetchedNews = await _fetchNews(tickers, r.now);
    }
    var dates = const <WidgetEarningsDate>[];
    if (tickers.isNotEmpty && PlanMatrix.allows(r.tier, PlanFeature.earnings)) {
      dates = await _fetchEarnings(r.uid, tickers, r.now);
    }
    WidgetTeaserCounts? teaserCounts;
    if (r.teasersEnabled && tickers.isNotEmpty) {
      try {
        teaserCounts = await counts.fetch(tickers, now: r.now);
      } catch (_) {
        teaserCounts = null;
      }
    }

    final selection = WidgetItemsSelector.select(
      holdings: r.holdings,
      news: fetchedNews,
      earnings: dates,
      tier: r.tier,
      teasersEnabled: r.teasersEnabled,
      teaserCounts: teaserCounts,
      platform: r.platform,
      now: r.now,
      cap: WidgetItemsSelector.maxItemsV2,
    );
    final entry = WidgetItemsCacheEntry(
      uid: r.uid,
      checkedAt: r.now,
      tier: r.tier.name,
      top: topKey,
      teasersEnabled: r.teasersEnabled,
      planUntil:
          r.planUntil ??
          (r.tier == SubscriptionTier.free ? null : r.now.add(paidPlanGrace)),
      itemsSection: selection.itemsSection,
      items: [
        for (final i in selection.items) WidgetCachedItem.fromSelected(i),
      ],
      teaser: selection.teaser,
    );
    await cache.write(entry);
    return entry;
  }

  Future<List<CompanyNewsItem>> _fetchNews(
    List<String> tickers,
    DateTime now,
  ) async {
    // Día completo hasta mañana: así comparte la caché del servidor.
    final from = now.subtract(WidgetItemsSelector.newsWindow);
    final to = now.add(const Duration(days: 1));
    final results = await Future.wait([
      for (final t in tickers)
        news.getRecentNews(t, limit: 5, from: from, to: to),
    ]);
    final all = <CompanyNewsItem>[];
    for (final result in results) {
      final failure = result.fold<String?>((e) => e.code, (_) => null);
      // El servidor dice que el plan no alcanza (falta el deploy): cero
      // ítems, nunca error.
      if (failure == 'plan_required') continue;
      if (failure != null) throw WidgetItemsFailure(failure);
      all.addAll(result.getOrElse(() => const []));
    }
    return all;
  }

  /// `next_report.date` por ticker, con caché local de 12 h.
  Future<List<WidgetEarningsDate>> _fetchEarnings(
    String uid,
    List<String> tickers,
    DateTime now,
  ) async {
    final stored = _readEarningsCache(uid);
    final missing = [
      for (final t in tickers)
        if (!_fresh(stored[t.toUpperCase()], now)) t,
    ];
    if (missing.isNotEmpty) {
      final Map<String, Object?> body;
      try {
        body = await earnings.fetch(missing);
      } catch (e) {
        throw WidgetItemsFailure('earnings: $e');
      }
      if (body['status'] == 'failed') {
        throw const WidgetItemsFailure('earnings failed');
      }
      final byTicker = body['earnings'];
      for (final t in missing) {
        final entry = byTicker is Map ? byTicker[t] : null;
        final next = entry is Map ? entry['next_report'] : null;
        final date = next is Map ? '${next['date'] ?? ''}' : '';
        stored[t.toUpperCase()] = (
          at: now,
          date: DateTime.tryParse(date) == null ? null : date.substring(0, 10),
        );
      }
      await _prefs.setString(
        WidgetItemsCache.earningsKey,
        jsonEncode({
          'uid': uid,
          'by_ticker': {
            for (final e in stored.entries)
              e.key: {
                'at': e.value.at.toUtc().millisecondsSinceEpoch,
                'date': e.value.date,
              },
          },
        }),
      );
    }
    return [
      for (final t in tickers)
        if (stored[t.toUpperCase()]?.date != null)
          (ticker: t, date: _day(stored[t.toUpperCase()]!.date!)),
    ];
  }

  static DateTime _day(String iso) {
    final d = DateTime.parse(iso);
    return DateTime(d.year, d.month, d.day);
  }

  static bool _fresh(({DateTime at, String? date})? e, DateTime now) =>
      e != null && !now.isBefore(e.at) && now.difference(e.at) < earningsTtl;

  Map<String, ({DateTime at, String? date})> _readEarningsCache(String uid) {
    final raw = _prefs.getString(WidgetItemsCache.earningsKey);
    final out = <String, ({DateTime at, String? date})>{};
    if (raw == null) return out;
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['uid'] != uid) return out;
      final by = json['by_ticker'];
      if (by is! Map) return out;
      by.forEach((k, v) {
        if (v is Map && v['at'] is int) {
          out['$k'] = (
            at: DateTime.fromMillisecondsSinceEpoch(
              v['at'] as int,
              isUtc: true,
            ),
            date: v['date'] as String?,
          );
        }
      });
    } catch (_) {}
    return out;
  }
}

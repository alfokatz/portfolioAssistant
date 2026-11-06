import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_background_refresh.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_chart_loader.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_counts_client.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_feed_cache.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_repository.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_insight_copy.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_feed_order.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_portfolio_facts.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot_builder.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/investor_profile/providers/investor_profile_provider.dart';
import 'package:portfolio_assistant/features/porty_inbox/providers/porty_inbox_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/conversion_flags.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/assistant/data/market/earnings_fetcher.dart'
    show EarningsSource;
import 'package:portfolio_assistant/features/assistant/data/market/news_provider.dart';
import 'package:portfolio_assistant/features/assistant/data/market/sec_market_fetchers.dart';
import 'package:portfolio_assistant/infraestructure/repositories/gdelt_headlines_repository_impl.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Session;

/// Lo último bueno que se sabe de la cartera, listo para (re)escribir el
/// snapshot sin red (cambio de idioma o del ajuste de montos).
sealed class _Known {
  const _Known();
}

class _KnownEmpty extends _Known {
  const _KnownEmpty();
}

class _KnownReady extends _Known {
  const _KnownReady({
    required this.totalValue,
    required this.move,
    required this.dataAsOf,
    this.holdings = const [],
    this.facts = const [],
    this.chart,
  });

  final double totalValue;
  final PortfolioDayMove move;
  final DateTime dataAsOf;

  /// Las posiciones por ticker (para elegir las novedades).
  final List<WidgetHolding> holdings;

  /// Valor y variación del último día por ticker (mover y biggest).
  final List<WidgetPositionFact> facts;

  /// La forma del día (o de los últimos días); `null` si no hay datos.
  final WidgetChart? chart;
}

/// Lo que solo tiene la app abierta (avisos de la Home, meta, desvío del
/// plan, perfil): alimenta el feed y se guarda en `widget_feed_cache_v1`
/// para el refresco de fondo.
class WidgetFeedExtras {
  const WidgetFeedExtras({
    this.insights = const [],
    this.goalLabel,
    this.driftTicker,
    this.profileRisk,
  });

  final List<WidgetInsightInput> insights;
  final String? goalLabel;

  /// `null` = sin desvío; `''` = desvío sin ticker.
  final String? driftTicker;
  final String? profileRisk;
}

/// Mantiene al día el snapshot que lee el widget de la pantalla de inicio
/// (ver docs/specs/home-widget-tech.md §3.3). Escribe con un debounce de
/// 500 ms y nunca rompe ni demora nada de la app: cualquier error se traga.
class HomeWidgetSyncController {
  HomeWidgetSyncController({
    required this.store,
    required this.prefs,
    required this.events,
    required this.scheduler,
    required this.loadTexts,
    required this.loadCandles,
    this.loadIntraday,
    required this.currentUserId,
    required this.amountsHidden,
    required String initialLang,
    this.items,
    this.newsV2Enabled,
    this.currentTier,
    this.teasersEnabled,
    this.feedExtras,
    DateTime Function()? now,
    this.debounce = const Duration(milliseconds: 500),
  }) : _lang = AppLanguage.normalize(initialLang),
       _now = now ?? DateTime.now;

  final HomeWidgetStore store;
  final SharedPreferences prefs;
  final ProductEvents events;
  final WidgetBackgroundScheduler scheduler;
  final Future<WidgetTexts> Function(String lang) loadTexts;
  final Future<List<PriceCandle>> Function(String ticker) loadCandles;

  /// Velas intradía (5 min) para el gráfico del día; `null` = sin intradía.
  final Future<List<PriceCandle>> Function(String ticker)? loadIntraday;
  final String? Function() currentUserId;
  final bool Function() amountsHidden;

  /// Novedades (opcional: sin esto el widget es el de la v1).
  final WidgetItemsRepository? items;

  /// `news_provider == v2`. Con otro valor el widget no trae nada.
  final Future<bool> Function()? newsV2Enabled;

  /// El plan, o `null` si todavía no cargó.
  final SubscriptionTier? Function()? currentTier;

  /// Interruptor remoto de los avisos de esta plataforma.
  final Future<bool> Function()? teasersEnabled;

  /// Avisos, meta, desvío y perfil de la app abierta (opcional).
  final WidgetFeedExtras Function()? feedExtras;
  final Duration debounce;
  final DateTime Function() _now;

  String _lang;
  _Known? _known;
  Timer? _timer;
  Future<void> Function()? _pendingHome;
  Future<void> _queue = Future.value();

  /// Sube al cerrar sesión: lo que estaba en vuelo de la sesión anterior no
  /// escribe (no resucita datos de otra cuenta).
  int _epoch = 0;
  bool _disposed = false;

  // Disparadores ------------------------------------------------------------

  /// La Home cambió. Solo cuenta lo que llegó bien: no escribe con la carga
  /// fallida (se queda el último bueno) ni con el caché (no pisa datos de un
  /// refresco de fondo más nuevos).
  void onHome(HomeState? previous, HomeState next) {
    if (next.loading || next.fromCache || next.quoteError != null) return;
    final summary = next.summary;
    if (summary == null) return;
    if (previous != null &&
        identical(previous.summary, summary) &&
        identical(previous.history, next.history) &&
        !previous.fromCache &&
        previous.quoteError == null) {
      return;
    }
    final epoch = _epoch;
    final history = next.history;
    final dataAsOf = _now();
    _timer?.cancel();
    _pendingHome = () => _captureHome(epoch, summary, history, dataAsOf);
    _timer = Timer(debounce, _fireHome);
  }

  void _fireHome() {
    final job = _pendingHome;
    _pendingHome = null;
    if (job != null) _enqueue(job);
  }

  /// "Ocultar posiciones en el widget" cambió: reescribe en el acto, sin red.
  /// Si todavía no hay datos buenos de esta sesión (arranque sin red o con
  /// la Home desde el caché), igual saca los montos del snapshot guardado.
  void onHiddenChanged() => _enqueue(() async {
    if (_known == null) {
      if (amountsHidden()) await store.scrubStoredPositions();
      return;
    }
    await _publish();
  });

  /// Cambió un insumo del feed (avisos de la Home, metas, desvío del plan o
  /// perfil): reescribe desde lo último conocido, sin red.
  void onFeedInputsChanged() => _enqueue(_publish);

  /// El plan cargó o cambió: vuelve a elegir las novedades (el repositorio
  /// pide de nuevo porque cambió el plan).
  void onTierChanged() => _enqueue(_publish);

  /// El idioma de la app. Idempotente: se puede llamar en cada build.
  void onLanguage(String languageCode) {
    final lang = AppLanguage.normalize(languageCode);
    if (lang == _lang) return;
    _lang = lang;
    _enqueue(_publish);
  }

  /// Cerrar sesión (o borrar la cuenta, que termina en signOut): primero el
  /// uid, después el snapshot `signed_out`. El JSON entero se reemplaza.
  void onSignedOut() {
    _epoch++;
    _timer?.cancel();
    _pendingHome = null;
    _known = null;
    _enqueue(() async {
      await prefs.remove(WidgetPrefsKeys.ownerUid);
      for (final key in WidgetPrefsKeys.promptKeys) {
        await prefs.remove(key);
      }
      await WidgetItemsCache(prefs).clear();
      await store.clearRenderLog();
      await store.clearCursor();
      final texts = await loadTexts(_lang);
      await store.writeSnapshot(
        WidgetSnapshotBuilder.signedOut(lang: _lang, now: _now(), texts: texts),
      );
      await scheduler.cancel();
    });
  }

  /// Al arrancar: qué widgets hay instalados. Loguea solo si cambió respecto
  /// de lo último guardado, y deja el refresco de fondo acorde.
  Future<void> reportPresence() async {
    try {
      final sizes = await store.installedSizes();
      final stored = prefs.getStringList(WidgetPrefsKeys.presence) ?? const [];
      if (!listEquals(sizes, stored)) {
        events.log(ProductEvent.widgetPresence, {
          'platform': store.platform,
          'sizes': sizes,
        });
        await prefs.setStringList(WidgetPrefsKeys.presence, sizes);
      }
      if (sizes.isEmpty) await scheduler.cancel();
    } catch (_) {}
  }

  /// Al abrir: loguea una vez por tamaño lo que el nativo dibujó desde la
  /// última vez (aproximación de impresiones; nunca ticker ni titular).
  Future<void> reportItemsRendered({SubscriptionTier? tier}) async {
    try {
      final log = await store.readRenderLog();
      if (log == null) return;
      final lastLogged = prefs.getInt(WidgetItemsCache.renderLoggedKey) ?? 0;
      var newest = lastLogged;
      for (final size in const ['small', 'medium', 'large']) {
        final entry = log[size];
        if (entry is! Map) continue;
        final at = entry['at'];
        if (at is! int || at <= lastLogged) continue;
        if (at > newest) newest = at;
        final teaser = entry['teaser'];
        final kinds = entry['kinds'] is Map ? entry['kinds'] as Map : const {};
        int count(String kind) {
          final v = kinds[kind] ?? entry[kind];
          return v is int ? v : 0;
        }

        final line = entry['line'];
        final shownKind = entry['shown_kind'];
        final shownPrio = entry['shown_prio'];
        final live = entry['live'];
        events.log(ProductEvent.widgetItemsRendered, {
          'size': size,
          'news_count': count('news'),
          'earnings_count': count('earnings'),
          'insight_count': count('insight'),
          'mover_count': count('mover'),
          'biggest_count': count('biggest'),
          'live_count': live is int ? live : 0,
          'teaser': teaser == 'news' || teaser == 'earnings' ? teaser : 'none',
          if (size == 'small')
            'line_kind': _renderLines.contains(line) ? line : 'none',
          if (size == 'medium') ...{
            'shown_kind':
                WidgetFeedKind.fromWire(shownKind is String ? shownKind : null)
                    ?.wire,
            'shown_prio': shownPrio is int ? shownPrio : null,
          },
          'tier': (tier ?? currentTier?.call())?.name,
          'positions_hidden': amountsHidden(),
          'platform': store.platform,
        });
      }
      if (newest > lastLogged) {
        await prefs.setInt(WidgetItemsCache.renderLoggedKey, newest);
      }
      await _reportFeedAdvanced(log);
    } catch (_) {}
  }

  static const _renderLines = {
    'dated',
    'insight',
    'chart',
    'hidden_count',
    'none',
  };

  /// Clave privada: hasta qué `next_taps` del mediano ya se registró.
  @visibleForTesting
  static const nextTapsLoggedKey = 'widget_next_taps_logged';

  /// Los toques de "siguiente" no abren la app: el nativo los cuenta en el
  /// render log y acá se registra la diferencia desde la última vez.
  Future<void> _reportFeedAdvanced(Map<String, Object?> log) async {
    final medium = log['medium'];
    final taps = medium is Map ? medium['next_taps'] : null;
    if (taps is! int) return;
    final logged = prefs.getInt(nextTapsLoggedKey) ?? 0;
    // El contador volvió a cero (reinstalación, otro widget): se reancla.
    if (taps < logged) {
      await prefs.setInt(nextTapsLoggedKey, taps);
      return;
    }
    if (taps == logged) return;
    events.log(ProductEvent.widgetFeedAdvanced, {
      'platform': store.platform,
      'size': 'medium',
      'taps': taps - logged,
    });
    await prefs.setInt(nextTapsLoggedKey, taps);
  }

  /// Escribe ya lo que esté pendiente (tests).
  @visibleForTesting
  Future<void> flush() async {
    _timer?.cancel();
    _fireHome();
    await _queue;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  // Escritura ----------------------------------------------------------------

  void _enqueue(Future<void> Function() job) {
    if (_disposed) return;
    _queue = _queue.then((_) async {
      try {
        await job();
      } catch (_) {
        // Un widget desactualizado no le cuesta nada al usuario.
      }
    });
  }

  Future<void> _captureHome(
    int epoch,
    PortfolioSummary summary,
    List<PortfolioHistoryPoint> history,
    DateTime dataAsOf,
  ) async {
    if (epoch != _epoch) return;
    if (summary.valuations.isEmpty) {
      _known = const _KnownEmpty();
      await prefs.remove(WidgetPrefsKeys.ownerUid);
      await _publish();
      return;
    }
    final lots = summary.lots.isNotEmpty ? summary.lots : summary.valuations;
    final positions = [for (final v in lots) v.position];
    final candles = await _candlesFor(positions);
    if (epoch != _epoch) return;
    final move = PortfolioDayMove.compute(
      history: history,
      positions: positions,
      candlesByTicker: candles,
      now: _now(),
    );
    final chart = await loadWidgetChart(
      positions: positions,
      dailyCandles: candles,
      movePercent: move.percent,
      dailyValues: [for (final p in history) p.totalValue],
      loadIntraday: loadIntraday,
    );
    if (epoch != _epoch) return;
    _known = _KnownReady(
      chart: chart,
      holdings: [
        for (final v in summary.valuations)
          WidgetHolding(
            ticker: v.position.ticker,
            marketValue: v.marketValue,
            isCrypto: v.position.source.isBinance,
          ),
      ],
      facts: [
        for (final v in summary.valuations)
          WidgetPositionFact(
            ticker: v.position.ticker,
            marketValue: v.marketValue,
            dayPct: WidgetPortfolioFacts.dayPct(
              candles[v.position.ticker] ?? const [],
            ),
          ),
      ],
      totalValue: summary.totalValue,
      move: move,
      dataAsOf: dataAsOf,
    );
    final uid = currentUserId();
    if (uid != null) await prefs.setString(WidgetPrefsKeys.ownerUid, uid);
    await _publish();
  }

  /// Las velas salen del caché de Yahoo que la Home ya llenó. Un ticker que
  /// falla queda afuera y el "mayor aporte" pasa a `null`.
  Future<Map<String, List<PriceCandle>>> _candlesFor(
    List<Position> positions,
  ) async {
    final candles = <String, List<PriceCandle>>{};
    for (final ticker in {for (final p in positions) p.ticker}) {
      try {
        candles[ticker] = await loadCandles(ticker);
      } catch (_) {}
    }
    return candles;
  }

  Future<void> _publish() async {
    final known = _known;
    if (known == null) return;
    final epoch = _epoch;
    final lang = _lang;
    final texts = await loadTexts(lang);
    if (epoch != _epoch) return;
    final now = _now();
    final WidgetSnapshot snapshot;
    if (known is _KnownReady) {
      final entry = await _itemsEntry(known, now);
      if (epoch != _epoch) return;
      final uid = currentUserId();
      final tier = currentTier?.call() ?? SubscriptionTier.free;
      final extras = feedExtras?.call() ?? const WidgetFeedExtras();
      final hidden = amountsHidden();
      final feedCache = WidgetFeedCache(prefs);
      final biggest = WidgetPortfolioFacts.biggest(known.facts);
      final built = WidgetSnapshotBuilder.readyBuild(
        move: known.move,
        chart: known.chart,
        positionsHidden: hidden,
        lang: lang,
        now: now,
        dataAsOf: known.dataAsOf,
        texts: texts,
        tier: tier,
        platform: _platform,
        selection: entry?.selection(now),
        planUntil: entry?.planUntil,
        insights: extras.insights,
        mover: WidgetPortfolioFacts.mover(known.facts),
        biggest: biggest,
        questionContext: WidgetQuestionContext(
          tier: tier,
          goalLabel: extras.goalLabel,
          hasDrift: extras.driftTicker != null,
          driftTicker: extras.driftTicker,
          biggestTicker: biggest?.ticker,
          profileRisk: extras.profileRisk,
        ),
        feedState:
            uid == null
                ? const WidgetFeedState()
                : feedCache.readState(uid: uid),
      );
      snapshot = built.snapshot;
      if (uid != null) {
        // Lo que el refresco de fondo y el toque de una pregunta necesitan.
        await feedCache.write(
          WidgetFeedCacheEntry(
            uid: uid,
            writtenAt: now,
            insights: extras.insights,
            goalLabel: extras.goalLabel,
            driftTicker: extras.driftTicker,
            profileRisk: extras.profileRisk,
            biggest: biggest,
            questions: feedCache.read(uid: uid)?.questions ?? const {},
          ),
        );
        await feedCache.rememberQuestions(
          uid: uid,
          drafts: built.questionDrafts,
          hidden: hidden,
          now: now,
        );
        // Con posiciones ocultas no hay ids en el JSON: no se toca el estado.
        if (!hidden) await feedCache.writeState(uid: uid, state: built.feedState);
      }
    } else {
      snapshot = WidgetSnapshotBuilder.noPortfolio(
        lang: lang,
        now: now,
        texts: texts,
      );
    }
    await prefs.setString(WidgetPrefsKeys.lang, lang);
    await store.writeSnapshot(snapshot);
    if (snapshot.state == WidgetSnapshotState.ready) {
      await _syncBackgroundTask();
    }
  }

  WidgetPlatform get _platform =>
      store.platform == 'ios' ? WidgetPlatform.ios : WidgetPlatform.android;

  /// Las novedades vigentes: trae lo nuevo si pasó el freno de 30 min (o
  /// cambió el top 5, el plan o el aviso); si falla o el plan no cargó, se
  /// queda con la caché anterior. `null` = sin bloque (v2 apagado, sin uid).
  Future<WidgetItemsCacheEntry?> _itemsEntry(
    _KnownReady known,
    DateTime now,
  ) async {
    final repo = items;
    final uid = currentUserId();
    if (repo == null || uid == null) return null;
    // Sin el plan cargado no se sabe qué se puede mostrar: sin bloque (se
    // reescribe con `onTierChanged` cuando cargue).
    final tier = currentTier?.call();
    if (tier == null) return null;
    // La caché solo sirve si se trajo con este mismo plan (un Gold que pasó
    // a Free no sigue viendo resultados ni noticias).
    WidgetItemsCacheEntry? cachedForTier() {
      final previous = repo.cached(uid);
      return previous != null && previous.tier == tier.name ? previous : null;
    }

    try {
      if (!(await (newsV2Enabled?.call() ?? Future.value(false)))) {
        await repo.cache.clearItems();
        return null;
      }
      final teasers = await (teasersEnabled?.call() ?? Future.value(false));
      return await repo.refresh(
        WidgetItemsRequest(
          uid: uid,
          holdings: known.holdings,
          tier: tier,
          teasersEnabled: teasers,
          platform: _platform,
          now: now,
        ),
      );
    } catch (_) {
      // Falla de red o del servidor: se queda lo anterior, sin error.
      return cachedForTier();
    }
  }

  /// El refresco de fondo solo corre si hay algún widget instalado.
  Future<void> _syncBackgroundTask() async {
    final sizes = await store.installedSizes();
    if (sizes.isEmpty) {
      await scheduler.cancel();
    } else {
      await scheduler.ensureRegistered();
    }
  }
}

final widgetTextsLoaderProvider =
    Provider<Future<WidgetTexts> Function(String lang)>(
      (ref) => WidgetTexts.load,
    );

final widgetIntradayLoaderProvider =
    Provider<Future<List<PriceCandle>> Function(String ticker)?>((ref) {
      final QuoteRepository quotes = ref.watch(quoteRepositoryProvider);
      return quotes.getIntradayCandles;
    });

final widgetCandleLoaderProvider =
    Provider<Future<List<PriceCandle>> Function(String ticker)>((ref) {
      final QuoteRepository quotes = ref.watch(quoteRepositoryProvider);
      return (ticker) async {
        final result = await quotes.getHistoricalDaily(ticker);
        return result.fold<List<PriceCandle>>(
          (e) => throw StateError(e.message ?? e.code),
          (c) => c,
        );
      };
    });

/// Noticias y resultados del widget: solo el camino v2 (`headlines` + `sec`).
final widgetItemsRepositoryProvider = Provider<WidgetItemsRepository>((ref) {
  final EarningsSource earnings = SecEarningsFetcher();
  return WidgetItemsRepository(
    news: GdeltHeadlinesRepositoryImpl(),
    earnings: earnings,
    prefs: ref.watch(sharedPreferencesProvider),
    counts: EdgeWidgetCountsClient(),
  );
});

final widgetBackgroundSchedulerProvider = Provider<WidgetBackgroundScheduler>(
  (ref) => const WorkmanagerWidgetScheduler(),
);

/// Los insumos del feed que solo tiene la app abierta, con los mismos
/// avisos que la bandeja de la Home.
/// Lee un insumo del feed sin romper: si un provider falla (sin red, sin
/// Supabase), el widget se escribe igual con lo demás.
T? _safeRead<T>(T Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}

WidgetFeedExtras _feedExtras(Ref ref) {
  final insights = <WidgetInsightInput>[
    for (final i in _safeRead(() => ref.read(portyInsightsProvider)) ?? const [])
      if (WidgetInsightKind.fromName(i.kind.name) case final kind?)
        WidgetInsightInput(
          id: i.id,
          kind: kind,
          score: i.score,
          ticker: i.ticker,
          goalLabel: i.goalLabel,
          numbers: i.numbers,
        ),
  ];
  // La meta del primer aviso de meta; si no, la activa con fecha más cercana.
  String? goal;
  for (final i in insights) {
    if (i.kind.isGoal && (i.goalLabel?.isNotEmpty ?? false)) {
      goal = i.goalLabel;
      break;
    }
  }
  if (goal == null) {
    final active = [...?_safeRead(() => ref.read(goalsProvider).active)]
      ..sort((a, b) => a.targetDate.compareTo(b.targetDate));
    if (active.isNotEmpty) goal = active.first.label;
  }
  final drift = _safeRead(() => ref.read(allocationDriftProvider));
  return WidgetFeedExtras(
    insights: insights,
    goalLabel: goal,
    driftTicker: drift?.ticker,
    profileRisk: _safeRead<String?>(
      () => ref.read(investorProfileProvider).profile?.risk.storageValue,
    ),
  );
}

/// Vive mientras está montado el shell (lo lee `AppShell`).
final homeWidgetSyncProvider = Provider<HomeWidgetSyncController>((ref) {
  final controller = HomeWidgetSyncController(
    store: ref.watch(homeWidgetStoreProvider),
    prefs: ref.watch(sharedPreferencesProvider),
    events: ref.watch(productEventsProvider),
    scheduler: ref.watch(widgetBackgroundSchedulerProvider),
    loadTexts: ref.watch(widgetTextsLoaderProvider),
    loadCandles: ref.watch(widgetCandleLoaderProvider),
    loadIntraday: ref.watch(widgetIntradayLoaderProvider),
    currentUserId: ref.read(widgetCurrentUserIdProvider),
    amountsHidden: () => ref.read(widgetPositionsHiddenProvider),
    initialLang: AppLanguage.code,
    items: ref.watch(widgetItemsRepositoryProvider),
    newsV2Enabled:
        () async => await NewsProviderConfig.instance.load() == NewsProvider.v2,
    currentTier: () {
      final state = _safeRead(() => ref.read(subscriptionProvider));
      return state == null || state.isLoading ? null : state.tier;
    },
    feedExtras: () => _feedExtras(ref),
    teasersEnabled: () async {
      final android = defaultTargetPlatform != TargetPlatform.iOS;
      return android
          ? await ref.read(widgetTeasersAndroidEnabledProvider.future)
          : await ref.read(widgetTeasersIosEnabledProvider.future);
    },
  );
  ref.onDispose(controller.dispose);
  ref.listen<HomeState>(homeProvider, controller.onHome, fireImmediately: true);
  ref.listen<bool>(
    widgetPositionsHiddenProvider,
    (_, __) => controller.onHiddenChanged(),
  );
  ref.listen<SubscriptionState>(subscriptionProvider, (previous, next) {
    if (previous?.tier != next.tier || previous?.isLoading != next.isLoading) {
      controller.onTierChanged();
    }
  });
  // Cualquier insumo del feed que cambie reescribe (mismo debounce y cola).
  ref.listen(portyInsightsProvider, (_, __) => controller.onFeedInputsChanged());
  ref.listen(goalsProvider, (_, __) => controller.onFeedInputsChanged());
  ref.listen(
    allocationDriftProvider,
    (_, __) => controller.onFeedInputsChanged(),
  );
  ref.listen(
    investorProfileProvider,
    (_, __) => controller.onFeedInputsChanged(),
  );
  ref.listen<AsyncValue<Session?>>(authSessionProvider, (previous, next) {
    if (previous?.valueOrNull != null && next.valueOrNull == null) {
      controller.onSignedOut();
    }
  });
  unawaited(controller.reportPresence());
  unawaited(controller.reportItemsRendered());
  return controller;
});

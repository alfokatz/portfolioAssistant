import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_series_builder.dart';
import 'package:portfolio_assistant/features/home_widget/data/home_widget_store.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_chart_loader.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_feed_cache.dart';
import 'package:portfolio_assistant/features/home_widget/data/widget_items_cache.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_items_selector.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_portfolio_facts.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_questions.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_snapshot_builder.dart';
import 'package:portfolio_assistant/features/home_widget/domain/widget_texts.dart';
import 'package:portfolio_assistant/features/home_widget/providers/widget_settings_provider.dart';
import 'package:portfolio_assistant/infraestructure/data_sources/yahoo_quote_remote_data_source.dart';
import 'package:portfolio_assistant/presentation/flows/home/data/home_portfolio_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

/// Identificador de la tarea de fondo. En iOS es también el id de
/// `BGTaskSchedulerPermittedIdentifiers` (el plugin usa el `uniqueName` como
/// identificador del BGAppRefreshTask), así que tiene que coincidir con el
/// de Info.plist.
const widgetRefreshTaskId = 'com.portyassistant.app.widget_refresh';

/// Hasta cuándo puede trabajar el refresco (iOS corta a ~30 s).
const widgetRefreshBudget = Duration(seconds: 25);

/// Prepara los plugins del widget. No rompe la app donde no hay soporte
/// (tests, escritorio).
Future<void> initializeHomeWidgetPlugins() async {
  try {
    await HomeWidget.setAppGroupId(homeWidgetAppGroupId);
  } catch (_) {}
  try {
    await Workmanager().initialize(widgetBackgroundDispatcher);
  } catch (_) {}
}

/// La app arrancó sin sesión: si la sesión murió con la app cerrada (por
/// ejemplo, revocada desde otro equipo), el widget no puede seguir mostrando
/// la cartera ni refrescándola. Mismo efecto que cerrar sesión: se borran
/// también los ítems de novedades, su caché privada y el render log.
Future<void> clearHomeWidgetForSignedOutLaunch({
  required SharedPreferences prefs,
  HomeWidgetStore store = const PluginHomeWidgetStore(),
  WidgetBackgroundScheduler scheduler = const WorkmanagerWidgetScheduler(),
  Future<WidgetTexts> Function(String lang) loadTexts = WidgetTexts.load,
  DateTime Function() now = DateTime.now,
}) async {
  try {
    await prefs.remove(WidgetPrefsKeys.ownerUid);
    await WidgetItemsCache(prefs).clear();
    await store.clearRenderLog();
    await store.clearCursor();
    await scheduler.cancel();
    final lang = prefs.getString(WidgetPrefsKeys.lang) ?? 'es';
    await store.writeSnapshot(
      WidgetSnapshotBuilder.signedOut(
        lang: lang,
        now: now(),
        texts: await loadTexts(lang),
      ),
    );
  } catch (_) {
    // Sin soporte del plugin (tests, escritorio).
  }
}

/// Registra y cancela el refresco periódico.
abstract class WidgetBackgroundScheduler {
  Future<void> ensureRegistered();
  Future<void> cancel();
}

class WorkmanagerWidgetScheduler implements WidgetBackgroundScheduler {
  const WorkmanagerWidgetScheduler();

  @override
  Future<void> ensureRegistered() async {
    try {
      await Workmanager().registerPeriodicTask(
        widgetRefreshTaskId,
        widgetRefreshTaskId,
        // Android: cada 30 min como mucho (Doze lo estira). iOS ignora la
        // frecuencia: `initialDelay` es el "no antes de" del BGAppRefreshTask.
        frequency: const Duration(minutes: 30),
        initialDelay: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } catch (_) {
      // Sin soporte o sin permiso: el widget igual se actualiza al abrir.
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await Workmanager().cancelByUniqueName(widgetRefreshTaskId);
    } catch (_) {}
  }
}

/// Punto de entrada del isolate de fondo.
@pragma('vm:entry-point')
void widgetBackgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != widgetRefreshTaskId) return true;
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await HomeWidget.setAppGroupId(homeWidgetAppGroupId);
      final yahoo = _yahooSource();
      final deps = WidgetRefreshDeps(
        prefs: await SharedPreferences.getInstance(),
        loadCandles: yahoo.getHistoricalDaily,
        loadIntraday: yahoo.getIntradayCandles,
        loadTexts: WidgetTexts.load,
        store: const PluginHomeWidgetStore(),
        now: DateTime.now,
      );
      await refreshOnce(deps).timeout(widgetRefreshBudget);
    } catch (_) {
      // Reintenta el próximo ciclo.
    }
    return true;
  });
}

/// Velas diarias directo de Yahoo, sin sesión de Supabase (ver §3.5 de la
/// spec: un segundo cliente de Supabase podría rotar el refresh token y
/// cerrar la sesión del usuario). Con `cacheTtl` explícito: `dotenv` no
/// está cargado en este isolate.
YahooQuoteRemoteDataSource _yahooSource() => YahooQuoteRemoteDataSource(
  cacheTtl: const Duration(minutes: 10),
  dio: Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      // Sin User-Agent de navegador Yahoo responde 429 al intradía.
      headers: {'User-Agent': 'Mozilla/5.0'},
    ),
  ),
);

/// Todo lo que necesita [refreshOnce], inyectable para tests.
class WidgetRefreshDeps {
  const WidgetRefreshDeps({
    required this.prefs,
    required this.loadCandles,
    required this.loadTexts,
    required this.store,
    required this.now,
    this.loadIntraday,
  });

  final SharedPreferences prefs;
  final Future<List<PriceCandle>> Function(String ticker) loadCandles;

  /// Velas intradía (5 min) para el gráfico del día; `null` = sin intradía.
  final Future<List<PriceCandle>> Function(String ticker)? loadIntraday;
  final Future<WidgetTexts> Function(String lang) loadTexts;
  final HomeWidgetStore store;
  final DateTime Function() now;
}

/// Un refresco: tenencias del caché privado de la Home + precios nuevos →
/// snapshot `ready`. Devuelve si escribió. No toca el caché de la Home, no
/// loguea eventos y no usa la sesión.
Future<bool> refreshOnce(WidgetRefreshDeps deps) async {
  // Este isolate tiene su propia copia de las preferencias.
  await deps.prefs.reload();
  final uid = deps.prefs.getString(WidgetPrefsKeys.ownerUid);
  if (uid == null || uid.isEmpty) return false;

  final cache = HomePortfolioCache(prefs: deps.prefs, userId: () => uid);
  final cached = cache.read();
  if (cached == null) return false;
  final valuations =
      cached.summary.lots.isNotEmpty
          ? cached.summary.lots
          : cached.summary.valuations;
  if (valuations.isEmpty) return false;
  final positions = [for (final v in valuations) v.position];

  final candles = <String, List<PriceCandle>>{};
  final failed = <String>[];
  for (final ticker in {for (final p in positions) p.ticker}) {
    try {
      final loaded = await deps.loadCandles(ticker);
      if (loaded.isEmpty) throw StateError('sin velas');
      candles[ticker] = loaded;
    } catch (_) {
      failed.add(ticker);
    }
  }
  if (candles.isEmpty) return false;

  // Un ticker caído se queda en el precio del caché, plano: no aporta
  // movimiento (ni se inventa uno).
  if (failed.isNotEmpty) {
    final dates = {
      for (final list in candles.values)
        for (final c in list) c.date,
    };
    for (final ticker in failed) {
      final price =
          valuations
              .firstWhere((v) => v.position.ticker == ticker)
              .currentPrice;
      candles[ticker] = [
        for (final d in dates) PriceCandle(date: d, close: price),
      ];
    }
  }

  final now = deps.now();
  final history = PortfolioSeriesBuilder.build(positions, candles, now: now);
  if (history.isEmpty) return false;
  final move = PortfolioDayMove.compute(
    history: history,
    positions: positions,
    candlesByTicker: candles,
    now: now,
  );

  final lang = deps.prefs.getString(WidgetPrefsKeys.lang) ?? 'es';
  final texts = await deps.loadTexts(lang);
  final positionsHidden = WidgetPrefsKeys.readPositionsHidden(deps.prefs);

  // Las novedades no se traen acá (no hay sesión): se rearman desde la caché
  // privada sin lo vencido. Una caché de otro uid no cuenta.
  final entry = WidgetItemsCache(deps.prefs).read(uid: uid);
  // Pasado `plan_until` no se sabe si el plan sigue: lo pago no vuelve a
  // escribirse en el almacenamiento compartido hasta abrir la app.
  final planExpired = entry?.planUntil?.isBefore(now) ?? false;
  final usable = planExpired ? null : entry;
  final tier =
      SubscriptionTier.values.where((t) => t.name == entry?.tier).firstOrNull ??
      SubscriptionTier.free;

  // Avisos, meta, desvío y perfil: lo último que supo la app abierta (hasta
  // 24 h; más viejo no se usa). Mover y biggest sí salen de los precios nuevos.
  final feedCache = WidgetFeedCache(deps.prefs);
  final extras = feedCache.read(uid: uid);
  final fresh = extras != null && extras.isFresh(now) ? extras : null;
  final facts = <WidgetPositionFact>[
    for (final v in valuations)
      WidgetPositionFact(
        ticker: v.position.ticker,
        marketValue:
            PortfolioCalculator.valuate(
              position: v.position,
              currentPrice: _lastClose(candles[v.position.ticker]!),
            ).marketValue,
        dayPct: WidgetPortfolioFacts.dayPct(candles[v.position.ticker]!),
      ),
  ];
  final biggest = WidgetPortfolioFacts.biggest(facts);
  final chart = await loadWidgetChart(
    positions: positions,
    dailyCandles: candles,
    movePercent: move.percent,
    dailyValues: [for (final p in history) p.totalValue],
    loadIntraday: deps.loadIntraday,
  );
  final built = WidgetSnapshotBuilder.readyBuild(
    move: move,
    chart: chart,
    positionsHidden: positionsHidden,
    lang: lang,
    now: now,
    dataAsOf: now,
    texts: texts,
    tier: tier,
    platform:
        deps.store.platform == 'ios'
            ? WidgetPlatform.ios
            : WidgetPlatform.android,
    selection: usable?.selection(now),
    planUntil: usable?.planUntil,
    insights: fresh?.insights ?? const [],
    mover: WidgetPortfolioFacts.mover(facts),
    biggest: biggest,
    questionContext: WidgetQuestionContext(
      tier: tier,
      goalLabel: fresh?.goalLabel,
      hasDrift: fresh?.driftTicker != null,
      driftTicker: fresh?.driftTicker,
      biggestTicker: biggest?.ticker,
      profileRisk: fresh?.profileRisk,
    ),
    feedState: feedCache.readState(uid: uid),
  );

  // Si mientras tanto se cerró sesión (o entró otra cuenta), no se
  // resucita nada.
  await deps.prefs.reload();
  if (deps.prefs.getString(WidgetPrefsKeys.ownerUid) != uid) return false;
  await deps.store.writeSnapshot(built.snapshot);
  // La histéresis persiste entre refrescos (con posiciones ocultas no hay
  // ids en el JSON: no se toca) y el toque de una pregunta del dibujo
  // anterior sigue resolviendo.
  if (!positionsHidden) {
    await feedCache.writeState(uid: uid, state: built.feedState);
  }
  await feedCache.rememberQuestions(
    uid: uid,
    drafts: built.questionDrafts,
    hidden: positionsHidden,
    now: now,
  );
  return true;
}

double _lastClose(List<PriceCandle> candles) =>
    candles.reduce((a, b) => b.date.isAfter(a.date) ? b : a).close;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/config/translate/app_language.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_history_point.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_generator.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_numbers_loader.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_numbers.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum DailyBriefPhase {
  /// Interruptor apagado, sin cartera, fin de semana, día sin cierre nuevo o
  /// sin respuesta del servidor: no hay fila, no hay entrada.
  hidden,

  /// Calculando los números o Porty escribiendo.
  loading,
  ready,
}

class DailyBriefState {
  const DailyBriefState({
    this.phase = DailyBriefPhase.hidden,
    this.brief,
    this.generating = false,
    this.freshlyGenerated = false,
    this.status = DailyBriefStatus.off,
    this.failed = false,
  });

  final DailyBriefPhase phase;
  final DailyBrief? brief;

  /// Porty está escribiendo (y no solo calculando números).
  final bool generating;
  final bool freshlyGenerated;

  /// El interruptor general y las piezas (para la entrada al feed).
  final DailyBriefStatus status;

  /// No se pudo armar el brief de hoy (se muestra el estado de error).
  final bool failed;
}

/// El brief del día en la Home y su pantalla. La máquina de estados es la de
/// `claim_daily_brief` (spec §3.3):
/// - ready → se muestra lo guardado.
/// - claimed → números + titulares del servidor → Porty escribe → se guarda.
/// - numbers_only → números + 1 hecho de mercado, **sin llamar al LLM**.
/// - in_progress → números ahora y se vuelve a preguntar en un rato.
/// - disabled / no_portfolio / not_business_day / failed → sin brief.
///
/// Con el interruptor apagado (`daily_brief_status.enabled = false`) el
/// estado queda `hidden` y no se pide nada más: la Home no cambia.
class DailyBriefController extends StateNotifier<DailyBriefState> {
  DailyBriefController({
    required DailyBriefStore store,
    required DailyBriefNumbersLoader numbers,
    required DailyBriefWriter writer,
    required String? Function() userId,
    SharedPreferences? preferences,
    DateTime Function()? clock,
    String Function()? language,
    void Function(ProductEvent event, Map<String, Object?> props)? logEvent,
    this.retryDelay = const Duration(seconds: 20),
  }) : _store = store,
       _numbers = numbers,
       _writer = writer,
       _userId = userId,
       _prefs = preferences,
       _clock = clock ?? DateTime.now,
       _language = language ?? (() => AppLanguage.code),
       _log = logEvent,
       super(const DailyBriefState()) {
    _hydrate();
  }

  final DailyBriefStore _store;
  final DailyBriefNumbersLoader _numbers;
  final DailyBriefWriter _writer;
  final String? Function() _userId;
  final SharedPreferences? _prefs;
  final DateTime Function() _clock;
  final String Function() _language;
  final void Function(ProductEvent event, Map<String, Object?> props)? _log;
  final Duration retryDelay;

  static const maxInProgressRetries = 3;

  /// Tickers por los que el servidor busca titulares (los de más peso).
  static const newsTickers = 8;

  Future<void>? _inFlight;
  Timer? _retry;
  int _inProgressRetries = 0;
  String? _settledDay;
  String? _disabledDay;

  /// Hasta cuándo no se vuelve a preguntar después de una falla de red.
  DateTime? _unreachableUntil;
  static const _unreachableBackoff = Duration(minutes: 1);
  String? _loadedFor;
  int _epoch = 0;
  List<PortfolioHistoryPoint> _history = const [];
  List<Position> _lots = const [];

  /// Lo llama la Home cada vez que tiene (o refresca) la cartera.
  /// Idempotente dentro del mismo día.
  Future<void> ensureFor(
    List<PortfolioHistoryPoint> history,
    List<Position> lots,
  ) {
    final uid = _userId();
    if (uid != _loadedFor) _resetFor(uid);
    _history = history;
    _lots = lots;
    if (uid == null || lots.isEmpty || history.isEmpty) {
      _retry?.cancel();
      if (state.phase != DailyBriefPhase.hidden) {
        state = DailyBriefState(status: state.status);
      }
      return Future.value();
    }
    final day = DailyBriefNumbers.dayKey(_clock());
    final current = state.brief;
    final sameDay = current != null && current.day == day;
    if (sameDay && (_settledDay == day || _retry != null)) {
      return Future.value();
    }
    if (_disabledDay == day) return Future.value();
    final waitUntil = _unreachableUntil;
    if (waitUntil != null && _clock().isBefore(waitUntil)) {
      return Future.value();
    }
    return _inFlight ??= _load(
      day,
      _epoch,
    ).whenComplete(() => _inFlight = null);
  }

  /// Vuelve a intentar después de un error (botón de la pantalla).
  Future<void> retry() {
    _settledDay = null;
    _disabledDay = null;
    _unreachableUntil = null;
    _inProgressRetries = 0;
    return ensureFor(_history, _lots);
  }

  void _hydrate() {
    final uid = _userId();
    if (uid == null) return;
    _loadedFor = uid;
    final cached = _readCache(DailyBriefNumbers.dayKey(_clock()));
    if (cached != null) {
      state = DailyBriefState(
        phase: DailyBriefPhase.ready,
        brief: cached,
        // Sin piezas hasta que llegue el estado real: nada de entradas
        // (feed, comparar) que el servidor pueda tener apagadas.
        status: const DailyBriefStatus(
          enabled: true,
          pieces: {
            'push': false,
            'feed': false,
            'topics': false,
            'sources': false,
            'market': false,
            'compare': false,
            'videos': false,
          },
        ),
      );
    }
  }

  void _resetFor(String? uid) {
    _epoch++;
    _loadedFor = uid;
    _retry?.cancel();
    _retry = null;
    _inFlight = null;
    _inProgressRetries = 0;
    _settledDay = null;
    _disabledDay = null;
    _unreachableUntil = null;
    state = const DailyBriefState();
    _hydrate();
  }

  bool _stale(int epoch) => !mounted || epoch != _epoch;

  Future<void> _load(String day, int epoch) async {
    final hadBrief = state.brief?.day == day;
    // El completo ya está guardado y no cambia en el día.
    if (hadBrief && state.brief!.variant == DailyBriefVariant.full) {
      _settledDay = day;
      return;
    }
    final status = await _store.status();
    if (_stale(epoch)) return;
    if (!status.reachable) {
      // Falla transitoria (red, servidor): se deja lo que había, sin cerrar
      // el día ni borrar la caché; se vuelve a preguntar en un rato.
      _unreachableUntil = _clock().add(_unreachableBackoff);
      return;
    }
    _unreachableUntil = null;
    if (!status.enabled) {
      // Apagado: nada nuevo en la Home. No se vuelve a preguntar hoy.
      _disabledDay = day;
      _clearCache();
      _retry?.cancel();
      _retry = null;
      state = const DailyBriefState();
      return;
    }
    if (_noNewClose(day)) {
      _settledDay = day;
      state = DailyBriefState(status: status);
      return;
    }
    if (!hadBrief) {
      state = DailyBriefState(phase: DailyBriefPhase.loading, status: status);
    }
    final claim = await _store.claim(day);
    if (_stale(epoch)) return;
    if (claim is! BriefClaimUnavailable) _settledDay = day;
    switch (claim) {
      case BriefClaimReady(:final payload, :final courtesy):
        _cancelRetry();
        final brief = DailyBrief.tryParse(payload, courtesy: courtesy);
        if (brief != null && brief.day == day) {
          _show(brief, status: status);
        } else {
          // Payload de otra versión: se recalculan los números.
          await _numbersOnly(day, epoch, status: status, save: false);
        }
      case BriefClaimGranted(
        :final courtesy,
        :final courtesyNumber,
        :final courtesyTotal,
      ):
        await _generate(
          day,
          epoch,
          status: status,
          courtesy: courtesy,
          courtesyNumber: courtesyNumber,
          courtesyTotal: courtesyTotal,
        );
      case BriefClaimNumbersOnly():
        await _numbersOnly(day, epoch, status: status, save: true);
      case BriefClaimInProgress():
        if (!hadBrief) {
          await _numbersOnly(day, epoch, status: status, save: false);
        }
        _scheduleInProgressRetry(day, epoch);
      case BriefClaimFailed():
        await _numbersOnly(day, epoch, status: status, save: false);
      case BriefClaimDisabled():
        _disabledDay = day;
        _clearCache();
        state = const DailyBriefState();
      case BriefClaimNoPortfolio() || BriefClaimNotBusinessDay():
        _clearCache();
        state = DailyBriefState(status: status);
      case BriefClaimUnavailable():
        // Sin respuesta no se sabe si el brief está prendido para este
        // usuario: sin fila, salvo que ya hubiera uno guardado de hoy.
        if (!hadBrief) state = DailyBriefState(status: status, failed: true);
    }
  }

  /// Feriado de todos los mercados de la cartera: el último punto del
  /// historial es el mismo cierre que ya contó un brief de un día anterior.
  bool _noNewClose(String day) {
    final prefs = _prefs;
    if (prefs == null || _loadedFor == null) return false;
    try {
      final saved = prefs.getString(_lastCloseKey);
      if (saved == null) return false;
      final parts = saved.split('|');
      if (parts.length != 2) return false;
      final asOf = DailyBriefNumbers.dayKey(_history.last.date);
      return parts[0] != day && parts[1] == asOf;
    } catch (_) {
      return false;
    }
  }

  Future<void> _numbersOnly(
    String day,
    int epoch, {
    required DailyBriefStatus status,
    required bool save,
  }) async {
    final numbers = await _numbers.load(
      history: _history,
      lots: _lots,
      now: _clock(),
    );
    if (_stale(epoch)) return;
    if (numbers.isEmpty) {
      state = DailyBriefState(status: status);
      return;
    }
    // El hecho de mercado (1) sale del servidor; sin red, el brief queda con
    // los números (nunca se inventa).
    var bundle = DailyBriefBundle.empty;
    try {
      bundle = DailyBriefBundle.parse(
        await _store.bundle('brief', day: day, lang: _language()),
      );
    } on DailyBriefFailure catch (_) {}
    if (_stale(epoch)) return;
    final brief = DailyBrief.compose(
      day: day,
      lang: _language(),
      now: _clock(),
      numbers: numbers,
      bundle: bundle,
      variant: DailyBriefVariant.numbers,
      // Solo el de Free lleva el aviso de plan. Un brief de Premium que no
      // pudo escribir Porty no pide un plan que ya tiene.
      withTeaser: save,
    );
    if (save) {
      try {
        await _store.complete(day, brief.toJson());
      } on DailyBriefFailure catch (e) {
        debugPrint('[DailyBrief] complete numbers failed: $e');
      }
      if (_stale(epoch)) return;
    }
    _show(brief, status: status, persist: save);
  }

  Future<void> _generate(
    String day,
    int epoch, {
    required DailyBriefStatus status,
    required bool courtesy,
    int? courtesyNumber,
    int? courtesyTotal,
  }) async {
    final watch = Stopwatch()..start();
    state = DailyBriefState(
      phase: DailyBriefPhase.loading,
      brief: state.brief?.day == day ? state.brief : null,
      generating: true,
      status: status,
    );
    final lang = _language();
    final results = await Future.wait<Object?>([
      _numbers.load(history: _history, lots: _lots, now: _clock()),
      _store
          .bundle('brief', day: day, lang: lang)
          .then<Object?>(DailyBriefBundle.parse)
          .catchError((Object _) => null),
    ]);
    if (_stale(epoch)) return;
    final numbers = results[0]! as DailyBriefNumbers;
    final bundle = results[1] as DailyBriefBundle?;
    if (numbers.isEmpty) {
      await _store.fail(day);
      if (_stale(epoch)) return;
      state = DailyBriefState(status: status);
      return;
    }
    if (bundle == null) {
      // El servidor de noticias no respondió: se libera el claim y se
      // muestran los números; se reintenta en la próxima apertura.
      _log?.call(ProductEvent.dailyBriefGenerated, {
        'variant': 'numbers',
        'rounds': 0,
        'removed_items': 0,
        'held_with_news_pct': 0,
        'ms': watch.elapsedMilliseconds,
        'error': 'bundle_failed',
      });
      await _store.fail(day);
      if (_stale(epoch)) return;
      _settledDay = null;
      _show(
        _numbersFallback(day, numbers, courtesy),
        status: status,
        persist: false,
      );
      return;
    }
    final hasContent = bundle.mine.isNotEmpty || bundle.market.isNotEmpty;
    final writing =
        hasContent
            ? await _writer.write(
              DailyBriefWritingRequest(
                day: day,
                language: lang,
                numbers: numbers,
                held: bundle.held,
                watch: bundle.watch,
                market: bundle.market,
                assetClasses: bundle.assetClasses,
              ),
            )
            : const DailyBriefWriting(prose: DailyBriefProse.empty);
    if (_stale(epoch)) return;
    final pct = _heldWithNewsPct(bundle);
    if (writing.failed) {
      _log?.call(ProductEvent.dailyBriefGenerated, {
        'variant': 'numbers',
        'rounds': writing.rounds,
        'removed_items': writing.removedItems,
        'held_with_news_pct': pct,
        'ms': watch.elapsedMilliseconds,
        'error': writing.error,
      });
      debugPrint('[DailyBrief] generation failed: ${writing.error}');
      await _store.fail(day);
      if (_stale(epoch)) return;
      _settledDay = null;
      _show(
        _numbersFallback(day, numbers, courtesy),
        status: status,
        persist: false,
      );
      return;
    }
    final brief = DailyBrief.compose(
      day: day,
      lang: lang,
      now: _clock(),
      numbers: numbers,
      bundle: bundle,
      variant: DailyBriefVariant.full,
      prose: writing.prose,
      courtesy: courtesy,
      courtesyNumber: courtesyNumber,
      courtesyTotal: courtesyTotal,
    );
    try {
      final saved = await _store.complete(day, brief.toJson());
      if (!saved) debugPrint('[DailyBrief] complete rejected for $day');
    } on DailyBriefFailure catch (e) {
      debugPrint('[DailyBrief] complete failed: $e');
    }
    _log?.call(ProductEvent.dailyBriefGenerated, {
      'variant': 'full',
      'rounds': writing.rounds,
      'removed_items': writing.removedItems,
      'held_with_news_pct': pct,
      'ms': watch.elapsedMilliseconds,
      if (writing.error != null) 'error': writing.error,
    });
    if (_stale(epoch)) return;
    _show(brief, status: status, fresh: true);
  }

  DailyBrief _numbersFallback(
    String day,
    DailyBriefNumbers numbers,
    bool courtesy,
  ) => DailyBrief.compose(
    day: day,
    lang: _language(),
    now: _clock(),
    numbers: numbers,
    bundle: DailyBriefBundle.empty,
    variant: DailyBriefVariant.numbers,
    withTeaser: false,
    courtesy: courtesy,
  );

  /// Porcentaje (0-100) de las posiciones de más peso con al menos un
  /// titular. El denominador es lo que el servidor miró: las 8 de más peso.
  int _heldWithNewsPct(DailyBriefBundle bundle) {
    final distinct =
        {
          for (final p in _lots) PortfolioCalculator.normalizeTicker(p.ticker),
        }.length;
    final looked = distinct < newsTickers ? distinct : newsTickers;
    if (looked == 0) return 0;
    final withNews = {for (final h in bundle.held) h.ticker}.length;
    return ((withNews > looked ? looked : withNews) / looked * 100).round();
  }

  void _cancelRetry() {
    _retry?.cancel();
    _retry = null;
  }

  void _scheduleInProgressRetry(String day, int epoch) {
    _retry?.cancel();
    if (_inProgressRetries >= maxInProgressRetries) {
      _retry = null;
      return;
    }
    _inProgressRetries++;
    _retry = Timer(retryDelay, () {
      _retry = null;
      if (_stale(epoch)) return;
      _inFlight ??= _load(day, epoch).whenComplete(() => _inFlight = null);
    });
  }

  void _show(
    DailyBrief brief, {
    required DailyBriefStatus status,
    bool fresh = false,
    bool persist = true,
  }) {
    if (persist) _writeCache(brief);
    state = DailyBriefState(
      phase: DailyBriefPhase.ready,
      brief: brief,
      freshlyGenerated: fresh,
      status: status,
    );
  }

  // Caché del dispositivo: el brief de hoy al instante al abrir la app.

  String get _cachePrefix => 'daily_brief_cache_${_loadedFor ?? 'anon'}_';
  String get _lastCloseKey => 'daily_brief_last_close_${_loadedFor ?? 'anon'}';

  DailyBrief? _readCache(String day) {
    try {
      final raw = _prefs?.getString('$_cachePrefix$day');
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map || json['payload'] is! Map) return null;
      final brief = DailyBrief.tryParse(
        (json['payload'] as Map).cast<String, Object?>(),
        courtesy: json['courtesy'] == true,
        courtesyNumber: json['n'] as int?,
        courtesyTotal: json['total'] as int?,
      );
      return brief?.day == day ? brief : null;
    } catch (_) {
      return null;
    }
  }

  /// Solo se guarda el de hoy: los anteriores se borran.
  void _writeCache(DailyBrief brief) {
    final prefs = _prefs;
    if (prefs == null || _loadedFor == null) return;
    try {
      _clearCache(except: brief.day);
      prefs.setString(
        '$_cachePrefix${brief.day}',
        jsonEncode({
          'payload': brief.toJson(),
          'courtesy': brief.courtesy,
          'n': brief.courtesyNumber,
          'total': brief.courtesyTotal,
        }),
      );
      final asOf = brief.numbers.asOfDay;
      if (asOf != null) {
        prefs.setString(
          _lastCloseKey,
          '${brief.day}|${DailyBriefNumbers.dayKey(asOf)}',
        );
      }
    } catch (_) {}
  }

  void _clearCache({String? except}) {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final keep = except == null ? null : '$_cachePrefix$except';
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_cachePrefix) && key != keep) prefs.remove(key);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }
}

/// Escribe la prosa del brief. Hasta que el generador del chat esté
/// conectado, falla sin llamar a nadie y el brief sale con los números.
class UnavailableDailyBriefWriter implements DailyBriefWriter {
  const UnavailableDailyBriefWriter();

  @override
  Future<DailyBriefWriting> write(DailyBriefWritingRequest request) async =>
      const DailyBriefWriting(
        prose: DailyBriefProse.empty,
        error: 'writer_unavailable',
      );
}

/// Porty escribe la prosa con `DailyBriefGenerator` (chat).
final dailyBriefWriterProvider = Provider<DailyBriefWriter>(
  (ref) => DailyBriefGenerator(),
);

final dailyBriefNumbersLoaderProvider = Provider<DailyBriefNumbersLoader>(
  (ref) => DailyBriefNumbersLoader(quotes: ref.watch(quoteRepositoryProvider)),
);

/// Uno por sesión de usuario: se recrea al cambiar de cuenta.
final dailyBriefControllerProvider =
    StateNotifierProvider<DailyBriefController, DailyBriefState>((ref) {
      ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
      return DailyBriefController(
        store: ref.watch(dailyBriefRepositoryProvider),
        numbers: ref.watch(dailyBriefNumbersLoaderProvider),
        writer: ref.watch(dailyBriefWriterProvider),
        userId: () => ref.read(supabaseAuthServiceProvider).currentUser?.id,
        preferences: ref.watch(sharedPreferencesProvider),
        logEvent:
            (event, props) => ref.read(productEventsProvider).log(event, props),
      );
    });

/// La entrada al feed de noticias: solo con el interruptor general y la pieza
/// `feed` prendidos (`daily_brief_status`). Apagado, la app queda igual.
final newsFeedAvailableProvider = Provider<bool>(
  (ref) => ref.watch(
    dailyBriefControllerProvider.select((s) => s.status.piece('feed')),
  ),
);

/// Plan para el evento `daily_brief_opened` (no hay `PlanFeature`: el brief
/// lo decide el servidor).
final dailyBriefTierProvider = Provider<SubscriptionTier>(
  (ref) => ref.watch(subscriptionProvider.select((s) => s.tier)),
);

/// Abre una URL afuera de la app (inyectable en tests). Solo https.
final dailyBriefUrlLauncherProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) =>
          uri.scheme == 'https'
              ? launchUrl(uri, mode: LaunchMode.externalApplication)
              : Future.value(false),
);

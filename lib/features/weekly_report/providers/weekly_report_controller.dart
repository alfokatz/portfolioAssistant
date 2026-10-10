import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/subscription/subscription_policy.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_generator.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_input_builder.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_repository.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_claim.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/infraestructure/repositories/quote_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum WeeklyReportStatus {
  /// Sin posiciones: no hay tarjeta.
  hidden,

  /// Calculando números o generando el texto de Porty.
  loading,
  ready,
}

class WeeklyReportState {
  const WeeklyReportState({
    this.status = WeeklyReportStatus.hidden,
    this.report,
    this.generating = false,
    this.freshlyGenerated = false,
    this.seen = false,
  });

  final WeeklyReportStatus status;
  final WeeklyReport? report;

  /// Porty está escribiendo (y no solo calculando números): la tarjeta lo
  /// dice ("Porty está preparando tu semana…").
  final bool generating;

  /// Recién terminado en este dispositivo (no venía del servidor): la
  /// tarjeta lo anuncia con un toque.
  final bool freshlyGenerated;

  /// Ya se abrió la pantalla del informe de esta semana: no se re-anima.
  final bool seen;
}

/// Qué informe mostrar en la Home y cómo conseguirlo. Ver la máquina de
/// estados en `claim_weekly_report` (migración
/// 20261002120000_weekly_reports.sql):
/// - ready → se muestra lo guardado (otro dispositivo, o antes).
/// - claimed → se calculan los datos, Porty escribe, se guarda.
/// - in_progress → números ahora y se vuelve a preguntar en un rato.
/// - numbers_only / failed / unavailable → solo números (sin LLM).
///
/// El último informe de la semana queda guardado en el dispositivo: al abrir
/// la app se muestra al instante. El completo (con Porty) ya no cambia en
/// la semana y no se vuelve a pedir; las variantes de solo números se
/// revalidan en segundo plano, sin loader.
class WeeklyReportController extends StateNotifier<WeeklyReportState> {
  WeeklyReportController({
    required WeeklyReportStore store,
    required WeeklyReportInputBuilder builder,
    required WeeklyReportGenerator generator,
    required FutureOr<SubscriptionTier> Function() tier,
    required String? Function() userId,
    SharedPreferences? preferences,
    DateTime Function()? clock,
    this.retryDelay = const Duration(seconds: 20),
  }) : _store = store,
       _builder = builder,
       _generator = generator,
       _tier = tier,
       _userId = userId,
       _prefs = preferences,
       _clock = clock ?? DateTime.now,
       super(const WeeklyReportState()) {
    _hydrate();
  }

  final WeeklyReportStore _store;
  final WeeklyReportInputBuilder _builder;
  final WeeklyReportGenerator _generator;
  /// El plan del usuario, ya cargado (no el `free` por defecto mientras
  /// carga la suscripción: con ese, un Gold veía el teaser de Gold).
  final FutureOr<SubscriptionTier> Function() _tier;
  final String? Function() _userId;
  final SharedPreferences? _prefs;
  final DateTime Function() _clock;
  final Duration retryDelay;

  /// Veces que se vuelve a preguntar si otro dispositivo lo está generando.
  static const maxInProgressRetries = 3;

  Future<void>? _inFlight;
  Timer? _retry;
  int _inProgressRetries = 0;
  ReportWeek? _disabledWeek;

  /// Semana que ya se resolvió en esta sesión (con el servidor, o porque el
  /// guardado es el completo). Un informe recién leído del dispositivo no
  /// cuenta: se revalida una vez.
  ReportWeek? _settledWeek;

  /// Para quién es el estado actual. Al cambiar de cuenta (cerrar sesión y
  /// entrar con otra) se descarta todo: el informe de A nunca se muestra a B.
  String? _loadedFor;

  /// Sube con cada cambio de usuario: una carga en curso del usuario anterior
  /// que vuelve de un `await` con un epoch viejo no toca el estado.
  int _epoch = 0;
  List<Position> _lots = const [];
  List<ClosedPosition> _closed = const [];

  /// Lo llama la Home cada vez que tiene (o refresca) la cartera. Idempotente
  /// dentro de la misma semana.
  Future<void> ensureFor(
    List<Position> lots, {
    List<ClosedPosition> closed = const [],
  }) {
    final uid = _userId();
    if (uid != _loadedFor) _resetFor(uid);
    _lots = lots;
    _closed = closed;
    if (uid == null || lots.isEmpty) {
      _retry?.cancel();
      state = const WeeklyReportState();
      return Future.value();
    }
    final week = ReportWeek.coveredAt(_clock());
    final current = state.report;
    final sameWeek = current != null && current.week == week;
    // Resuelto, o con un reintento ya agendado (otro dispositivo generando):
    // la Home llama esto en cada rebuild y no tiene que adelantar nada.
    if (sameWeek && (_settledWeek == week || _retry != null)) {
      return Future.value();
    }
    // Apagado desde el servidor: no volver a preguntar en cada rebuild de la
    // Home (sí al cambiar de semana o reabrir la app).
    if (_disabledWeek == week) return Future.value();
    return _inFlight ??= _load(
      week,
      _epoch,
    ).whenComplete(() => _inFlight = null);
  }

  /// El informe guardado de esta semana, antes del primer frame de la Home.
  void _hydrate() {
    final uid = _userId();
    if (uid == null) return;
    _loadedFor = uid;
    final cached = _readCache(ReportWeek.coveredAt(_clock()));
    if (cached != null) _show(cached, persist: false);
  }

  /// Cambió el plan (compra, vencimiento): un informe de solo números puede
  /// pasar a otra variante. El completo se queda como está.
  void tierChanged() {
    final report = state.report;
    if (report == null || report.variant == WeeklyReportVariant.full) return;
    if (_lots.isEmpty || _userId() != _loadedFor) return;
    _retry?.cancel();
    _retry = null;
    _inProgressRetries = 0;
    _inFlight ??= _load(
      report.week,
      _epoch,
      useCache: false,
    ).whenComplete(() => _inFlight = null);
  }

  void _resetFor(String? uid) {
    _epoch++;
    _loadedFor = uid;
    _retry?.cancel();
    _retry = null;
    _inFlight = null;
    _inProgressRetries = 0;
    _disabledWeek = null;
    _settledWeek = null;
    state = const WeeklyReportState();
  }

  bool _stale(int epoch) => !mounted || epoch != _epoch;

  /// La pantalla del informe se abrió.
  void markSeen() {
    final report = state.report;
    if (report == null || state.seen) return;
    try {
      _prefs?.setBool(_seenKey(report.week), true);
    } catch (_) {}
    state = WeeklyReportState(
      status: state.status,
      report: report,
      generating: state.generating,
      seen: true,
    );
  }

  Future<void> _load(
    ReportWeek week,
    int epoch, {
    bool useCache = true,
  }) async {
    if (useCache && state.report?.week != week) {
      final cached = _readCache(week);
      if (cached != null) _show(cached, persist: false);
    }
    // El completo ya está guardado y no cambia en la semana.
    if (useCache &&
        state.report?.week == week &&
        state.report?.variant == WeeklyReportVariant.full) {
      _settledWeek = week;
      return;
    }
    if (state.report?.week != week) {
      state = const WeeklyReportState(status: WeeklyReportStatus.loading);
    }
    final claim = await _store.claim(week);
    if (_stale(epoch)) return;
    if (claim is! ClaimUnavailable) _settledWeek = week;
    switch (claim) {
      case ClaimReady(:final payload):
        _retry?.cancel();
        _retry = null;
        final report = WeeklyReport.tryParse(payload);
        if (report != null && report.week == week) {
          _show(report);
        } else {
          // Payload de otra versión: se recalculan los números.
          await _numbers(week, WeeklyReportVariant.numbersUnavailable, epoch);
        }
      case ClaimGranted(:final courtesy):
        await _generate(week, epoch, courtesy: courtesy);
      case ClaimInProgress():
        if (state.report?.week != week) {
          await _numbers(week, WeeklyReportVariant.numbersUnavailable, epoch);
        }
        _scheduleInProgressRetry(week, epoch);
      case ClaimNumbersOnly():
        await _numbers(week, WeeklyReportVariant.numbersLocked, epoch);
      case ClaimDisabled():
        _retry?.cancel();
        _retry = null;
        _disabledWeek = week;
        _clearCache();
        state = const WeeklyReportState();
      case ClaimFailed():
        final variant = await _locked();
        if (_stale(epoch)) return;
        await _numbers(week, variant, epoch);
      case ClaimUnavailable():
        // Sin respuesta del servidor no se sabe si el informe está prendido
        // (ni si el backend existe): no hay tarjeta, salvo que ya hubiera uno
        // guardado de esta semana. Se reintenta en la próxima apertura.
        if (state.report?.week != week) state = const WeeklyReportState();
    }
  }

  Future<void> _generate(
    ReportWeek week,
    int epoch, {
    required bool courtesy,
  }) async {
    state = WeeklyReportState(
      status: WeeklyReportStatus.loading,
      report: state.report?.week == week ? state.report : null,
      generating: true,
    );
    final input = await _builder.build(
      week: week,
      lots: _lots,
      closed: _closed,
    );
    if (_stale(epoch)) return;
    final generation = await _generator.generate(week: week, input: input);
    if (_stale(epoch)) return;
    if (generation.failed) {
      debugPrint(
        '[WeeklyReport] generation failed for ${week.key}: ${generation.error}',
      );
      await _store.fail(week);
      if (_stale(epoch)) return;
      _show(
        WeeklyReport.compose(
          input: input,
          draft: WeeklyReportDraft.empty,
          variant: WeeklyReportVariant.numbersUnavailable,
          courtesy: courtesy,
        ),
      );
      return;
    }
    final report = WeeklyReport.compose(
      input: input,
      draft: generation.draft,
      variant: WeeklyReportVariant.full,
      courtesy: courtesy,
    );
    final saved = await _store.complete(week, report.toJson());
    if (!saved) debugPrint('[WeeklyReport] complete rejected for ${week.key}');
    if (_stale(epoch)) return;
    _show(report, fresh: true);
  }

  Future<void> _numbers(
    ReportWeek week,
    WeeklyReportVariant variant,
    int epoch,
  ) async {
    // Revalidación que confirma lo que ya se muestra: no se vuelven a pedir
    // las cotizaciones de la semana.
    final current = state.report;
    if (current != null && current.week == week && current.variant == variant) {
      return;
    }
    final input = await _builder.build(
      week: week,
      lots: _lots,
      closed: _closed,
      numbersOnly: true,
    );
    if (_stale(epoch)) return;
    if (input.numbers.isEmpty) {
      state = const WeeklyReportState();
      return;
    }
    _show(
      WeeklyReport.compose(
        input: input,
        draft: WeeklyReportDraft.empty,
        variant: variant,
      ),
    );
  }

  void _scheduleInProgressRetry(ReportWeek week, int epoch) {
    _retry?.cancel();
    if (_inProgressRetries >= maxInProgressRetries) {
      _retry = null;
      return;
    }
    _inProgressRetries++;
    _retry = Timer(retryDelay, () {
      _retry = null;
      if (_stale(epoch)) return;
      _inFlight ??= _load(week, epoch).whenComplete(() => _inFlight = null);
    });
  }

  void _show(WeeklyReport report, {bool fresh = false, bool persist = true}) {
    if (persist) _writeCache(report);
    state = WeeklyReportState(
      status: WeeklyReportStatus.ready,
      report: report,
      freshlyGenerated: fresh,
      seen: _wasSeen(report.week),
    );
  }

  Future<WeeklyReportVariant> _locked() async =>
      await _tier() == SubscriptionTier.gold
          ? WeeklyReportVariant.numbersUnavailable
          : WeeklyReportVariant.numbersLocked;

  String get _cachePrefix => 'weekly_report_cache_${_loadedFor ?? 'anon'}_';

  WeeklyReport? _readCache(ReportWeek week) {
    try {
      final raw = _prefs?.getString('$_cachePrefix${week.key}');
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final report = WeeklyReport.tryParse(json.cast<String, Object?>());
      return report?.week == week ? report : null;
    } catch (_) {
      return null;
    }
  }

  /// Solo se guarda la semana actual: las anteriores se borran.
  void _writeCache(WeeklyReport report) {
    final prefs = _prefs;
    if (prefs == null || _loadedFor == null) return;
    try {
      _clearCache(except: report.week);
      prefs.setString(
        '$_cachePrefix${report.week.key}',
        jsonEncode(report.toJson()),
      );
    } catch (_) {}
  }

  void _clearCache({ReportWeek? except}) {
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      final keep = except == null ? null : '$_cachePrefix${except.key}';
      for (final key in prefs.getKeys().toList()) {
        if (key.startsWith(_cachePrefix) && key != keep) prefs.remove(key);
      }
    } catch (_) {}
  }

  bool _wasSeen(ReportWeek week) {
    try {
      return _prefs?.getBool(_seenKey(week)) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Por usuario: en un teléfono compartido, que A lo haya visto no le
  /// saca la entrada animada a B.
  String _seenKey(ReportWeek week) =>
      'weekly_report_seen_${_loadedFor ?? 'anon'}_${week.key}';

  @override
  void dispose() {
    _retry?.cancel();
    super.dispose();
  }
}

/// Uno por sesión de usuario: se recrea al cambiar de cuenta (cerrar sesión
/// y entrar con otra no puede mostrar el informe de la anterior).
final weeklyReportControllerProvider =
    StateNotifierProvider<WeeklyReportController, WeeklyReportState>((ref) {
      ref.watch(authSessionProvider.select((s) => s.valueOrNull?.user.id));
      final controller = WeeklyReportController(
        store: ref.watch(weeklyReportRepositoryProvider),
        builder: WeeklyReportInputBuilder(
          quotes: ref.watch(quoteRepositoryProvider),
        ),
        generator: WeeklyReportGenerator(),
        tier: () => _loadedTier(ref),
        userId: () => ref.read(supabaseAuthServiceProvider).currentUser?.id,
        preferences: ref.watch(sharedPreferencesProvider),
      );
      SubscriptionTier? lastTier;
      ref.listen<SubscriptionState>(subscriptionProvider, (_, s) {
        if (s.isLoading) return;
        if (lastTier != null && lastTier != s.tier) controller.tierChanged();
        lastTier = s.tier;
      }, fireImmediately: true);
      return controller;
    });

/// El plan una vez cargada la suscripción. Mientras carga, el estado dice
/// `free` aunque el usuario sea Gold.
Future<SubscriptionTier> _loadedTier(Ref ref) async {
  final current = ref.read(subscriptionProvider);
  if (!current.isLoading) return current.tier;
  try {
    final loaded = await ref
        .read(subscriptionProvider.notifier)
        .stream
        .firstWhere((s) => !s.isLoading)
        .timeout(const Duration(seconds: 8));
    return loaded.tier;
  } catch (_) {
    return ref.read(subscriptionProvider).tier;
  }
}

/// Si el plan ve la comparación con el S&P 500 (Premium y Gold). Aparte,
/// para que la tarjeta y la pantalla no dependan de todo el estado de la
/// suscripción.
final weeklyReportBenchmarkAllowedProvider = Provider<bool>(
  (ref) => SubscriptionPolicy.isBenchmarkAllowed(
    ref.watch(subscriptionProvider.select((s) => s.tier)),
  ),
);

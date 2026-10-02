import 'dart:async';

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
class WeeklyReportController extends StateNotifier<WeeklyReportState> {
  WeeklyReportController({
    required WeeklyReportStore store,
    required WeeklyReportInputBuilder builder,
    required WeeklyReportGenerator generator,
    required SubscriptionTier Function() tier,
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
       super(const WeeklyReportState());

  final WeeklyReportStore _store;
  final WeeklyReportInputBuilder _builder;
  final WeeklyReportGenerator _generator;
  final SubscriptionTier Function() _tier;
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
    // Listo, o con un reintento ya agendado (otro dispositivo generando):
    // la Home llama esto en cada rebuild y no tiene que adelantar nada.
    if (sameWeek &&
        (state.status == WeeklyReportStatus.ready || _retry != null)) {
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

  void _resetFor(String? uid) {
    _epoch++;
    _loadedFor = uid;
    _retry?.cancel();
    _retry = null;
    _inFlight = null;
    _inProgressRetries = 0;
    _disabledWeek = null;
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

  Future<void> _load(ReportWeek week, int epoch) async {
    if (state.report?.week != week) {
      state = const WeeklyReportState(status: WeeklyReportStatus.loading);
    }
    final claim = await _store.claim(week);
    if (_stale(epoch)) return;
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
        state = const WeeklyReportState();
      case ClaimFailed():
        await _numbers(week, _locked(), epoch);
      case ClaimUnavailable():
        // Sin respuesta del servidor no se sabe si el informe está prendido
        // (ni si el backend existe): no hay tarjeta. Se reintenta en la
        // próxima apertura de la Home.
        state = const WeeklyReportState();
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

  void _show(WeeklyReport report, {bool fresh = false}) {
    state = WeeklyReportState(
      status: WeeklyReportStatus.ready,
      report: report,
      freshlyGenerated: fresh,
      seen: _wasSeen(report.week),
    );
  }

  WeeklyReportVariant _locked() =>
      _tier() == SubscriptionTier.gold
          ? WeeklyReportVariant.numbersUnavailable
          : WeeklyReportVariant.numbersLocked;

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
      return WeeklyReportController(
        store: ref.watch(weeklyReportRepositoryProvider),
        builder: WeeklyReportInputBuilder(
          quotes: ref.watch(quoteRepositoryProvider),
        ),
        generator: WeeklyReportGenerator(),
        tier: () => ref.read(subscriptionProvider).tier,
        userId: () => ref.read(supabaseAuthServiceProvider).currentUser?.id,
        preferences: ref.watch(sharedPreferencesProvider),
      );
    });

/// Si el plan ve la comparación con el S&P 500 (Premium y Gold). Aparte,
/// para que la tarjeta y la pantalla no dependan de todo el estado de la
/// suscripción.
final weeklyReportBenchmarkAllowedProvider = Provider<bool>(
  (ref) => SubscriptionPolicy.isBenchmarkAllowed(
    ref.watch(subscriptionProvider.select((s) => s.tier)),
  ),
);

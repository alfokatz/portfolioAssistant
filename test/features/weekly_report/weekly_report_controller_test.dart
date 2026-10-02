import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/networking/error/http_error.dart';
import 'package:portfolio_assistant/domain/entities/closed_position.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/price_candle.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/domain/repositories/quote_repository.dart';
import 'package:portfolio_assistant/features/genui_core/tool_calling/ai_proxy_client.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_generator.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_input_builder.dart';
import 'package:portfolio_assistant/features/weekly_report/data/weekly_report_repository.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/report_week.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_claim.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_draft.dart';
import 'package:portfolio_assistant/features/weekly_report/domain/weekly_report_input.dart';
import 'package:portfolio_assistant/features/weekly_report/providers/weekly_report_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'weekly_report_fixtures.dart';

/// Usuario de la sesión actual (los tests lo cambian para simular otra
/// cuenta).
var _currentUser = 'user-a';

/// Sábado 26/9: cubre la semana del 21 (la de los fixtures).
DateTime _saturday() => DateTime(2026, 9, 26, 10);

class _Store implements WeeklyReportStore {
  _Store(this.claims);

  /// Respuestas de `claim` en orden (la última se repite).
  final List<WeeklyReportClaim> claims;
  final completed = <Map<String, Object?>>[];
  var failed = 0;
  var claimCalls = 0;

  @override
  Future<WeeklyReportClaim> claim(ReportWeek week) async =>
      claims[(claimCalls++).clamp(0, claims.length - 1)];

  @override
  Future<bool> complete(ReportWeek week, Map<String, Object?> payload) async {
    completed.add(payload);
    return true;
  }

  @override
  Future<void> fail(ReportWeek week) async => failed++;
}

class _NoQuotes implements QuoteRepository {
  @override
  Future<Either<HttpError, double>> getCurrentPrice(String ticker) =>
      throw UnimplementedError();
  @override
  Future<Either<HttpError, List<PriceCandle>>> getHistoricalDaily(
    String ticker,
  ) => throw UnimplementedError();
  @override
  Future<List<PriceCandle>> getIntradayCandles(String ticker) =>
      throw UnimplementedError();
}

class _Builder extends WeeklyReportInputBuilder {
  _Builder() : super(quotes: _NoQuotes());
  final calls = <bool>[]; // numbersOnly de cada llamada

  @override
  Future<WeeklyReportInput> build({
    required ReportWeek week,
    required List<Position> lots,
    List<ClosedPosition> closed = const [],
    bool numbersOnly = false,
  }) async {
    calls.add(numbersOnly);
    return fixtureInput();
  }
}

class _Generator extends WeeklyReportGenerator {
  _Generator({this.error, this.gate})
    : super(
        config: AiProxyConfig.fixed(Uri.parse('https://x/ai-chat'), 'jwt'),
        model: 'gpt-4.1-mini',
      );
  final String? error;

  /// Si está, la generación espera a que se complete (para simular que
  /// Porty sigue escribiendo mientras cambia el usuario).
  final Future<void>? gate;
  var calls = 0;

  @override
  Future<WeeklyReportGeneration> generate({
    required ReportWeek week,
    required WeeklyReportInput input,
  }) async {
    calls++;
    await gate;
    if (error != null) {
      return WeeklyReportGeneration(
        draft: WeeklyReportDraft.empty,
        rounds: 1,
        remainingIssues: const [],
        error: error,
      );
    }
    return const WeeklyReportGeneration(
      draft: WeeklyReportDraft(
        headline: 'Apple empujó tu cartera',
        movers: [
          DraftMover(
            ticker: 'AAPL',
            why: 'Coincidió con las reservas del iPhone.',
            newsId: 'n1',
          ),
        ],
        news: [DraftNews(newsId: 'n2', take: 'Una investigación lleva meses.')],
        investors: [
          DraftInvestor(
            itemId: 'i2',
            take: 'Según CNBC, Ackman apuesta a MSFT.',
          ),
        ],
        learn: DraftLearn(
          topic: 'earnings',
          concept: 'Qué es un reporte de resultados',
          text: 'Es el informe trimestral de una empresa.',
        ),
        followUpQuestion: '¿Qué espera el mercado de MSFT?',
      ),
      rounds: 1,
      remainingIssues: [],
    );
  }
}

final _lots = [
  Position(
    id: '1',
    ticker: 'AAPL',
    quantity: 10,
    purchasePrice: 50,
    purchaseDate: DateTime(2026, 1, 5),
  ),
];

Future<
  ({WeeklyReportController c, _Store store, _Builder builder, _Generator gen})
>
_setup(
  List<WeeklyReportClaim> claims, {
  SubscriptionTier tier = SubscriptionTier.gold,
  String? generationError,
  Future<void>? gate,
  Duration retryDelay = const Duration(milliseconds: 10),
}) async {
  SharedPreferences.setMockInitialValues({});
  final store = _Store(claims);
  final builder = _Builder();
  final gen = _Generator(error: generationError, gate: gate);
  final c = WeeklyReportController(
    store: store,
    builder: builder,
    generator: gen,
    tier: () => tier,
    userId: () => _currentUser,
    preferences: await SharedPreferences.getInstance(),
    clock: _saturday,
    retryDelay: retryDelay,
  );
  return (c: c, store: store, builder: builder, gen: gen);
}

void main() {
  setUp(() => _currentUser = 'user-a');

  test(
    'claimed: builds the full input, Porty writes, the report is saved',
    () async {
      final s = await _setup([const ClaimGranted(courtesy: false, attempt: 1)]);
      await s.c.ensureFor(_lots);

      expect(s.builder.calls, [false]);
      expect(s.gen.calls, 1);
      expect(s.c.state.status, WeeklyReportStatus.ready);
      expect(s.c.state.freshlyGenerated, isTrue);
      final r = s.c.state.report!;
      expect(r.variant, WeeklyReportVariant.full);
      expect(r.headline, 'Apple empujó tu cartera');
      expect(r.movers.first.news!.source, 'Reuters');
      expect(r.news.single.url, 'https://news.google.com/n2');
      expect(r.investors.single.who, 'Bill Ackman');
      expect(s.store.completed.single['headline'], 'Apple empujó tu cartera');
    },
  );

  test(
    'ready: shows what was saved, without building or calling Porty',
    () async {
      final saved = WeeklyReport.compose(
        input: fixtureInput(),
        draft: const WeeklyReportDraft(
          headline: 'Guardado en otro dispositivo',
          movers: [],
          news: [],
          investors: [],
        ),
        variant: WeeklyReportVariant.full,
      );
      final s = await _setup([
        ClaimReady(payload: saved.toJson(), courtesy: false),
      ]);
      await s.c.ensureFor(_lots);

      expect(s.builder.calls, isEmpty);
      expect(s.gen.calls, 0);
      expect(s.c.state.report!.headline, 'Guardado en otro dispositivo');
      expect(s.c.state.freshlyGenerated, isFalse);
    },
  );

  test(
    'numbers only (no Gold, tasting used): no news, no LLM, Gold teaser',
    () async {
      final s = await _setup([
        const ClaimNumbersOnly(),
      ], tier: SubscriptionTier.free);
      await s.c.ensureFor(_lots);

      expect(s.builder.calls, [true]);
      expect(s.gen.calls, 0);
      expect(s.c.state.report!.variant, WeeklyReportVariant.numbersLocked);
      expect(s.c.state.report!.hasProse, isFalse);
      expect(s.c.state.report!.movers, isNotEmpty);
    },
  );

  test(
    'a failed generation releases the claim and still shows the numbers',
    () async {
      final s = await _setup([
        const ClaimGranted(courtesy: false, attempt: 1),
      ], generationError: 'http_500');
      await s.c.ensureFor(_lots);

      expect(s.store.failed, 1);
      expect(s.store.completed, isEmpty);
      expect(s.c.state.report!.variant, WeeklyReportVariant.numbersUnavailable);
    },
  );

  test(
    'in progress elsewhere: numbers now, then picks up the saved report',
    () async {
      final saved = WeeklyReport.compose(
        input: fixtureInput(),
        draft: const WeeklyReportDraft(
          headline: 'Lo escribió el otro teléfono',
          movers: [],
          news: [],
          investors: [],
        ),
        variant: WeeklyReportVariant.full,
      );
      final s = await _setup([
        const ClaimInProgress(),
        ClaimReady(payload: saved.toJson(), courtesy: false),
      ]);
      await s.c.ensureFor(_lots);
      expect(s.c.state.report!.hasProse, isFalse);

      // Rebuilds de la Home mientras espera: no adelantan el reintento.
      await s.c.ensureFor(_lots);
      expect(s.store.claimCalls, 1);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.store.claimCalls, 2);
      expect(s.c.state.report!.headline, 'Lo escribió el otro teléfono');
    },
  );

  test('unavailable server (or backend not deployed yet): no card', () async {
    final s = await _setup([const ClaimUnavailable()]);
    await s.c.ensureFor(_lots);
    expect(s.c.state.status, WeeklyReportStatus.hidden);
    expect(s.builder.calls, isEmpty);
  });

  test('a failed claim (attempts used up): Gold sees plain numbers, Free '
      'sees the teaser', () async {
    final gold = await _setup([const ClaimFailed()]);
    await gold.c.ensureFor(_lots);
    expect(
      gold.c.state.report!.variant,
      WeeklyReportVariant.numbersUnavailable,
    );

    final free = await _setup([
      const ClaimFailed(),
    ], tier: SubscriptionTier.free);
    await free.c.ensureFor(_lots);
    expect(free.c.state.report!.variant, WeeklyReportVariant.numbersLocked);
  });

  test('no positions: hidden, and nothing is claimed', () async {
    final s = await _setup([const ClaimGranted(courtesy: false, attempt: 1)]);
    await s.c.ensureFor(const []);
    expect(s.c.state.status, WeeklyReportStatus.hidden);
    expect(s.store.claimCalls, 0);
  });

  test('calling again the same week does nothing', () async {
    final s = await _setup([const ClaimGranted(courtesy: false, attempt: 1)]);
    await s.c.ensureFor(_lots);
    await s.c.ensureFor(_lots);
    expect(s.store.claimCalls, 1);
    expect(s.gen.calls, 1);
  });

  test('seen is remembered per week', () async {
    final s = await _setup([const ClaimNumbersOnly()]);
    await s.c.ensureFor(_lots);
    expect(s.c.state.seen, isFalse);
    s.c.markSeen();
    expect(s.c.state.seen, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('weekly_report_seen_user-a_2026-09-21'), isTrue);
  });

  test('the stored payload round-trips', () {
    final report = WeeklyReport.compose(
      input: fixtureInput(),
      draft: const WeeklyReportDraft(
        headline: 'h',
        movers: [DraftMover(ticker: 'AAPL', why: 'w', newsId: 'n1')],
        news: [DraftNews(newsId: 'n2', take: 't')],
        investors: [DraftInvestor(itemId: 'i1', take: 'Berkshire informó.')],
        learn: DraftLearn(topic: 'earnings', concept: 'c', text: 'x'),
        followUpQuestion: 'q',
        closing: 'cl',
      ),
      variant: WeeklyReportVariant.full,
      courtesy: true,
    );
    final back = WeeklyReport.tryParse(report.toJson())!;
    expect(back.toJson(), report.toJson());
    expect(back.courtesy, isTrue);
    expect(back.investors.single.isFiling, isTrue);
    expect(WeeklyReport.tryParse({'v': 99}), isNull);
  });

  test('the locked variant never carries Gold data', () {
    final locked = WeeklyReport.compose(
      input: fixtureInput(),
      draft: const WeeklyReportDraft(
        headline: null,
        movers: [],
        news: [DraftNews(newsId: 'n1', take: 't')],
        investors: [DraftInvestor(itemId: 'i2', take: 't')],
      ),
      variant: WeeklyReportVariant.numbersLocked,
    );
    expect(locked.upcomingEarnings, isEmpty);
    expect(locked.news, isEmpty);
    expect(locked.investors, isEmpty);
    expect(locked.movers, isNotEmpty);
  });

  test(
    'disabled from the server: no card, and Home rebuilds do not ask again',
    () async {
      final s = await _setup([const ClaimDisabled()]);
      await s.c.ensureFor(_lots);
      expect(s.c.state.status, WeeklyReportStatus.hidden);
      await s.c.ensureFor(_lots);
      expect(s.store.claimCalls, 1);
      expect(s.builder.calls, isEmpty);
    },
  );

  group('switching accounts (bug 2026-10-02)', () {
    test('B never sees the report of A', () async {
      final s = await _setup([
        const ClaimGranted(courtesy: false, attempt: 1),
        const ClaimNumbersOnly(),
      ]);
      await s.c.ensureFor(_lots);
      expect(s.c.state.report!.headline, 'Apple empujó tu cartera');

      // A cierra sesión y entra B.
      _currentUser = 'user-b';
      final pending = s.c.ensureFor(_lots);
      expect(s.c.state.report, isNull, reason: 'el de A se descarta ya');
      await pending;
      expect(s.store.claimCalls, 2);
      expect(s.c.state.report!.variant, WeeklyReportVariant.numbersLocked);
      expect(s.c.state.report!.headline, isNull);
    });

    test(
      'a generation of A that finishes after B logged in is dropped',
      () async {
        final gate = Completer<void>();
        final s = await _setup([
          const ClaimGranted(courtesy: false, attempt: 1),
          const ClaimNumbersOnly(),
        ], gate: gate.future);
        final forA = s.c.ensureFor(_lots); // Porty escribe para A…

        await Future<void>.delayed(Duration.zero);
        _currentUser = 'user-b';
        await s.c.ensureFor(_lots); // …y B entra antes de que termine
        expect(s.c.state.report!.variant, WeeklyReportVariant.numbersLocked);

        gate.complete();
        await forA;
        expect(s.c.state.report!.variant, WeeklyReportVariant.numbersLocked);
        expect(s.c.state.report!.headline, isNull);
        // Tampoco se guarda: la sesión ya es de B, y `complete` con el token
        // de B podría escribir los datos de A en la fila de B. La reserva de
        // A vence sola y A lo regenera al volver a entrar.
        expect(s.store.completed, isEmpty);
        expect(s.store.failed, 0);
      },
    );

    test('signed out: no card and nothing is claimed', () async {
      final s = await _setup([const ClaimGranted(courtesy: false, attempt: 1)]);
      final c = WeeklyReportController(
        store: s.store,
        builder: s.builder,
        generator: s.gen,
        tier: () => SubscriptionTier.gold,
        userId: () => null,
        clock: _saturday,
      );
      await c.ensureFor(_lots);
      expect(c.state.status, WeeklyReportStatus.hidden);
      expect(s.store.claimCalls, 0);
    });

    test('"seen" is per user', () async {
      final s = await _setup([const ClaimNumbersOnly()]);
      await s.c.ensureFor(_lots);
      s.c.markSeen();
      _currentUser = 'user-b';
      await s.c.ensureFor(_lots);
      expect(s.c.state.seen, isFalse);
    });
  });
}

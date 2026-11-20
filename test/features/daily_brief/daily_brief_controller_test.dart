// Controlador del brief: claim → generar → guardar, por plan y por estado
// del servidor. Sin red ni LLM real. Correr:
// flutter test test/features/daily_brief/daily_brief_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_day_move.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_numbers_loader.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_repository.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_bundle.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_writer.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/daily_brief_fakes.dart';

var _user = 'user-a';

DailyBriefController _controller(
  FakeDailyBriefStore store,
  FakeDailyBriefWriter writer, {
  SharedPreferences? prefs,
  List<(ProductEvent, Map<String, Object?>)>? events,
  DateTime Function()? clock,
}) => DailyBriefController(
  store: store,
  numbers: DailyBriefNumbersLoader(quotes: FakeQuotes()),
  writer: writer,
  userId: () => _user,
  preferences: prefs,
  clock: clock ?? briefNow,
  language: () => 'es',
  logEvent: (e, p) => events?.add((e, p)),
  retryDelay: const Duration(milliseconds: 10),
);

void main() {
  setUp(() => _user = 'user-a');

  group('with the switch off', () {
    test('hidden, and nothing else is asked of the server', () async {
      final store = FakeDailyBriefStore(
        statusResult: DailyBriefStatus.off,
        claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
      );
      final writer = FakeDailyBriefWriter();
      final c = _controller(store, writer);
      await c.ensureFor(history(), lots);
      expect(c.state.phase, DailyBriefPhase.hidden);
      expect(store.claimCalls, 0);
      expect(store.bundleCalls, isEmpty);
      expect(writer.requests, isEmpty);
      // Y no vuelve a preguntar en cada rebuild de la Home.
      await c.ensureFor(history(), lots);
      expect(store.statusCalls, 1);
    });

    test('claim disabled also hides it', () async {
      final store = FakeDailyBriefStore(claims: const [BriefClaimDisabled()]);
      final c = _controller(store, FakeDailyBriefWriter());
      await c.ensureFor(history(), lots);
      expect(c.state.phase, DailyBriefPhase.hidden);
    });
  });

  group('hidden states', () {
    for (final claim in <DailyBriefClaim>[
      const BriefClaimNoPortfolio(),
      const BriefClaimNotBusinessDay(),
      const BriefClaimUnavailable(),
    ]) {
      test('${claim.runtimeType} shows no row', () async {
        final c = _controller(
          FakeDailyBriefStore(claims: [claim]),
          FakeDailyBriefWriter(),
        );
        await c.ensureFor(history(), lots);
        expect(c.state.phase, DailyBriefPhase.hidden);
        expect(c.state.brief, isNull);
      });
    }

    test('no positions or no history: hidden without asking', () async {
      final store = FakeDailyBriefStore();
      final c = _controller(store, FakeDailyBriefWriter());
      await c.ensureFor(history(), const []);
      await c.ensureFor(const [], lots);
      expect(c.state.phase, DailyBriefPhase.hidden);
      expect(store.statusCalls, 0);
    });
  });

  group('Free (numbers_only)', () {
    test('never calls the generator; saves a numbers payload with a teaser', () async {
      final store = FakeDailyBriefStore(); // numbers_only + bundle numbers
      final writer = FakeDailyBriefWriter();
      final c = _controller(store, writer);
      await c.ensureFor(history(), lots);

      expect(writer.requests, isEmpty);
      expect(c.state.phase, DailyBriefPhase.ready);
      final brief = c.state.brief!;
      expect(brief.variant, DailyBriefVariant.numbers);
      expect(brief.day, briefDay);
      expect(brief.market, hasLength(1));
      expect(brief.market.single.connection, isNull);
      expect(brief.teaser?.requiredPlan, 'premium');
      expect(store.completed.single['variant'], 'numbers');
      expect(store.completed.single['teaser'], isNotNull);
      expect(store.completed.single['why'], isEmpty);
    });

    test('without the news server it still shows the numbers', () async {
      final store = FakeDailyBriefStore(
        bundleError: const DailyBriefNetworkFailure(),
      );
      final c = _controller(store, FakeDailyBriefWriter());
      await c.ensureFor(history(), lots);
      expect(c.state.phase, DailyBriefPhase.ready);
      expect(c.state.brief!.market, isEmpty);
    });
  });

  group('full (claimed)', () {
    test('Porty writes, it is saved and the event is logged', () async {
      final store = FakeDailyBriefStore(
        claims: const [
          BriefClaimGranted(
            courtesy: true,
            attempt: 1,
            courtesyNumber: 2,
            courtesyTotal: 7,
          ),
        ],
        bundleBody: bundleFixture('bundle_brief_full'),
      );
      final writer = FakeDailyBriefWriter();
      final events = <(ProductEvent, Map<String, Object?>)>[];
      final c = _controller(store, writer, events: events);
      await c.ensureFor(history(), lots);

      final brief = c.state.brief!;
      expect(brief.variant, DailyBriefVariant.full);
      expect(brief.courtesy, isTrue);
      expect(brief.courtesyNumber, 2);
      expect(brief.why.single.newsId, 'h1');
      expect(brief.teaser, isNull);
      expect(c.state.freshlyGenerated, isTrue);
      // Se le dio a Porty lo que trajo el servidor, con las clases de activo.
      expect(writer.requests.single.held.map((h) => h.id), ['h1', 'h2', 'h3']);
      expect(writer.requests.single.assetClasses, {'equity', 'bond'});
      expect(writer.requests.single.language, 'es');
      expect(store.completed.single['variant'], 'full');
      final generated = events.singleWhere(
        (e) => e.$1 == ProductEvent.dailyBriefGenerated,
      );
      expect(generated.$2['variant'], 'full');
      expect(generated.$2['rounds'], 1);
      // AAPL y NVDA con noticias, de 2 tickers en cartera.
      expect(generated.$2['held_with_news_pct'], 100);
      expect(generated.$2, isNot(contains('error')));
    });

    test('the numbers are the ones of the Home', () async {
      final store = FakeDailyBriefStore(
        claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
        bundleBody: bundleFixture('bundle_brief_full'),
      );
      final c = _controller(store, FakeDailyBriefWriter());
      await c.ensureFor(history(), lots);
      final n = c.state.brief!.numbers;
      final home = PortfolioDayMove.compute(history: history(), now: briefNow());
      expect(n.pct, home.percent);
      expect(n.abs, home.absolute);
      expect(n.movers.first.ticker, 'NVDA');
      expect(n.asOfDay, DateTime(2026, 11, 25));
    });

    test('generator fails: the claim is released and numbers are shown without a teaser', () async {
      final store = FakeDailyBriefStore(
        claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
        bundleBody: bundleFixture('bundle_brief_full'),
      );
      final writer = FakeDailyBriefWriter(
        writing: const DailyBriefWriting(
          prose: DailyBriefProse.empty,
          rounds: 1,
          error: 'http_500',
        ),
      );
      final events = <(ProductEvent, Map<String, Object?>)>[];
      final c = _controller(store, writer, events: events);
      await c.ensureFor(history(), lots);

      expect(store.failCalls, 1);
      expect(store.completed, isEmpty);
      expect(c.state.brief!.variant, DailyBriefVariant.numbers);
      expect(c.state.brief!.teaser, isNull);
      expect(
        events.single.$2,
        containsPair('error', 'http_500'),
      );
    });

    test('news server down: claim released, no LLM call', () async {
      final store = FakeDailyBriefStore(
        claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
        bundleError: const DailyBriefServerFailure(500),
      );
      final writer = FakeDailyBriefWriter();
      final c = _controller(store, writer);
      await c.ensureFor(history(), lots);
      expect(writer.requests, isEmpty);
      expect(store.failCalls, 1);
      expect(c.state.phase, DailyBriefPhase.ready);
      expect(c.state.brief!.variant, DailyBriefVariant.numbers);
    });

    test('a full brief of the day is not asked again', () async {
      final store = FakeDailyBriefStore(
        claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
        bundleBody: bundleFixture('bundle_brief_full'),
      );
      final c = _controller(store, FakeDailyBriefWriter());
      await c.ensureFor(history(), lots);
      await c.ensureFor(history(), lots);
      expect(store.claimCalls, 1);
    });
  });

  group('server states', () {
    test('ready shows what was saved, courtesy included', () async {
      final saved =
          DailyBrief.compose(
            day: briefDay,
            lang: 'es',
            now: briefNow(),
            numbers: (await DailyBriefNumbersLoader(quotes: FakeQuotes()).load(
              history: history(),
              lots: lots,
            )),
            bundle: DailyBriefBundle.parse(bundleFixture('bundle_brief_full')),
            variant: DailyBriefVariant.full,
          ).toJson();
      final store = FakeDailyBriefStore(
        claims: [BriefClaimReady(payload: saved, courtesy: true)],
      );
      final writer = FakeDailyBriefWriter();
      final c = _controller(store, writer);
      await c.ensureFor(history(), lots);
      expect(c.state.brief!.variant, DailyBriefVariant.full);
      expect(c.state.brief!.courtesy, isTrue);
      expect(writer.requests, isEmpty);
      expect(store.completed, isEmpty);
    });

    test('ready with a payload of another version: numbers are recomputed', () async {
      final store = FakeDailyBriefStore(
        claims: [
          const BriefClaimReady(payload: {'v': 99}, courtesy: false),
        ],
      );
      final c = _controller(store, FakeDailyBriefWriter());
      await c.ensureFor(history(), lots);
      expect(c.state.brief!.variant, DailyBriefVariant.numbers);
      expect(c.state.brief!.teaser, isNull);
      expect(store.completed, isEmpty);
    });

    test('in_progress shows the numbers and asks again later', () async {
      final store = FakeDailyBriefStore(
        claims: [
          const BriefClaimInProgress(),
          const BriefClaimInProgress(),
          const BriefClaimInProgress(),
          const BriefClaimInProgress(),
        ],
      );
      final c = _controller(store, FakeDailyBriefWriter());
      await c.ensureFor(history(), lots);
      expect(c.state.phase, DailyBriefPhase.ready);
      expect(store.completed, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      // Preguntó de nuevo, y se detiene en el tope de reintentos.
      expect(store.claimCalls, 1 + DailyBriefController.maxInProgressRetries);
      c.dispose();
    });

    test('failed (attempts exhausted) shows numbers only', () async {
      final c = _controller(
        FakeDailyBriefStore(claims: const [BriefClaimFailed()]),
        FakeDailyBriefWriter(),
      );
      await c.ensureFor(history(), lots);
      expect(c.state.brief!.variant, DailyBriefVariant.numbers);
      expect(c.state.brief!.teaser, isNull);
    });
  });

  group('device cache and holidays', () {
    test('a full brief is cached and shown before asking the server', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FakeDailyBriefStore(
        claims: const [
          BriefClaimGranted(courtesy: true, attempt: 1, courtesyNumber: 1, courtesyTotal: 7),
        ],
        bundleBody: bundleFixture('bundle_brief_full'),
      );
      await (_controller(store, FakeDailyBriefWriter(), prefs: prefs))
          .ensureFor(history(), lots);

      final second = FakeDailyBriefStore();
      final c = _controller(second, FakeDailyBriefWriter(), prefs: prefs);
      // Antes de cualquier llamada: ya hay brief.
      expect(c.state.phase, DailyBriefPhase.ready);
      expect(c.state.brief!.courtesyNumber, 1);
      await c.ensureFor(history(), lots);
      expect(second.statusCalls, 0);
    });

    test('another account never sees the cached brief', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FakeDailyBriefStore(
        claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
        bundleBody: bundleFixture('bundle_brief_full'),
      );
      await (_controller(store, FakeDailyBriefWriter(), prefs: prefs))
          .ensureFor(history(), lots);
      _user = 'user-b';
      final c = _controller(FakeDailyBriefStore(), FakeDailyBriefWriter(), prefs: prefs);
      expect(c.state.brief, isNull);
    });

    test('same close as the last brief of another day: no brief (holiday)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = FakeDailyBriefStore(
        claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
        bundleBody: bundleFixture('bundle_brief_full'),
      );
      // El jueves cubre el cierre del miércoles…
      await (_controller(store, FakeDailyBriefWriter(), prefs: prefs))
          .ensureFor(history(), lots);
      // …y el viernes, con el mismo último cierre (feriado), no hay brief.
      final friday = FakeDailyBriefStore();
      final c = _controller(
        friday,
        FakeDailyBriefWriter(),
        prefs: prefs,
        clock: () => DateTime(2026, 11, 27, 8),
      );
      await c.ensureFor(history(), lots);
      expect(c.state.phase, DailyBriefPhase.hidden);
      expect(friday.claimCalls, 0);
    });
  });
}

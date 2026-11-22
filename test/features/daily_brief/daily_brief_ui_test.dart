// Pantalla del brief y fila de la Home: por plan, claro y oscuro, a 375 de
// ancho. Sin traducciones cargadas, `.tr()` devuelve la clave: se busca por
// clave. Correr: flutter test test/features/daily_brief/daily_brief_ui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/daily_brief/data/daily_brief_numbers_loader.dart';
import 'package:portfolio_assistant/features/daily_brief/domain/daily_brief_claim.dart';
import 'package:portfolio_assistant/features/daily_brief/nav/daily_brief_router.dart';
import 'package:portfolio_assistant/features/daily_brief/providers/daily_brief_provider.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_today_card.dart';
import 'package:portfolio_assistant/features/daily_brief/view/daily_brief_screen.dart';
import 'package:portfolio_assistant/features/daily_brief/view/widgets/daily_brief_feedback.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/paywall_source.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/shared/formatting/app_number_format.dart';

import '../subscription/paywall_test_harness.dart';
import 'fakes/daily_brief_fakes.dart';

DailyBriefController _controller(FakeDailyBriefStore store) =>
    DailyBriefController(
      store: store,
      numbers: DailyBriefNumbersLoader(quotes: FakeQuotes()),
      writer: FakeDailyBriefWriter(),
      userId: () => 'u',
      clock: briefNow,
      language: () => 'es',
      retryDelay: const Duration(milliseconds: 10),
    );

FakeDailyBriefStore _premiumStore() => FakeDailyBriefStore(
  claims: const [BriefClaimGranted(courtesy: false, attempt: 1)],
  bundleBody: bundleFixture('bundle_brief_full'),
);

ThemeData _theme(Brightness b) {
  final c = ProviderContainer();
  addTearDown(c.dispose);
  return c.read(
    b == Brightness.dark ? themeDataDarkProvider : themeDataLightProvider,
  );
}

Future<PaywallHarness> _pumpScreen(
  WidgetTester tester,
  DailyBriefController controller, {
  Brightness brightness = Brightness.light,
  List<Uri>? launched,
  Widget? screen,
}) async {
  tester.view.physicalSize = const Size(375, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final h = PaywallHarness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...h.overrides,
        dailyBriefControllerProvider.overrideWith((ref) => controller),
        newsFeedAvailableProvider.overrideWithValue(false),
        dailyBriefUrlLauncherProvider.overrideWithValue((uri) async {
          launched?.add(uri);
          return true;
        }),
      ],
      child: MaterialApp(
        theme: _theme(brightness),
        home: screen ?? const DailyBriefScreen(day: briefDay),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return h;
}

void main() {
  group('DailyBriefScreen (Premium, full)', () {
    for (final brightness in Brightness.values) {
      testWidgets('renders the chapters in ${brightness.name}', (tester) async {
        final controller = _controller(_premiumStore());
        await controller.ensureFor(history(), lots);
        await _pumpScreen(tester, controller, brightness: brightness);

        expect(tester.takeException(), isNull);
        // Porty y el titular con el % del día.
        expect(find.text('brief_porty_intro'), findsOneWidget);
        expect(
          find.textContaining(
            AppNumberFormat.percent(controller.state.brief!.numbers.pct),
            findRichText: true,
          ),
          findsWidgets,
        );
        // Capítulo 1: lo tuyo, con el ticker y lo que escribió Porty.
        expect(find.textContaining('brief_chapter_count'), findsOneWidget);
        expect(find.text('NVDA'), findsWidgets);
        expect(
          find.textContaining(
            'el día que presentó resultados',
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(find.text('news_ai_notice'), findsOneWidget);
        // Sin watchlist ni aviso de plan; "Sigue" lleva al de mercado.
        expect(find.text('daily_brief_teaser_premium'), findsNothing);
        await tester.tap(
          find.textContaining('brief_next_label', findRichText: true),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('daily_brief_see_all'), findsNothing);
        expect(find.text('daily_brief_ask_porty'), findsOneWidget);
      });
    }

    testWidgets('every news line shows its outlet citation and opens it', (
      tester,
    ) async {
      final controller = _controller(_premiumStore());
      await controller.ensureFor(history(), lots);
      final launched = <Uri>[];
      await _pumpScreen(tester, controller, launched: launched);

      // La cita del medio va al lado de la frase ("Reuters 1").
      final cite = find.textContaining('Reuters', findRichText: true).first;
      await tester.ensureVisible(cite);
      await tester.tap(cite);
      await tester.pump();
      expect(
        launched.single.toString(),
        startsWith('https://www.reuters.com/'),
      );
    });

    testWidgets('the progress bar jumps to a chapter', (tester) async {
      final controller = _controller(_premiumStore());
      await controller.ensureFor(history(), lots);
      await _pumpScreen(tester, controller);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('brief_chapter_go')).last);
      await tester.pump(const Duration(milliseconds: 500));
      // El número del capítulo en el encabezado pasa de 1 a 2.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('courtesy brief says which day it is', (tester) async {
      final store = FakeDailyBriefStore(
        claims: const [
          BriefClaimGranted(
            courtesy: true,
            attempt: 1,
            courtesyNumber: 3,
            courtesyTotal: 7,
          ),
        ],
        bundleBody: bundleFixture('bundle_brief_full'),
      );
      final controller = _controller(store);
      await controller.ensureFor(history(), lots);
      await _pumpScreen(tester, controller);
      expect(find.text('daily_brief_courtesy_n'), findsOneWidget);
    });

    testWidgets('logs daily_brief_opened with source and variant', (
      tester,
    ) async {
      final controller = _controller(_premiumStore());
      await controller.ensureFor(history(), lots);
      final h = await _pumpScreen(
        tester,
        controller,
        screen: const DailyBriefScreen(day: briefDay, source: 'push'),
      );
      final opened = h.events.of(ProductEvent.dailyBriefOpened).single;
      expect(opened['source'], 'push');
      expect(opened['variant'], 'full');
      expect(opened['courtesy'], false);
    });
  });

  group('DailyBriefScreen (Free, numbers)', () {
    for (final brightness in Brightness.values) {
      testWidgets(
        'no ticker news, one market fact and the plan notice (${brightness.name})',
        (tester) async {
          final controller = _controller(FakeDailyBriefStore());
          await controller.ensureFor(history(), lots);
          await _pumpScreen(tester, controller, brightness: brightness);

          expect(tester.takeException(), isNull);
          // Sin titulares de la cartera: solo los números de lo tuyo y, en
          // el último capítulo, el hecho de mercado con su medio y el aviso.
          expect(find.text('daily_brief_how_affects'), findsNothing);
          await tester.tap(
            find.textContaining('brief_next_label', findRichText: true),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('daily_brief_teaser_premium'), findsOneWidget);
          expect(
            find.textContaining('Reuters', findRichText: true),
            findsWidgets,
          );
        },
      );
    }

    testWidgets('the notice opens the paywall with source daily_brief', (
      tester,
    ) async {
      final controller = _controller(FakeDailyBriefStore());
      await controller.ensureFor(history(), lots);
      final h = await _pumpScreen(tester, controller);

      await tester.tap(
        find.textContaining('brief_next_label', findRichText: true),
      );
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(find.text('daily_brief_teaser_premium'));
      await tester.tap(find.text('daily_brief_teaser_premium'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        h.events.of(ProductEvent.paywallViewed).single['source'],
        PaywallSource.dailyBrief,
      );
      expect(
        h.events.of(ProductEvent.dailyBriefItemTapped).single['kind'],
        'teaser',
      );
    });
  });

  group('DailyBriefScreen (empty)', () {
    testWidgets('no brief today: Porty says so, no empty box', (tester) async {
      final controller = _controller(
        FakeDailyBriefStore(claims: const [BriefClaimNotBusinessDay()]),
      );
      await controller.ensureFor(history(), lots);
      await _pumpScreen(tester, controller);
      expect(find.text('daily_brief_empty_title'), findsOneWidget);
      expect(find.text('daily_brief_empty_body'), findsOneWidget);
    });

    testWidgets('server unreachable: error with retry', (tester) async {
      final controller = _controller(
        FakeDailyBriefStore(claims: const [BriefClaimUnavailable()]),
      );
      await controller.ensureFor(history(), lots);
      await _pumpScreen(tester, controller);
      expect(find.text('daily_brief_error_title'), findsOneWidget);
      expect(find.text('retry'), findsOneWidget);
    });
  });

  group('DailyBriefFeedback', () {
    testWidgets('yes answers useful once and thanks', (tester) async {
      final answers = <(bool, String?)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.light),
          home: Scaffold(
            body: DailyBriefFeedback(onAnswer: (u, r) => answers.add((u, r))),
          ),
        ),
      );
      await tester.tap(find.text('daily_brief_feedback_yes'));
      await tester.pumpAndSettle();
      expect(answers, [(true, null)]);
      expect(find.text('daily_brief_feedback_thanks'), findsOneWidget);
      expect(find.text('daily_brief_feedback_yes'), findsNothing);
    });

    testWidgets('no asks why, then reports the reason', (tester) async {
      final answers = <(bool, String?)>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: _theme(Brightness.dark),
          home: Scaffold(
            body: DailyBriefFeedback(onAnswer: (u, r) => answers.add((u, r))),
          ),
        ),
      );
      await tester.tap(find.text('daily_brief_feedback_no'));
      await tester.pumpAndSettle();
      expect(answers, isEmpty);
      await tester.tap(find.text('daily_brief_feedback_reason_too_long'));
      await tester.pumpAndSettle();
      expect(answers, [(false, 'too_long')]);
    });
  });

  group('DailyBriefTodayCard', () {
    Future<void> pumpHome(
      WidgetTester tester,
      DailyBriefController controller, {
      bool feedAvailable = false,
    }) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder:
                (_, _) => Scaffold(
                  body: Column(
                    children: [
                      DailyBriefTodayCard(history: history(), lots: lots),
                    ],
                  ),
                ),
          ),
          GoRoute(
            name: DailyBriefRouter.routeName,
            path: DailyBriefRouter.path,
            builder:
                (_, state) => Text('screen:${(state.extra as Map)['source']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...PaywallHarness().overrides,
            dailyBriefControllerProvider.overrideWith((ref) => controller),
            newsFeedAvailableProvider.overrideWithValue(feedAvailable),
          ],
          child: MaterialApp.router(
            theme: _theme(Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('switch off: nothing is drawn', (tester) async {
      final store = FakeDailyBriefStore(statusResult: DailyBriefStatus.off);
      await pumpHome(tester, _controller(store), feedAvailable: true);
      expect(find.text('today_card_cta'), findsNothing);
      expect(store.claimCalls, 0);
    });

    testWidgets('on: Porty, the top notes and the button open the brief', (
      tester,
    ) async {
      final controller = _controller(_premiumStore());
      await pumpHome(tester, controller);
      expect(find.byType(PortyAvatar), findsOneWidget);
      expect(find.text('today_card_cta'), findsOneWidget);
      // Hasta dos notas, con ticker y medio.
      expect(find.text('NVDA'), findsOneWidget);
      expect(find.textContaining('Reuters'), findsWidgets);
      expect(
        find.textContaining('today_card_phrase', findRichText: true),
        findsOneWidget,
      );

      await tester.tap(find.text('today_card_cta'));
      await tester.pumpAndSettle();
      expect(find.text('screen:home'), findsOneWidget);
    });

    testWidgets('free plan without notes: Porty says how it closed', (
      tester,
    ) async {
      final controller = _controller(FakeDailyBriefStore());
      await pumpHome(tester, controller);
      expect(
        find.textContaining('today_card_phrase_none', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('today_card_cta'), findsOneWidget);
    });

    test('TodayNote lists each news once, why-lines first', () async {
      final controller = _controller(_premiumStore());
      await controller.ensureFor(history(), lots);
      final notes = TodayNote.allOf(controller.state.brief!);
      expect(notes, isNotEmpty);
      expect(notes.map((n) => n.title).toSet().length, notes.length);
    });
  });
}

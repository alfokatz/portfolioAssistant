import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/portfolio_summary.dart';
import 'package:portfolio_assistant/domain/entities/position.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/broker_connect/nav/connect_broker_router.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/features/subscription/config/conversion_flags.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/subscription/services/paywall_offer.dart';
import 'package:portfolio_assistant/domain/utils/portfolio_calculator.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/domain/portfolio_diagnosis.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/portfolio_diagnosis_screen.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/view/widgets/diagnosis_entry_card.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/providers/home_provider.dart';
import 'package:portfolio_assistant/presentation/flows/home/states/home_state.dart';

import '../subscription/paywall_test_harness.dart' show FakeProductEvents;

ThemeData get _light => ProviderContainer().read(themeDataLightProvider);

const _diagnosis = PortfolioDiagnosis(
  findings: [
    DiagnosisFinding(
      kind: DiagnosisKind.overlap,
      tone: DiagnosisTone.attention,
      score: 70,
      ticker: 'NVDA',
      via: ['QQQ', 'VOO'],
      numbers: {'total': 17, 'direct': 10},
    ),
    DiagnosisFinding(
      kind: DiagnosisKind.topHolding,
      tone: DiagnosisTone.attention,
      score: 40,
      ticker: 'VOO',
      numbers: {'pct': 50},
    ),
  ],
  positions: 3,
  funds: 2,
);

class _Seen extends DiagnosisSeenNotifier {
  _Seen(bool seen) : super(null, null) {
    state = seen;
  }
  int marks = 0;

  @override
  Future<void> markSeen() async {
    marks++;
    state = true;
  }
}

class _Home extends StateNotifier<HomeState> implements HomeProvider {
  _Home(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sub extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Sub(SubscriptionTier tier)
    : super(SubscriptionState(tier: tier, queriesUsed: 0, queriesLimit: 20));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Push extends StateNotifier<PushState> implements PushController {
  _Push(PushPermission permission)
    : super(PushState(permission: permission, loaded: true));

  @override
  Future<void> refreshPermission() async {}

  @override
  Future<PushPermission> requestPermission() async {
    state = state.copyWith(permission: PushPermission.granted);
    return PushPermission.granted;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

HomeState _homeWith(int positions, {PositionSource? source}) => HomeState(
  loading: false,
  summary: PortfolioSummary(
    totalValue: 1000.0 * positions,
    totalCostBasis: 1000.0 * positions,
    totalPnlAbsolute: 0,
    totalPnlPercent: 0,
    valuations: [
      for (var i = 0; i < positions; i++)
        PortfolioCalculator.valuate(
          position: Position(
            id: '$i',
            ticker: 'T$i',
            quantity: 1,
            purchasePrice: 1000,
            purchaseDate: DateTime(2025),
            source: i == 0 && source != null ? source : PositionSource.manual,
          ),
          currentPrice: 1000,
        ),
    ],
  ),
);

void main() {
  setUp(() => PortyAvatar.ambientMotion = false);
  tearDown(() => PortyAvatar.ambientMotion = true);

  Future<_Seen> pump(
    WidgetTester tester,
    Future<PortfolioDiagnosis> Function() load,
  ) async {
    final seen = _Seen(false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          portfolioDiagnosisProvider.overrideWith((ref) => load()),
          diagnosisSeenProvider.overrideWith((ref) => seen),
        ],
        child: MaterialApp(
          theme: _light,
          home: const PortfolioDiagnosisScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return seen;
  }

  testWidgets('muestra lo que vio, deja preguntas y lo marca como visto', (
    tester,
  ) async {
    final seen = await pump(tester, () async => _diagnosis);
    expect(find.text('diagnosis_porty_many'), findsOneWidget);
    expect(find.text('diagnosis_overlap_title'), findsOneWidget);
    expect(find.text('diagnosis_top_title'), findsOneWidget);
    expect(find.text('diagnosis_overlap_question'), findsOneWidget);
    expect(find.text('diagnosis_top_question'), findsOneWidget);
    expect(find.text('diagnosis_cta_done'), findsOneWidget);
    expect(seen.marks, 1);
  });

  testWidgets('sin datos: Porty lo dice, deja reintentar y no lo marca', (
    tester,
  ) async {
    final seen = await pump(
      tester,
      () async =>
          const PortfolioDiagnosis(findings: [], positions: 0, funds: 0),
    );
    expect(find.text('diagnosis_unavailable'), findsOneWidget);
    expect(find.text('retry'), findsOneWidget);
    expect(seen.marks, 0);
  });

  group('puente al final (diagnosis_bridge)', () {
    Future<FakeProductEvents> pumpBridge(
      WidgetTester tester, {
      bool flag = true,
      SubscriptionTier tier = SubscriptionTier.free,
      PositionSource? imported,
      PushPermission permission = PushPermission.notDetermined,
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(375, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final events = FakeProductEvents();
      final theme = ProviderContainer().read(
        brightness == Brightness.dark
            ? themeDataDarkProvider
            : themeDataLightProvider,
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const PortfolioDiagnosisScreen(),
          ),
          GoRoute(
            name: ConnectBrokerRouter.routeName,
            path: '/connect',
            builder: (_, _) => const Text('CONNECT SCREEN'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            portfolioDiagnosisProvider.overrideWith((ref) async => _diagnosis),
            diagnosisSeenProvider.overrideWith((ref) => _Seen(false)),
            diagnosisBridgeEnabledProvider.overrideWith((ref) async => flag),
            subscriptionProvider.overrideWith((ref) => _Sub(tier)),
            homeProvider.overrideWith(
              (ref) => _Home(_homeWith(3, source: imported)),
            ),
            pushControllerProvider.overrideWith((ref) => _Push(permission)),
            paywallOfferProvider.overrideWith((ref) async => PaywallOffer.empty),
            productEventsProvider.overrideWithValue(events),
          ],
          child: MaterialApp.router(theme: theme, routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      return events;
    }

    for (final brightness in Brightness.values) {
      testWidgets('Free, nothing imported: both rows, sync opens the paywall '
          '(${brightness.name})', (tester) async {
        final events = await pumpBridge(tester, brightness: brightness);
        expect(find.text('diagnosis_sync_title'), findsOneWidget);
        expect(find.text('diagnosis_sync_detail_locked'), findsOneWidget);
        expect(find.text('diagnosis_push_title'), findsOneWidget);
        // Siguen todos los hallazgos y las preguntas.
        expect(find.text('diagnosis_overlap_title'), findsOneWidget);
        expect(find.text('diagnosis_overlap_question'), findsOneWidget);

        await tester.tap(find.text('diagnosis_sync_title'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final viewed = events.of(ProductEvent.paywallViewed).single;
        expect(viewed['reason'], 'brokerSync');
        expect(viewed['source'], 'diagnosis_sync');
      });
    }

    testWidgets('Premium: sync goes to the connect screen, no paywall', (
      tester,
    ) async {
      final events = await pumpBridge(tester, tier: SubscriptionTier.premium);
      expect(find.text('diagnosis_sync_detail'), findsOneWidget);
      await tester.tap(find.text('diagnosis_sync_title'));
      await tester.pumpAndSettle();
      expect(find.text('CONNECT SCREEN'), findsOneWidget);
      expect(events.of(ProductEvent.paywallViewed), isEmpty);
    });

    testWidgets('an imported position hides the sync row', (tester) async {
      await pumpBridge(tester, imported: PositionSource.binance);
      expect(find.text('diagnosis_sync_title'), findsNothing);
      expect(find.text('diagnosis_push_title'), findsOneWidget);
    });

    testWidgets('push row opens the sheet with the diagnosis texts and '
        'disappears after accepting', (tester) async {
      final events = await pumpBridge(tester);
      await tester.ensureVisible(find.text('diagnosis_push_title'));
      await tester.tap(find.text('diagnosis_push_title'));
      await tester.pumpAndSettle();
      expect(find.text('push_prompt_title_diagnosis'), findsOneWidget);
      await tester.tap(find.text('push_prompt_enable'));
      await tester.pumpAndSettle();
      expect(find.text('diagnosis_push_title'), findsNothing);
      expect(events.of(ProductEvent.pushOptIn), [
        {'source': 'diagnosis', 'result': 'granted'},
      ]);
    });

    testWidgets('unavailable or decided permission: no push row', (
      tester,
    ) async {
      await pumpBridge(tester, permission: PushPermission.unavailable);
      expect(find.text('diagnosis_push_title'), findsNothing);
    });

    testWidgets('flag off: the diagnosis is the same as before', (
      tester,
    ) async {
      await pumpBridge(tester, flag: false);
      expect(find.text('diagnosis_sync_title'), findsNothing);
      expect(find.text('diagnosis_push_title'), findsNothing);
      expect(find.text('diagnosis_overlap_title'), findsOneWidget);
    });
  });

  group('entrada en la Home', () {
    Future<void> pumpEntry(WidgetTester tester, HomeState home, bool seen) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              homeProvider.overrideWith((ref) => _Home(home)),
              diagnosisSeenProvider.overrideWith((ref) => _Seen(seen)),
            ],
            child: MaterialApp(
              theme: _light,
              home: const Scaffold(body: DiagnosisEntryCard()),
            ),
          ),
        );

    testWidgets('con cartera y sin haberlo visto, aparece', (tester) async {
      await pumpEntry(tester, _homeWith(3), false);
      expect(find.text('diagnosis_entry_title'), findsOneWidget);
    });

    testWidgets('ya visto o sin cartera, no ocupa lugar', (tester) async {
      await pumpEntry(tester, _homeWith(3), true);
      expect(find.text('diagnosis_entry_title'), findsNothing);
      await pumpEntry(tester, _homeWith(0), false);
      expect(find.text('diagnosis_entry_title'), findsNothing);
    });
  });
}

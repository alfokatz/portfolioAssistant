import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/allocation/data/allocation_repository.dart';
import 'package:portfolio_assistant/features/allocation/domain/allocation_plan.dart';
import 'package:portfolio_assistant/features/allocation/providers/allocation_provider.dart';
import 'package:portfolio_assistant/features/allocation/view/allocation_screen.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/notifications/domain/push_route.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Repo implements AllocationRepository {
  _Repo({this.stored, this.failWith});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  AllocationPlan? stored;
  AllocationFailure? failWith;
  int saves = 0;

  @override
  Future<AllocationPlan?> load() async => stored;

  @override
  Future<void> save(AllocationPlan plan) async {
    if (failWith != null) throw failWith!;
    saves++;
    stored = plan;
  }
}

class _Subscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _Subscription(SubscriptionTier tier)
    : super(SubscriptionState(tier: tier, queriesUsed: 0, queriesLimit: 20));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('AllocationMath', () {
    const values = {'VOO': 5000.0, 'BND': 1400.0, 'NVDA': 600.0};
    const targets = {'VOO': 60.0, 'BND': 40.0};

    test('filas: peso de hoy, objetivo y desvío; ordenadas por objetivo', () {
      final rows = AllocationMath.rows(values: values, targets: targets);
      expect(rows.map((r) => r.ticker), ['VOO', 'BND', 'NVDA']);
      expect(rows[0].currentPct, closeTo(71.43, 0.01));
      expect(rows[0].drift, closeTo(11.43, 0.01));
      expect(rows[1].drift, closeTo(-20, 0.01));
      expect(rows[2].targetPct, 0);
      expect(AllocationMath.maxDrift(rows), closeTo(20, 0.01));
    });

    test('aporte: solo compras, reparte todo y acerca al plan', () {
      final split = AllocationMath.contribution(
        values: values,
        targets: targets,
        amount: 1000,
      );
      // Total después: 8000. BND objetivo 3200 (le faltan 1800); VOO 4800
      // (le sobra): todo va a BND.
      expect(split, {'BND': 1000.0});
      final big = AllocationMath.contribution(
        values: values,
        targets: targets,
        amount: 10000,
      );
      // Total 17000: VOO 10200 (falta 5200), BND 6800 (falta 5400).
      expect(big['VOO']! + big['BND']!, closeTo(10000, 0.02));
      expect(big['BND']! > big['VOO']!, isTrue);
      expect(big.containsKey('NVDA'), isFalse);
      expect(
        AllocationMath.contribution(values: values, targets: {}, amount: 1),
        isEmpty,
      );
    });

    test('empezar con los pesos de hoy y ajustar a 100 en enteros', () {
      final t = AllocationMath.fromCurrentWeights(values);
      expect(t.values.fold<double>(0, (a, b) => a + b), 100);
      expect(t, {'VOO': 71.0, 'BND': 20.0, 'NVDA': 9.0});
      final r = AllocationMath.roundTo100({'A': 1, 'B': 1, 'C': 1});
      expect(r.values.fold<double>(0, (a, b) => a + b), 100);
      expect(r, {'A': 34.0, 'B': 33.0, 'C': 33.0});
    });

    test('plan: suma con medio punto de margen y de/hacia la base', () {
      const plan = AllocationPlan(targets: {'VOO': 60.3, 'BND': 39.9});
      expect(plan.sumsTo100, isTrue);
      expect(
        const AllocationPlan(targets: {'VOO': 60, 'BND': 30}).sumsTo100,
        isFalse,
      );
      final row = AllocationPlan.fromRow({
        'targets': {'voo': 60, 'BND': 40, 'X': 'nope'},
        'drift_threshold': 3,
        'notify': false,
      });
      expect(row.targets, {'VOO': 60.0, 'BND': 40.0});
      expect(row.driftThreshold, 3);
      expect(row.notify, isFalse);
      expect(row.toRow()['targets'], {'VOO': 60.0, 'BND': 40.0});
    });
  });

  group('AllocationNotifier', () {
    test('carga, edita, no guarda si no suma 100, guarda', () async {
      final repo = _Repo();
      final n = AllocationNotifier(repo);
      await n.load();
      expect(n.state.loaded, isTrue);
      expect(n.state.draft.isEmpty, isTrue);
      n.startFromCurrent({'VOO': 600, 'BND': 400});
      expect(n.state.draft.targets, {'VOO': 60.0, 'BND': 40.0});
      n.setTarget('voo', 70);
      expect(n.state.draft.sumsTo100, isFalse);
      expect(await n.save(), isFalse);
      n.normalize();
      expect(n.state.draft.targetSum, 100);
      expect(await n.save(), isTrue);
      expect(repo.saves, 1);
      expect(n.state.dirty, isFalse);
      n.setTarget('BND', 0);
      expect(n.state.draft.targets.containsKey('BND'), isFalse);
    });

    test('la base dice que es de Premium', () async {
      final n = AllocationNotifier(_Repo(failWith: const AllocationLocked()));
      await n.load();
      n.startFromCurrent({'VOO': 1});
      expect(await n.save(), isFalse);
      expect(n.state.error, AllocationError.locked);
    });
  });

  test('la notificación abre el plan', () {
    expect(
      PushRoute.fromData({'route': 'allocation'}),
      isA<PushRouteAllocation>(),
    );
  });

  group('pantalla', () {
    Future<void> pump(
      WidgetTester tester, {
      required SubscriptionTier tier,
      AllocationPlan? stored,
    }) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final theme = ProviderContainer().read(themeDataLightProvider);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allocationRepositoryProvider.overrideWithValue(
              _Repo(stored: stored),
            ),
            goalHoldingsProvider.overrideWithValue(const {
              'VOO': 5000,
              'BND': 1400,
              'NVDA': 600,
            }),
            subscriptionProvider.overrideWith((ref) => _Subscription(tier)),
          ],
          child: MaterialApp(theme: theme, home: const AllocationScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Free ve el paywall, no el editor', (tester) async {
      await pump(tester, tier: SubscriptionTier.free);
      expect(find.text('allocation_locked_body'), findsOneWidget);
      expect(find.text('allocation_save'), findsNothing);
    });

    testWidgets('Premium sin plan: arrancar con los pesos de hoy', (
      tester,
    ) async {
      await pump(tester, tier: SubscriptionTier.premium);
      await tester.tap(find.text('allocation_start_current'));
      await tester.pumpAndSettle();
      expect(find.text('VOO'), findsOneWidget);
      expect(find.text('allocation_sum_ok'), findsOneWidget);
      expect(find.text('allocation_save'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con plan: desvíos y reparto del aporte', (tester) async {
      await pump(
        tester,
        tier: SubscriptionTier.premium,
        stored: const AllocationPlan(targets: {'VOO': 60, 'BND': 40}),
      );
      expect(find.text('BND'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1000');
      await tester.pumpAndSettle();
      expect(find.text('allocation_contribution_result'), findsOneWidget);
      expect(find.text('\$1,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

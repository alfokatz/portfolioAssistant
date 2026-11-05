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
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
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

  group('reparto del asistente', () {
    test('mover uno reparte la diferencia entre los demás y suma 100', () {
      final r = AllocationMath.rebalance(
        targets: const {'VOO': 50, 'BND': 30, 'NVDA': 20},
        ticker: 'VOO',
        value: 70,
      );
      // Sobran 30 entre BND y NVDA, en proporción 30:20.
      expect(r, {'VOO': 70, 'BND': 18, 'NVDA': 12});
      expect(r.values.fold<int>(0, (a, b) => a + b), 100);
    });

    test('los fijos no se mueven y ponen el techo', () {
      final r = AllocationMath.rebalance(
        targets: const {'VOO': 50, 'BND': 30, 'NVDA': 20},
        ticker: 'VOO',
        value: 90,
        locked: {'BND'},
      );
      expect(r, {'VOO': 70, 'BND': 30, 'NVDA': 0});
      // Si todos los demás están fijos, no hay a quién pasarle nada.
      final stuck = AllocationMath.rebalance(
        targets: const {'VOO': 60, 'BND': 40},
        ticker: 'VOO',
        value: 10,
        locked: {'BND'},
      );
      expect(stuck, {'VOO': 60, 'BND': 40});
    });

    test('si los demás estaban en 0, reparte en partes iguales', () {
      final r = AllocationMath.rebalance(
        targets: const {'VOO': 100, 'BND': 0, 'QQQ': 0},
        ticker: 'VOO',
        value: 60,
      );
      expect(r, {'VOO': 60, 'BND': 20, 'QQQ': 20});
    });

    test('arranque: pesos de hoy para lo que tiene, 0 para lo nuevo', () {
      expect(
        AllocationMath.initialSplit(
          tickers: const ['VOO', 'BND', 'QQQ'],
          values: const {'VOO': 600, 'BND': 400, 'NVDA': 1000},
        ),
        {'VOO': 60, 'BND': 40, 'QQQ': 0},
      );
      expect(
        AllocationMath.initialSplit(tickers: const ['A', 'B', 'C'], values: {}),
        {'A': 34, 'B': 33, 'C': 33},
      );
      expect(AllocationMath.equalSplit(const ['A', 'B']), {'A': 50, 'B': 50});
      expect(AllocationMath.remove(const {'A': 50, 'B': 30, 'C': 20}, 'A'), {
        'B': 60,
        'C': 40,
      });
    });

    test('cómo quedaría la cartera después del aporte', () {
      final after = AllocationMath.weightsAfter(
        values: const {'VOO': 600, 'BND': 400},
        split: const {'BND': 1000},
      );
      expect(after['VOO'], closeTo(30, 0.01));
      expect(after['BND'], closeTo(70, 0.01));
    });

    test('frecuencia del aviso: de/hacia la base, semanal por defecto', () {
      expect(
        AllocationPlan.fromRow({
          'targets': {'VOO': 100},
          'notify_frequency': 'monthly',
        }).frequency,
        AllocationAlertFrequency.monthly,
      );
      expect(
        AllocationPlan.fromRow({'targets': {}}).frequency,
        AllocationAlertFrequency.weekly,
      );
      expect(
        const AllocationPlan(
          frequency: AllocationAlertFrequency.monthly,
        ).toRow()['notify_frequency'],
        'monthly',
      );
    });
  });

  group('recordatorio de aporte (fase 6)', () {
    test('de/hacia la base; un día fuera de 1-28 no cuenta; sin día no se '
        'guarda el monto', () {
      final plan = AllocationPlan.fromRow({
        'targets': {'VOO': 100},
        'contribution_day': 5,
        'contribution_amount': '500',
      });
      expect(plan.contributionDay, 5);
      expect(plan.contributionAmount, 500);
      expect(plan.hasContributionReminder, isTrue);
      expect(plan.toRow()['contribution_day'], 5);
      expect(plan.toRow()['contribution_amount'], 500);
      expect(
        AllocationPlan.fromRow({'contribution_day': 31}).contributionDay,
        isNull,
      );
      expect(
        const AllocationPlan(contributionAmount: 500).toRow()
            ['contribution_amount'],
        isNull,
      );
    });

    test('copyWith puede apagarlo (volver a null) y dejarlo como estaba', () {
      const plan = AllocationPlan(
        targets: {'VOO': 100},
        contributionDay: 5,
        contributionAmount: 500,
      );
      expect(plan.copyWith(notify: false).contributionDay, 5);
      final off = plan.copyWith(
        contributionDay: () => null,
        contributionAmount: () => null,
      );
      expect(off.hasContributionReminder, isFalse);
      expect(off, isNot(plan));
    });
  });

  group('AllocationNotifier', () {
    test('carga, no guarda si no suma 100, guarda', () async {
      final repo = _Repo();
      final n = AllocationNotifier(repo);
      await n.load();
      expect(n.state.loaded, isTrue);
      expect(n.state.saved.isEmpty, isTrue);
      expect(
        await n.save(const AllocationPlan(targets: {'VOO': 70, 'BND': 40})),
        isFalse,
      );
      const plan = AllocationPlan(targets: {'VOO': 60, 'BND': 40});
      expect(await n.save(plan), isTrue);
      expect(repo.saves, 1);
      expect(n.state.saved, plan);
    });

    test('la base dice que es de Premium', () async {
      final n = AllocationNotifier(_Repo(failWith: const AllocationLocked()));
      await n.load();
      expect(
        await n.save(const AllocationPlan(targets: {'VOO': 100})),
        isFalse,
      );
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
    late _Repo repo;

    Future<void> pump(
      WidgetTester tester, {
      required SubscriptionTier tier,
      AllocationPlan? stored,
    }) async {
      tester.view.physicalSize = const Size(320, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      repo = _Repo(stored: stored);
      final theme = ProviderContainer().read(themeDataLightProvider);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            allocationRepositoryProvider.overrideWithValue(repo),
            goalHoldingsProvider.overrideWithValue(const {
              'VOO': 5000,
              'BND': 1400,
              'NVDA': 600,
            }),
            subscriptionProvider.overrideWith((ref) => _Subscription(tier)),
          ],
          child: MaterialApp(
            theme: theme,
            // Alguien escucha las alertas (si no, el provider se descarta
            // antes de que se cierre el aviso de "guardado").
            home: Consumer(
              builder: (context, ref, _) {
                ref.watch(alertProvider);
                return const AllocationScreen();
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    Future<void> tapText(WidgetTester tester, String text) async {
      await tester.tap(find.text(text));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('Free ve qué es y el botón a los planes', (tester) async {
      await pump(tester, tier: SubscriptionTier.free);
      expect(find.text('allocation_locked_body'), findsOneWidget);
      expect(find.text('allocation_see_plans'), findsOneWidget);
      expect(find.text('allocation_start'), findsNothing);
    });

    testWidgets('Premium sin plan: lo arma de a pasos y lo guarda', (
      tester,
    ) async {
      await pump(tester, tier: SubscriptionTier.premium);
      await tapText(tester, 'allocation_start');

      // Paso 1: lo que ya tiene viene marcado; saca NVDA.
      expect(find.text('allocation_pick_porty'), findsOneWidget);
      await tapText(tester, 'NVDA');
      expect(find.text('allocation_pick_left_out'), findsOneWidget);
      await tapText(tester, 'allocation_wizard_next');

      // Paso 2: arranca con los pesos de hoy y siempre suma 100.
      expect(find.text('allocation_split_total'), findsOneWidget);
      expect(find.text('78%'), findsOneWidget); // VOO 5000 / 6400
      expect(find.text('22%'), findsOneWidget);
      await tapText(tester, 'allocation_preset_equal');
      expect(find.text('50%'), findsNWidgets(2));
      await tapText(tester, 'allocation_wizard_next');

      // Paso 3: avisos, con el ejemplo de sus tickers.
      expect(find.text('allocation_margin_title'), findsOneWidget);
      expect(find.text('allocation_bands_title'), findsOneWidget);
      await tapText(tester, 'allocation_frequency_monthly');
      await tapText(tester, 'allocation_wizard_review');

      // Paso 4: repaso y guardar.
      expect(find.text('allocation_review_porty'), findsOneWidget);
      await tapText(tester, 'allocation_save');
      expect(repo.saves, 1);
      expect(repo.stored!.targets, {'VOO': 50.0, 'BND': 50.0});
      expect(repo.stored!.frequency, AllocationAlertFrequency.monthly);
      // Vuelve al tablero.
      expect(find.text('allocation_compare_title'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Que se cierre el aviso de "guardado".
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('con plan: cómo viene y dónde poner el próximo aporte', (
      tester,
    ) async {
      await pump(
        tester,
        tier: SubscriptionTier.premium,
        stored: const AllocationPlan(targets: {'VOO': 60, 'BND': 40}),
      );
      // BND pesa 22% y el plan dice 40%: el mayor desvío.
      expect(find.text('allocation_status_off_under'), findsOneWidget);
      expect(find.text('allocation_row_under'), findsWidgets);
      await tapText(tester, 'allocation_contribution_cta');
      await tester.enterText(find.byType(TextField), '1000');
      await tester.pump();
      expect(find.text('allocation_contribution_result'), findsOneWidget);
      expect(find.text('\$1,000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

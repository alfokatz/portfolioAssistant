import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/goals/data/goals_repository.dart';
import 'package:portfolio_assistant/features/goals/domain/user_goal.dart';
import 'package:portfolio_assistant/features/goals/providers/goals_provider.dart';
import 'package:portfolio_assistant/features/goals/view/goals_screen.dart';
import 'package:portfolio_assistant/presentation/base/alert/alert_provider.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

import 'goal_detail_screen_test.dart' show goalFixture, loadSpanish;

/// Repo en memoria: lista la meta y registra los borrados.
class _Repo extends GoalsRepository {
  _Repo(this.goals) : super(client: () => null);

  final List<UserGoal> goals;
  final deleted = <String>[];

  @override
  Future<List<UserGoal>> list() async => [...goals];

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    goals.removeWhere((g) => g.id == id);
  }
}

Future<_Repo> _pump(WidgetTester tester) async {
  final repo = _Repo([goalFixture()]);
  await tester.binding.setSurfaceSize(const Size(390, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        goalsProvider.overrideWith((ref) => GoalsNotifier(repo)),
        goalHoldingsProvider.overrideWithValue(const {}),
      ],
      child: MaterialApp(
        theme: ProviderContainer().read(themeDataLightProvider),
        // Como el AppShell: alguien escucha los avisos (si no, el provider
        // se descarta antes de que el aviso se oculte).
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(alertProvider);
            return const GoalsScreen();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  setUpAll(loadSpanish);

  testWidgets('swiping a goal asks and deletes it', (tester) async {
    final repo = await _pump(tester);
    expect(find.text('Auto'), findsOneWidget);

    await tester.drag(find.text('Auto'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(
      find.text('goal_delete_title'.tr(namedArgs: {'goal': 'Auto'})),
      findsOneWidget,
    );

    // Cancelar: la meta vuelve a su lugar.
    await tester.tap(find.text('porty_memory_cancel'.tr()));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.text('Auto'), findsOneWidget);

    await tester.drag(find.text('Auto'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('goal_delete_confirm'.tr()).last);
    // Sin metas queda el estado vacío, con Porty animado: no "se asienta".
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect(repo.deleted, ['g1']);
    expect(find.text('Auto'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long press opens the options, with delete', (tester) async {
    final repo = await _pump(tester);
    await tester.longPress(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(find.text('goal_mark_achieved'.tr()), findsOneWidget);
    await tester.tap(find.text('goal_delete'.tr()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('goal_delete_confirm'.tr()).last);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 3));
    expect(repo.deleted, ['g1']);
  });
}

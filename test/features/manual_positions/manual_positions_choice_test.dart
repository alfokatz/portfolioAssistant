// Reemplazar o conservar lo cargado a mano al traer la cartera de un
// bróker: la fila aparece solo si hay manuales, "Conservar las dos" no
// borra nada y "Quedarme solo con lo de…" borra y recarga la Home.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/manual_positions/data/manual_positions_repository.dart';
import 'package:portfolio_assistant/features/manual_positions/view/manual_positions_choice.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';

class _Repo implements ManualPositionsRepository {
  _Repo(this.count);

  int count;
  var deletes = 0;

  @override
  Future<int> countTickers() async => count;

  @override
  Future<void> deleteAll() async {
    deletes++;
    count = 0;
  }
}

void main() {
  late _Repo repo;
  late int refreshes;

  Future<void> pump(WidgetTester tester, {Brightness? brightness}) async {
    refreshes = 0;
    final theme = ProviderContainer().read(
      brightness == Brightness.dark
          ? themeDataDarkProvider
          : themeDataLightProvider,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          manualPositionsRepositoryProvider.overrideWithValue(repo),
          manualPositionsRefreshProvider.overrideWithValue(
            () async => refreshes++,
          ),
        ],
        child: MaterialApp(
          theme: theme,
          home: const Scaffold(body: ManualPositionsRow(broker: 'eToro')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ManualPositionsRow', () {
    testWidgets('hidden without manual positions', (tester) async {
      repo = _Repo(0);
      await pump(tester);
      expect(find.text('manual_positions_row_cta'), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('keep both deletes nothing (${brightness.name})', (
        tester,
      ) async {
        repo = _Repo(3);
        await pump(tester, brightness: brightness);
        await tester.tap(find.text('manual_positions_row_cta'));
        await tester.pumpAndSettle();
        expect(find.text('manual_positions_title'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('manual_positions_keep'));
        await tester.pumpAndSettle();
        expect(repo.deletes, 0);
        expect(find.text('manual_positions_row_cta'), findsOneWidget);
      });
    }

    testWidgets('replace deletes them, reloads Home and hides the row', (
      tester,
    ) async {
      repo = _Repo(2);
      await pump(tester);
      await tester.tap(find.text('manual_positions_row_cta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('manual_positions_replace'));
      await tester.pumpAndSettle();
      expect(repo.deletes, 1);
      expect(refreshes, 1);
      expect(find.text('manual_positions_row_cta'), findsNothing);
    });
  });
}

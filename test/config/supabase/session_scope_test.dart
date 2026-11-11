import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/session_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Estado en memoria de "un usuario" (como la cartera cargada).
final _amountProvider = StateProvider<int>((ref) => 0);

/// Un override que tiene que sobrevivir a cada contenedor nuevo.
final _serviceProvider = Provider<String>((ref) => 'sin override');

const _a = 'user-a-1111';
const _b = 'user-b-2222';

void main() {
  late StreamController<String?> users;
  late WidgetRef ref;

  Future<void> pump(
    WidgetTester tester, {
    String? initialUserId = _a,
    SharedPreferences? prefs,
  }) async {
    await tester.pumpWidget(
      SessionScope(
        initialUserId: initialUserId,
        userIds: users.stream,
        prefs: prefs,
        overrides: [_serviceProvider.overrideWithValue('servicio')],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            return Text(
              '${r.watch(_amountProvider)} ${r.watch(_serviceProvider)}',
              textDirection: TextDirection.ltr,
            );
          },
        ),
      ),
    );
  }

  Future<void> emit(WidgetTester tester, String? userId) async {
    users.add(userId);
    await tester.pump();
    await tester.pump();
  }

  setUp(() => users = StreamController<String?>.broadcast());
  tearDown(() => users.close());

  testWidgets('cerrar sesión descarta todo el estado en memoria', (
    tester,
  ) async {
    await pump(tester);
    ref.read(_amountProvider.notifier).state = 125000;
    await tester.pump();
    expect(find.text('125000 servicio'), findsOneWidget);

    await emit(tester, null);

    expect(find.text('0 servicio'), findsOneWidget);
  });

  testWidgets('otra cuenta nunca ve el estado de la anterior', (tester) async {
    await pump(tester);
    ref.read(_amountProvider.notifier).state = 125000;
    await tester.pump();

    await emit(tester, _b);

    expect(find.text('125000 servicio'), findsNothing);
    expect(find.text('0 servicio'), findsOneWidget);
  });

  testWidgets('un refresco de token (mismo usuario) no reinicia nada', (
    tester,
  ) async {
    await pump(tester);
    ref.read(_amountProvider.notifier).state = 42;
    await tester.pump();

    await emit(tester, _a);

    expect(find.text('42 servicio'), findsOneWidget);
  });

  testWidgets('borra del disco las claves del usuario que se fue', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'home_snapshot_v1_$_a': '{}',
      'weekly_report_cache_${_a}_2026-W45': '{}',
      'weekly_report_seen_${_a}_2026-W45': true,
      'home_snapshot_v1_$_b': '{}',
      'onboarding_completed': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await pump(tester, prefs: prefs);

    await emit(tester, null);

    expect(prefs.getKeys(), {
      'weekly_report_seen_${_a}_2026-W45',
      'home_snapshot_v1_$_b',
      'onboarding_completed',
    });
  });

  testWidgets('runAfterRestart corre con el contenedor nuevo', (tester) async {
    await pump(tester);
    ref.read(_amountProvider.notifier).state = 7;
    int? seen;
    SessionScope.runAfterRestart(
      (container) => seen = container.read(_amountProvider),
    );

    await emit(tester, null);

    expect(seen, 0);
  });
}

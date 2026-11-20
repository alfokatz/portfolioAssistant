import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfolio_assistant/config/env/app_env.dart';
import 'package:portfolio_assistant/presentation/shared/widgets/env_badge.dart';

Widget _host(EnvBadge badge) => MaterialApp(
  home: const SizedBox.expand(),
  builder: (context, child) =>
      Stack(children: [if (child != null) child, badge]),
);

void main() {
  group('AppEnv sin defines (tests)', () {
    test('valores vacíos, develop por defecto y falla rápido', () {
      expect(AppEnv.supabaseUrl, isEmpty);
      expect(AppEnv.supabaseAnonKeyOrNull, isNull);
      expect(AppEnv.appEnv, AppEnv.develop);
      expect(AppEnv.isProd, isFalse);
      expect(AppEnv.yahooCacheTtlMinutes, 10);
      expect(
        AppEnv.ensureValid,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('SUPABASE_URL'), contains('SUPABASE_ANON_KEY')),
          ),
        ),
      );
    });
  });

  group('EnvBadge', () {
    testWidgets('fuera de prod muestra DEV sin tapar toques', (tester) async {
      await tester.pumpWidget(_host(const EnvBadge(show: true)));
      expect(find.text('DEV'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('DEV'), matching: find.byType(IgnorePointer)),
        findsWidgets,
      );
    });

    testWidgets('en prod no muestra nada', (tester) async {
      await tester.pumpWidget(_host(const EnvBadge(show: false)));
      expect(find.text('DEV'), findsNothing);
    });

    testWidgets('por defecto sigue a AppEnv (develop en tests)', (tester) async {
      await tester.pumpWidget(_host(const EnvBadge()));
      expect(find.text('DEV'), findsOneWidget);
    });
  });
}

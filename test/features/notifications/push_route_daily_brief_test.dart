// Ruta del push `daily_brief`: parseo del data y navegación a la pantalla del
// brief con el día y el origen `push`. Correr:
// flutter test test/features/notifications/push_route_daily_brief_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:portfolio_assistant/features/daily_brief/nav/daily_brief_router.dart';
import 'package:portfolio_assistant/features/notifications/domain/push_route.dart';
import 'package:portfolio_assistant/features/notifications/view/push_open_listener.dart';

void main() {
  group('PushRoute.fromData daily_brief', () {
    test('carries a valid day', () {
      final r =
          PushRoute.fromData({'route': 'daily_brief', 'day': '2026-12-02'})
              as PushRouteDailyBrief;
      expect(r.day, '2026-12-02');
    });

    test('a missing or malformed day means today', () {
      expect(
        (PushRoute.fromData({'route': 'daily_brief'}) as PushRouteDailyBrief)
            .day,
        isNull,
      );
      expect(
        (PushRoute.fromData({'route': 'daily_brief', 'day': "x'; drop"})
                as PushRouteDailyBrief)
            .day,
        isNull,
      );
    });
  });

  testWidgets('opens the brief with day and source push', (tester) async {
    Object? extra;
    late BuildContext captured;
    final router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) {
            captured = context;
            return const Text('start');
          },
        ),
        GoRoute(
          name: DailyBriefRouter.routeName,
          path: DailyBriefRouter.path,
          builder: (context, state) {
            extra = state.extra;
            return const Text('brief');
          },
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    openPushRoute(
      captured,
      const PushRouteDailyBrief(day: '2026-12-02'),
      holds: (_) => false,
    );
    await tester.pumpAndSettle();
    expect(find.text('brief'), findsOneWidget);
    expect(extra, {'day': '2026-12-02', 'source': 'push'});
  });
}

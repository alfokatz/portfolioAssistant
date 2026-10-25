import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/domain/entities/subscription_tier.dart';
import 'package:portfolio_assistant/features/assistant/nav/assistant_router.dart';
import 'package:portfolio_assistant/features/assistant/states/assistant_state.dart';
import 'package:portfolio_assistant/features/notifications/data/notifications_repository.dart';
import 'package:portfolio_assistant/features/notifications/data/price_alerts_repository.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/domain/price_alert.dart';
import 'package:portfolio_assistant/features/notifications/domain/push_route.dart';
import 'package:portfolio_assistant/features/notifications/nav/notifications_router.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/features/notifications/view/notification_settings_screen.dart';
import 'package:portfolio_assistant/features/notifications/view/price_alerts_screen.dart';
import 'package:portfolio_assistant/features/notifications/view/push_open_listener.dart';
import 'package:portfolio_assistant/features/subscription/providers/subscription_provider.dart';
import 'package:portfolio_assistant/features/weekly_report/nav/weekly_report_router.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:portfolio_assistant/presentation/flows/home/nav/home_router.dart';
import 'package:portfolio_assistant/presentation/flows/position/nav/position_router.dart';
import 'package:portfolio_assistant/presentation/flows/settings/ui/widgets/settings_nav_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_controller_test.dart' show FakeDeviceInfo, FakeMessaging, FakeRepo;

ThemeData get _light => ProviderContainer().read(themeDataLightProvider);

class _FixedSubscription extends StateNotifier<SubscriptionState>
    implements SubscriptionNotifier {
  _FixedSubscription(SubscriptionTier tier)
    : super(SubscriptionState(tier: tier, queriesUsed: 0, queriesLimit: 20));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAlerts extends PriceAlertsRepository {
  _FakeAlerts(this.alerts) : super(client: () => null);

  final List<PriceAlert> alerts;

  @override
  Future<List<PriceAlert>> list() async => alerts;
}

PriceAlert _alert(
  String id,
  String symbol,
  PriceAlertStatus status, {
  PriceAlertCondition condition = PriceAlertCondition.above,
  bool pausedByPlan = false,
}) => PriceAlert(
  id: id,
  symbol: symbol,
  condition: condition,
  target: 750,
  status: status,
  createdAt: DateTime(2026, 10, 1),
  pausedByPlan: pausedByPlan,
  lastPrice: 741.2,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required FakeMessaging messaging,
  FakeRepo? repo,
  List<PriceAlert> alerts = const [],
  SubscriptionTier tier = SubscriptionTier.premium,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        pushMessagingProvider.overrideWithValue(messaging),
        notificationsRepositoryProvider.overrideWithValue(repo ?? FakeRepo()),
        deviceInfoSourceProvider.overrideWithValue(FakeDeviceInfo()),
        priceAlertsRepositoryProvider.overrideWithValue(_FakeAlerts(alerts)),
        subscriptionProvider.overrideWith((ref) => _FixedSubscription(tier)),
      ],
      child: MaterialApp(theme: _light, home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Ajustes → Notificaciones', () {
    testWidgets('sin permiso: ofrece activarlas y los tipos quedan apagados', (
      tester,
    ) async {
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        messaging: FakeMessaging(),
      );
      expect(find.text('notifications_enable'), findsOneWidget);
      final toggles = tester.widgetList<SettingsToggleRow>(
        find.byType(SettingsToggleRow),
      );
      expect(toggles, isNotEmpty);
      expect(toggles.every((t) => t.onChanged == null), isTrue);
      // Sin permiso no hay "enviarme una de prueba".
      expect(find.text('notifications_send_test'), findsNothing);
    });

    testWidgets('con permiso: apagar un tipo lo guarda', (tester) async {
      final messaging = FakeMessaging()..current = PushPermission.granted;
      final repo = FakeRepo();
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        messaging: messaging,
        repo: repo,
      );
      expect(find.text('notifications_master'), findsOneWidget);
      // Registró el token al abrir (zona e idioma al día).
      expect(repo.registered, isNotEmpty);

      final bigMoves = find.widgetWithText(
        SettingsToggleRow,
        'notifications_big_moves',
      );
      await tester.ensureVisible(bigMoves);
      await tester.tap(
        find.descendant(of: bigMoves, matching: find.byType(Switch)),
      );
      await tester.pumpAndSettle();
      expect(repo.stored.bigMoves, isFalse);
    });

    testWidgets('negadas en el sistema: lleva a los ajustes del teléfono', (
      tester,
    ) async {
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        messaging: FakeMessaging()..current = PushPermission.denied,
      );
      expect(find.text('notifications_denied'), findsOneWidget);
      expect(find.text('notifications_denied_desc'), findsOneWidget);
    });
  });

  group('Alertas de precio', () {
    testWidgets('agrupa activas, cumplidas y pausadas', (tester) async {
      await _pump(
        tester,
        const PriceAlertsScreen(),
        messaging: FakeMessaging(),
        alerts: [
          _alert('1', 'VOO', PriceAlertStatus.active),
          _alert(
            '2',
            'NVDA',
            PriceAlertStatus.triggered,
            condition: PriceAlertCondition.below,
          ),
          _alert('3', 'TSLA', PriceAlertStatus.paused, pausedByPlan: true),
        ],
      );
      expect(find.text('price_alerts_section_active'), findsOneWidget);
      expect(find.text('price_alerts_section_triggered'), findsOneWidget);
      expect(find.text('price_alerts_section_paused'), findsOneWidget);
      expect(find.textContaining('VOO · '), findsOneWidget);
      expect(find.text('price_alert_status_paused_plan'), findsOneWidget);
    });

    testWidgets('vacía: explica cómo crear una', (tester) async {
      await _pump(
        tester,
        const PriceAlertsScreen(),
        messaging: FakeMessaging(),
      );
      expect(find.text('price_alerts_empty'), findsOneWidget);
      expect(find.text('price_alerts_new'), findsOneWidget);
    });
  });

  group('openPushRoute', () {
    late GoRouter router;
    late List<String> visited;

    GoRoute named(String name, String path) => GoRoute(
      name: name,
      path: path,
      builder: (context, state) {
        visited.add(name);
        final extra = state.extra;
        return Text(
          '$name ${extra is AssistantQuestionRequest ? extra.question : extra is Map ? extra['ticker'] : ''}',
        );
      },
    );

    Future<BuildContext> pumpRouter(WidgetTester tester) async {
      visited = [];
      late BuildContext captured;
      router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (context, state) {
              captured = context;
              return const Text('start');
            },
          ),
          named(HomeRouter.homeRouteName, '/Home'),
          named(AssistantRouter.routeName, AssistantRouter.path),
          named(WeeklyReportRouter.routeName, WeeklyReportRouter.path),
          named(PositionRouter.detailRouteName, PositionRouter.detailPath),
          named(
            NotificationsRouter.alertsRouteName,
            NotificationsRouter.alertsPath,
          ),
        ],
      );
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      return captured;
    }

    testWidgets('alerta de un ticker que tiene: el detalle de la posición', (
      tester,
    ) async {
      final context = await pumpRouter(tester);
      openPushRoute(
        context,
        const PushRouteTicker('VOO'),
        holds: (t) => t == 'VOO',
      );
      await tester.pumpAndSettle();
      expect(find.text('${PositionRouter.detailRouteName} VOO'), findsOneWidget);
    });

    testWidgets('alerta de un ticker que no tiene: la lista de alertas', (
      tester,
    ) async {
      final context = await pumpRouter(tester);
      openPushRoute(context, const PushRouteTicker('AAPL'), holds: (_) => false);
      await tester.pumpAndSettle();
      expect(visited.last, NotificationsRouter.alertsRouteName);
    });

    testWidgets('movimiento fuerte: el chat con la pregunta cargada', (
      tester,
    ) async {
      final context = await pumpRouter(tester);
      openPushRoute(
        context,
        const PushRouteAssistant('¿Por qué se mueve NVDA hoy?'),
        holds: (_) => false,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('${AssistantRouter.routeName} ¿Por qué se mueve NVDA hoy?'),
        findsOneWidget,
      );
    });

    testWidgets('informe semanal', (tester) async {
      final context = await pumpRouter(tester);
      openPushRoute(
        context,
        const PushRouteWeeklyReport(),
        holds: (_) => false,
      );
      await tester.pumpAndSettle();
      expect(visited.last, WeeklyReportRouter.routeName);
    });
  });
}

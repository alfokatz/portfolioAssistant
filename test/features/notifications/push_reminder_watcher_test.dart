// Notificaciones al entrar a la Home: la primera vez se ofrecen; si se
// rechazaron en el sistema, cada tanto Porty recuerda cómo prenderlas. Nunca
// apila hojas. Correr: flutter test test/features/notifications/push_reminder_watcher_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/assistant/view/widgets/porty_avatar.dart';
import 'package:portfolio_assistant/features/notifications/data/notifications_repository.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:portfolio_assistant/features/notifications/view/push_reminder_watcher.dart';
import 'package:portfolio_assistant/features/portfolio_diagnosis/providers/portfolio_diagnosis_provider.dart';
import 'package:portfolio_assistant/features/product_events/data/product_events.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/base/theme/theme_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'push_controller_test.dart' show FakeMessaging, FakeRepo, FakeDeviceInfo;

class _Seen extends DiagnosisSeenNotifier {
  _Seen(bool seen) : super(null, null) {
    state = seen;
  }

  void see() => state = true;
}

class _Events extends ProductEvents {
  _Events() : super(client: () => null, prefs: () => null);
  final logged = <(ProductEvent, Map<String, Object?>)>[];

  @override
  void log(ProductEvent event, [Map<String, Object?> props = const {}]) =>
      logged.add((event, props));
}

void main() {
  // La cara de Porty (PortySays) no se anima sola: pumpAndSettle termina.
  setUpAll(() => PortyAvatar.ambientMotion = false);
  group('PushSettingsReminderPolicy', () {
    test('solo con permiso rechazado: a los 3 días, cada 14 y 3 veces como '
        'mucho; si vuelve a prenderlas, arranca de cero', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 11, 1);
      final policy = PushSettingsReminderPolicy(prefs, now: () => now);

      expect(policy.shouldOffer(PushPermission.denied), isFalse);
      await policy.observe(PushPermission.denied);
      expect(policy.shouldOffer(PushPermission.denied), isFalse);
      expect(policy.shouldOffer(PushPermission.notDetermined), isFalse);

      now = now.add(const Duration(days: 3));
      expect(policy.shouldOffer(PushPermission.denied), isTrue);
      await policy.recordShown();
      now = now.add(const Duration(days: 13));
      expect(policy.shouldOffer(PushPermission.denied), isFalse);
      now = now.add(const Duration(days: 1));
      expect(policy.shouldOffer(PushPermission.denied), isTrue);
      await policy.recordShown();
      now = now.add(const Duration(days: 14));
      await policy.recordShown();
      now = now.add(const Duration(days: 60));
      expect(policy.shouldOffer(PushPermission.denied), isFalse);

      await policy.observe(PushPermission.granted);
      await policy.observe(PushPermission.denied);
      expect(policy.shouldOffer(PushPermission.denied), isFalse);
      now = now.add(const Duration(days: 3));
      expect(policy.shouldOffer(PushPermission.denied), isTrue);
    });
  });

  group('PushReminderWatcher', () {
    late FakeMessaging messaging;
    late SharedPreferences prefs;
    late _Seen seen;
    late ProviderContainer container;
    const delay = Duration(milliseconds: 50);

    Future<void> pump(
      WidgetTester tester, {
      PushPermission permission = PushPermission.notDetermined,
      Map<String, Object> extraPrefs = const {},
      bool isHome = true,
      bool diagnosisSeen = true,
    }) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(extraPrefs);
      prefs = await SharedPreferences.getInstance();
      messaging = FakeMessaging()..current = permission;
      seen = _Seen(diagnosisSeen);
      final probe = ProviderContainer();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            pushMessagingProvider.overrideWithValue(messaging),
            notificationsRepositoryProvider.overrideWithValue(FakeRepo()),
            deviceInfoSourceProvider.overrideWithValue(FakeDeviceInfo()),
            diagnosisSeenProvider.overrideWith((ref) => seen),
            productEventsProvider.overrideWithValue(_Events()),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: probe.read(themeDataLightProvider),
                home: PushReminderWatcher(
                  isHome: isHome,
                  settleDelay: delay,
                  child: const Scaffold(body: Text('home')),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> wait(WidgetTester tester) async {
      await tester.pump(delay * 2);
      await tester.pumpAndSettle();
    }

    testWidgets('sin decidir: ofrece activarlas al entrar a la Home, y '
        '"Activar" muestra el diálogo del sistema', (tester) async {
      await pump(tester);
      await wait(tester);
      expect(find.text('push_prompt_title_welcome'), findsOneWidget);
      expect(container.read(homePromptShownThisOpenProvider), isTrue);

      await tester.tap(find.text('push_prompt_enable'));
      await tester.pumpAndSettle();
      expect(messaging.requests, 1);
    });

    testWidgets('"Ahora no": no vuelve en la misma apertura', (tester) async {
      await pump(tester);
      await wait(tester);
      await tester.tap(find.text('push_prompt_not_now'));
      await tester.pumpAndSettle();
      await wait(tester);
      expect(find.text('push_prompt_title_welcome'), findsNothing);
      expect(messaging.requests, 0);
    });

    testWidgets('rechazado en el sistema hace más de 3 días: recuerda cómo '
        'prenderlas, sin el diálogo del sistema', (tester) async {
      final denied = DateTime.now()
          .subtract(const Duration(days: 4))
          .millisecondsSinceEpoch;
      await pump(
        tester,
        permission: PushPermission.denied,
        extraPrefs: {'push_denied_seen_at': denied},
      );
      await wait(tester);
      expect(find.text('push_reminder_title'), findsOneWidget);
      expect(find.text('push_reminder_open_settings'), findsOneWidget);
      expect(prefs.getInt('push_settings_reminder_count'), 1);

      await tester.tap(find.text('push_prompt_not_now'));
      await tester.pumpAndSettle();
      expect(messaging.requests, 0);
    });

    testWidgets('rechazado recién: solo anota cuándo, todavía no insiste', (
      tester,
    ) async {
      await pump(tester, permission: PushPermission.denied);
      await wait(tester);
      expect(find.text('push_reminder_title'), findsNothing);
      expect(prefs.getInt('push_denied_seen_at'), isNotNull);
    });

    testWidgets('ya prendidas, o fuera de la Home: nada', (tester) async {
      await pump(tester, permission: PushPermission.granted);
      await wait(tester);
      expect(find.text('push_prompt_title_welcome'), findsNothing);
      expect(find.text('push_reminder_title'), findsNothing);

      await pump(tester, isHome: false);
      await wait(tester);
      expect(find.text('push_prompt_title_welcome'), findsNothing);
    });

    testWidgets('la apertura en la que se vio el primer diagnóstico no ofrece '
        'nada (el diagnóstico ya las ofrece)', (tester) async {
      await pump(tester, diagnosisSeen: false);
      seen.see();
      await tester.pump();
      await wait(tester);
      expect(find.text('push_prompt_title_welcome'), findsNothing);
    });
  });
}

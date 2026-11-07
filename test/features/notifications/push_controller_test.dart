import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/notifications/data/notifications_repository.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/features/notifications/domain/notification_preferences.dart';
import 'package:portfolio_assistant/features/notifications/domain/push_route.dart';
import 'package:portfolio_assistant/features/notifications/providers/notification_preferences_provider.dart';
import 'package:portfolio_assistant/features/notifications/providers/push_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeMessaging implements PushMessaging {
  PushPermission current = PushPermission.notDetermined;
  PushPermission onRequest = PushPermission.granted;
  String? deviceToken = 'fcm-token-1';
  final refresh = StreamController<String>.broadcast();
  int requests = 0;

  @override
  bool get isAvailable => true;
  @override
  Future<PushPermission> permission() async => current;
  @override
  Future<PushPermission> requestPermission() async {
    requests++;
    current = onRequest;
    return current;
  }

  void Function()? onTokenAsked;

  @override
  Future<String?> token() async {
    onTokenAsked?.call();
    return deviceToken;
  }
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<PushMessage> get onOpened => const Stream.empty();
  @override
  Future<PushMessage?> initialMessage() async => null;
  @override
  Future<void> deleteToken() async {}
  @override
  String get platform => 'ios';
}

class FakeRepo extends NotificationsRepository {
  FakeRepo() : super(client: () => null);

  final registered = <Map<String, Object?>>[];
  final unregistered = <String>[];
  NotificationPreferences stored = const NotificationPreferences();
  bool failSave = false;

  @override
  Future<void> registerDevice({
    required String token,
    required String platform,
    required String locale,
    required String timezone,
    int? appBuild,
  }) async {
    registered.add({
      'token': token,
      'platform': platform,
      'locale': locale,
      'timezone': timezone,
      'build': appBuild,
    });
  }

  @override
  Future<void> unregisterDevice(String token) async => unregistered.add(token);

  @override
  Future<NotificationPreferences> loadPreferences() async => stored;

  @override
  Future<void> savePreferences(NotificationPreferences prefs) async {
    if (failSave) throw Exception('sin red');
    stored = prefs;
  }
}

class FakeDeviceInfo implements DeviceInfoSource {
  @override
  Future<String> timezone() async => 'America/Argentina/Buenos_Aires';
  @override
  Future<int?> appBuild() async => 7;
}

void main() {
  late FakeMessaging messaging;
  late FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    messaging = FakeMessaging();
    repo = FakeRepo();
    container = ProviderContainer(
      overrides: [
        pushMessagingProvider.overrideWithValue(messaging),
        notificationsRepositoryProvider.overrideWithValue(repo),
        deviceInfoSourceProvider.overrideWithValue(FakeDeviceInfo()),
      ],
    );
  });

  tearDown(() => container.dispose());

  PushController controller() => container.read(pushControllerProvider.notifier);

  test('sin permiso no registra nada', () async {
    await controller().syncToken();
    expect(repo.registered, isEmpty);
    expect(
      container.read(pushControllerProvider).permission,
      PushPermission.notDetermined,
    );
  });

  test('al conceder el permiso registra token, zona, idioma y build', () async {
    controller().localeCode = 'en';
    final result = await controller().requestPermission();
    expect(result, PushPermission.granted);
    expect(repo.registered.single, {
      'token': 'fcm-token-1',
      'platform': 'ios',
      'locale': 'en',
      'timezone': 'America/Argentina/Buenos_Aires',
      'build': 7,
    });
    expect(container.read(pushControllerProvider).token, 'fcm-token-1');
  });

  test('token nuevo de FCM: lo vuelve a registrar', () async {
    messaging.current = PushPermission.granted;
    container.read(pushControllerProvider);
    messaging.deviceToken = 'fcm-token-2';
    messaging.refresh.add('fcm-token-2');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(repo.registered.last['token'], 'fcm-token-2');
  });

  test('sin permiso, cerrar sesión no pide el token (no demora)', () async {
    await controller().refreshPermission();
    messaging.deviceToken = null;
    var asked = false;
    messaging.onTokenAsked = () => asked = true;
    await controller().unregisterBeforeSignOut();
    expect(asked, isFalse);
    expect(repo.unregistered, isEmpty);
  });

  test('al cerrar sesión borra el token registrado', () async {
    messaging.current = PushPermission.granted;
    await controller().syncToken();
    await controller().unregisterBeforeSignOut();
    expect(repo.unregistered, ['fcm-token-1']);
    expect(container.read(pushControllerProvider).token, isNull);
  });

  test('preferencias: el cambio se ve al instante y vuelve atrás si falla', () async {
    final notifier = container.read(notificationPreferencesProvider.notifier);
    await notifier.load();
    await notifier.update((p) => p.copyWith(bigMoves: false));
    expect(repo.stored.bigMoves, isFalse);

    repo.failSave = true;
    final pending = notifier.update((p) => p.copyWith(showAmounts: true));
    expect(
      container.read(notificationPreferencesProvider).preferences.showAmounts,
      isTrue,
    );
    await pending;
    final state = container.read(notificationPreferencesProvider);
    expect(state.preferences.showAmounts, isFalse);
    expect(state.saveFailed, isTrue);
  });

  group('PushPromptPolicy (plan §6)', () {
    test('no insiste: 14 días entre ofertas y 3 como mucho', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime(2026, 10, 10);
      final policy = PushPromptPolicy(prefs, now: () => now);

      expect(policy.shouldOffer(PushPermission.notDetermined), isTrue);
      expect(policy.shouldOffer(PushPermission.denied), isFalse);
      expect(policy.shouldOffer(PushPermission.granted), isFalse);

      await policy.recordShown();
      await policy.recordDismissed();
      now = now.add(const Duration(days: 13));
      expect(policy.shouldOffer(PushPermission.notDetermined), isFalse);
      now = now.add(const Duration(days: 1));
      expect(policy.shouldOffer(PushPermission.notDetermined), isTrue);

      await policy.recordShown();
      await policy.recordShown();
      now = now.add(const Duration(days: 30));
      expect(policy.shouldOffer(PushPermission.notDetermined), isFalse);
    });
  });
}

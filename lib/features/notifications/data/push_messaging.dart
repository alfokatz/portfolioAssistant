import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:portfolio_assistant/features/notifications/domain/push_route.dart';

/// Estado del permiso del sistema para mostrar notificaciones.
enum PushPermission {
  /// Nunca se le preguntó (iOS, Android 13+).
  notDetermined,
  granted,

  /// iOS "provisional" (llegan en silencio al centro de notificaciones).
  provisional,
  denied,

  /// Sin Firebase configurado (o plataforma sin push): no hay nada que
  /// pedir.
  unavailable;

  bool get canReceive => this == granted || this == provisional;
}

/// Lo que la app usa de FCM. Detrás de una interfaz para los tests, y para
/// que sin Firebase configurado (desarrollo, tests de pantallas) todo siga
/// andando sin push.
abstract class PushMessaging {
  bool get isAvailable;
  Future<PushPermission> permission();

  /// Muestra el diálogo del sistema (una sola vez en iOS).
  Future<PushPermission> requestPermission();
  Future<String?> token();
  Stream<String> get onTokenRefresh;

  /// Tocó una notificación con la app abierta o en segundo plano.
  Stream<PushMessage> get onOpened;

  /// La notificación que abrió la app desde cerrada (una sola vez).
  Future<PushMessage?> initialMessage();
  Future<void> deleteToken();

  String get platform;
}

class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  bool get isAvailable => false;
  @override
  Future<PushPermission> permission() async => PushPermission.unavailable;
  @override
  Future<PushPermission> requestPermission() async =>
      PushPermission.unavailable;
  @override
  Future<String?> token() async => null;
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Stream<PushMessage> get onOpened => const Stream.empty();
  @override
  Future<PushMessage?> initialMessage() async => null;
  @override
  Future<void> deleteToken() async {}
  @override
  String get platform => 'ios';
}

/// Canales de Android: los mismos ids que `androidChannel` en
/// supabase/functions/notify-dispatch/kinds.ts. El usuario puede silenciar
/// cada uno desde los ajustes del sistema.
const _androidChannels = [
  AndroidNotificationChannel(
    'price_alerts',
    'Alertas de precio',
    importance: Importance.high,
  ),
  AndroidNotificationChannel(
    'portfolio',
    'Tu cartera',
    importance: Importance.defaultImportance,
  ),
  AndroidNotificationChannel(
    'reports',
    'Informes',
    importance: Importance.defaultImportance,
  ),
  AndroidNotificationChannel(
    'account',
    'Cuenta',
    importance: Importance.defaultImportance,
  ),
];

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging._(this._messaging, this._local);

  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local;
  final _openedController = StreamController<PushMessage>.broadcast();

  /// Inicializa Firebase. Si el proyecto no tiene la configuración nativa
  /// (`GoogleService-Info.plist` / `google-services.json`), devuelve
  /// [NoopPushMessaging]: la app funciona igual, sin push.
  static Future<PushMessaging> create() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid)) {
      return const NoopPushMessaging();
    }
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[Push] Firebase no configurado: $e');
      return const NoopPushMessaging();
    }
    final instance = FirebasePushMessaging._(
      FirebaseMessaging.instance,
      FlutterLocalNotificationsPlugin(),
    );
    await instance._setUp();
    return instance;
  }

  Future<void> _setUp() async {
    // iOS: con la app abierta, el sistema muestra el banner igual y tocarlo
    // llega por onMessageOpenedApp.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: false,
      sound: true,
    );

    // Android: FCM no muestra nada con la app en primer plano; se muestra
    // con una notificación local en el canal que corresponda.
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
          _openedController.add(PushMessage(data: data));
        } catch (_) {}
      },
    );
    final android =
        _local
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    for (final channel in _androidChannels) {
      await android?.createNotificationChannel(channel);
    }

    FirebaseMessaging.onMessage.listen(_showForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _openedController.add(_toPushMessage(m)),
    );
  }

  Future<void> _showForeground(RemoteMessage message) async {
    if (!Platform.isAndroid) return;
    final notification = message.notification;
    if (notification == null) return;
    final channel =
        notification.android?.channelId ??
        _androidChannels.last.id; // 'account'
    final match = _androidChannels.firstWhere(
      (c) => c.id == channel,
      orElse: () => _androidChannels.last,
    );
    await _local.show(
      id: message.hashCode & 0x7fffffff,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          match.id,
          match.name,
          importance: match.importance,
          priority:
              match.importance == Importance.high
                  ? Priority.high
                  : Priority.defaultPriority,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static PushMessage _toPushMessage(RemoteMessage m) => PushMessage(
    data: m.data,
    title: m.notification?.title,
    body: m.notification?.body,
  );

  static PushPermission _map(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized => PushPermission.granted,
    AuthorizationStatus.provisional => PushPermission.provisional,
    AuthorizationStatus.denied => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notDetermined,
  };

  @override
  bool get isAvailable => true;

  @override
  Future<PushPermission> permission() async =>
      _map((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: false,
      sound: true,
    );
    return _map(settings.authorizationStatus);
  }

  @override
  Future<String?> token() async {
    try {
      if (Platform.isIOS) {
        // Sin el token de APNs todavía, getToken falla: se espera un poco.
        for (var i = 0; i < 5; i++) {
          if (await _messaging.getAPNSToken() != null) break;
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      return await _messaging.getToken();
    } catch (e) {
      debugPrint('[Push] getToken falló: $e');
      return null;
    }
  }

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  @override
  Stream<PushMessage> get onOpened => _openedController.stream;

  @override
  Future<PushMessage?> initialMessage() async {
    final remote = await _messaging.getInitialMessage();
    if (remote != null) return _toPushMessage(remote);
    // Android: tocó una notificación local (mostrada en primer plano) y la
    // app se había cerrado.
    final details = await _local.getNotificationAppLaunchDetails();
    final payload = details?.notificationResponse?.payload;
    if (details?.didNotificationLaunchApp == true && payload != null) {
      try {
        return PushMessage(
          data: Map<String, dynamic>.from(jsonDecode(payload) as Map),
        );
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  String get platform => Platform.isIOS ? 'ios' : 'android';
}

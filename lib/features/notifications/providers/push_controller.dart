import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/features/notifications/data/notifications_repository.dart';
import 'package:portfolio_assistant/features/notifications/data/push_messaging.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCM (o [NoopPushMessaging] sin Firebase). Se reemplaza en main.dart con
/// la instancia ya inicializada.
final pushMessagingProvider = Provider<PushMessaging>(
  (ref) => const NoopPushMessaging(),
);

/// Lo que la app necesita saber del dispositivo para registrarlo.
abstract class DeviceInfoSource {
  Future<String> timezone();
  Future<int?> appBuild();
}

class PlatformDeviceInfoSource implements DeviceInfoSource {
  const PlatformDeviceInfoSource();

  @override
  Future<String> timezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'UTC';
    }
  }

  @override
  Future<int?> appBuild() async {
    try {
      return int.tryParse((await PackageInfo.fromPlatform()).buildNumber);
    } catch (_) {
      return null;
    }
  }
}

final deviceInfoSourceProvider = Provider<DeviceInfoSource>(
  (ref) => const PlatformDeviceInfoSource(),
);

class PushState {
  const PushState({
    this.permission = PushPermission.notDetermined,
    this.loaded = false,
    this.token,
  });

  final PushPermission permission;
  final bool loaded;

  /// El token registrado en el servidor para la cuenta actual.
  final String? token;

  bool get isAvailable => permission != PushPermission.unavailable;

  PushState copyWith({
    PushPermission? permission,
    bool? loaded,
    String? token,
    bool clearToken = false,
  }) {
    return PushState(
      permission: permission ?? this.permission,
      loaded: loaded ?? this.loaded,
      token: clearToken ? null : (token ?? this.token),
    );
  }
}

/// Permiso del sistema y registro del token del dispositivo.
///
/// - Al iniciar sesión (o abrir la app con sesión) y con permiso, registra
///   el token, la zona horaria y el idioma (la zona y el idioma pueden
///   cambiar: se actualizan en cada apertura).
/// - Al cerrar sesión lo borra ANTES de que la sesión se cierre (después ya
///   no hay con qué autenticar el borrado).
class PushController extends StateNotifier<PushState> {
  PushController(this._ref) : super(const PushState()) {
    _tokenSub = _messaging.onTokenRefresh.listen((_) => syncToken());
  }

  final Ref _ref;
  StreamSubscription<String>? _tokenSub;

  /// Idioma de la app (lo fija la UI: es la elección del usuario, no la del
  /// sistema).
  String localeCode = 'es';

  PushMessaging get _messaging => _ref.read(pushMessagingProvider);
  NotificationsRepository get _repo =>
      _ref.read(notificationsRepositoryProvider);

  Future<void> refreshPermission() async {
    final permission = await _messaging.permission();
    if (!mounted) return;
    state = state.copyWith(permission: permission, loaded: true);
  }

  /// Lee el permiso y, si se puede, registra el token. Idempotente.
  Future<void> syncToken() async {
    await refreshPermission();
    if (!state.permission.canReceive) return;
    final token = await _messaging.token();
    if (token == null || !mounted) return;
    final info = _ref.read(deviceInfoSourceProvider);
    try {
      await _repo.registerDevice(
        token: token,
        platform: _messaging.platform,
        locale: localeCode == 'en' ? 'en' : 'es',
        timezone: await info.timezone(),
        appBuild: await info.appBuild(),
      );
      if (mounted) state = state.copyWith(token: token);
    } catch (e) {
      debugPrint('[Push] register_push_device falló: $e');
    }
  }

  /// Muestra el diálogo del sistema. Con permiso, registra el token.
  Future<PushPermission> requestPermission() async {
    final permission = await _messaging.requestPermission();
    if (!mounted) return permission;
    state = state.copyWith(permission: permission, loaded: true);
    if (permission.canReceive) await syncToken();
    return permission;
  }

  /// Antes de cerrar sesión. Nunca bloquea el cierre: si falla (sin red),
  /// el servidor limpia el token cuando FCM lo rechace o a los 60 días.
  Future<void> unregisterBeforeSignOut() async {
    // Sin permiso no hay token registrado: no se espera a FCM (en iOS pedir
    // el token sin permiso espera el de APNs y demoraría el cierre).
    final token =
        state.token ??
        (state.permission.canReceive ? await _messaging.token() : null);
    if (token == null) return;
    try {
      await _repo.unregisterDevice(token).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[Push] unregister_push_device falló: $e');
    }
    if (mounted) state = state.copyWith(clearToken: true);
  }

  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }
}

final pushControllerProvider =
    StateNotifierProvider<PushController, PushState>(
      (ref) => PushController(ref),
    );

/// Registra el token al iniciar sesión (y al abrir la app con sesión).
final pushAuthSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<Session?>>(authSessionProvider, (previous, next) {
    final previousId = previous?.value?.user.id;
    final nextId = next.value?.user.id;
    if (nextId != null && nextId != previousId) {
      unawaited(ref.read(pushControllerProvider.notifier).syncToken());
    }
  }, fireImmediately: true);
});

/// Cuándo ofrecer la pantalla previa al permiso (plan §6): nunca si ya
/// respondió el diálogo del sistema; si tocó "Ahora no", no antes de 14
/// días, y como mucho 3 veces.
class PushPromptPolicy {
  PushPromptPolicy(this._prefs, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const _dismissedAtKey = 'push_prompt_dismissed_at';
  static const _countKey = 'push_prompt_count';
  static const maxPrompts = 3;
  static const cooldown = Duration(days: 14);

  bool shouldOffer(PushPermission permission) {
    if (permission != PushPermission.notDetermined) return false;
    if ((_prefs.getInt(_countKey) ?? 0) >= maxPrompts) return false;
    final dismissedAt = _prefs.getInt(_dismissedAtKey);
    if (dismissedAt == null) return true;
    final since = _now().difference(
      DateTime.fromMillisecondsSinceEpoch(dismissedAt),
    );
    return since >= cooldown;
  }

  Future<void> recordShown() async {
    await _prefs.setInt(_countKey, (_prefs.getInt(_countKey) ?? 0) + 1);
  }

  Future<void> recordDismissed() async {
    await _prefs.setInt(_dismissedAtKey, _now().millisecondsSinceEpoch);
  }
}

final pushPromptPolicyProvider = Provider<PushPromptPolicy>(
  (ref) => PushPromptPolicy(ref.watch(sharedPreferencesProvider)),
);

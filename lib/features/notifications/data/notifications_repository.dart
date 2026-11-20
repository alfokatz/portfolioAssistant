import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_client_provider.dart';
import 'package:portfolio_assistant/features/notifications/domain/notification_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dispositivos y preferencias de notificaciones en Supabase (RPCs de
/// 20261011000000_push_notifications.sql).
class NotificationsRepository {
  NotificationsRepository({required SupabaseClient? Function() client})
    : _client = client;

  /// Diferido: sin Supabase inicializado (tests de pantallas) las llamadas
  /// no hacen nada.
  final SupabaseClient? Function() _client;

  SupabaseClient? get _signedIn {
    final client = _client();
    if (client == null || client.auth.currentUser == null) return null;
    return client;
  }

  Future<void> registerDevice({
    required String token,
    required String platform,
    required String locale,
    required String timezone,
    int? appBuild,
  }) async {
    final client = _signedIn;
    if (client == null) return;
    await client.rpc(
      'register_push_device',
      params: {
        'p_token': token,
        'p_platform': platform,
        'p_locale': locale,
        'p_timezone': timezone,
        'p_app_build': appBuild,
      },
    );
  }

  Future<void> unregisterDevice(String token) async {
    final client = _signedIn;
    if (client == null) return;
    await client.rpc('unregister_push_device', params: {'p_token': token});
  }

  Future<NotificationPreferences> loadPreferences() async {
    final client = _signedIn;
    if (client == null) return const NotificationPreferences();
    final row = await client.rpc('get_notification_preferences');
    if (row is Map) {
      return NotificationPreferences.fromRow(Map<String, dynamic>.from(row));
    }
    return const NotificationPreferences();
  }

  Future<void> savePreferences(NotificationPreferences prefs) async {
    final client = _signedIn;
    if (client == null) return;
    await client.from('notification_preferences').upsert({
      'user_id': client.auth.currentUser!.id,
      ...prefs.toRow(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> requestTestNotification() async {
    final client = _signedIn;
    if (client == null) return;
    await client.rpc('request_test_notification');
  }

  Future<void> markOpened(int logId) async {
    final client = _signedIn;
    if (client == null) return;
    await client.rpc('mark_notification_opened', params: {'p_log_id': logId});
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(
    client: () {
      try {
        return ref.read(supabaseClientProvider);
      } catch (_) {
        return null;
      }
    },
  ),
);

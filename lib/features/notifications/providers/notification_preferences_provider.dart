import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/features/notifications/data/notifications_repository.dart';
import 'package:portfolio_assistant/features/notifications/domain/notification_preferences.dart';

class NotificationPreferencesState {
  const NotificationPreferencesState({
    this.preferences = const NotificationPreferences(),
    this.loaded = false,
    this.saveFailed = false,
  });

  final NotificationPreferences preferences;
  final bool loaded;

  /// El último cambio no se pudo guardar (se volvió al valor anterior).
  final bool saveFailed;
}

/// Preferencias de notificaciones. Los cambios se ven al instante y se
/// guardan de fondo; si el guardado falla, vuelve el valor anterior.
class NotificationPreferencesNotifier
    extends StateNotifier<NotificationPreferencesState> {
  NotificationPreferencesNotifier(this._repo)
    : super(const NotificationPreferencesState());

  final NotificationsRepository _repo;
  int _revision = 0;

  Future<void> load() async {
    try {
      final prefs = await _repo.loadPreferences();
      if (!mounted) return;
      state = NotificationPreferencesState(preferences: prefs, loaded: true);
    } catch (e) {
      debugPrint('[Push] preferencias: $e');
      if (mounted) {
        state = NotificationPreferencesState(
          preferences: state.preferences,
          loaded: true,
        );
      }
    }
  }

  Future<void> update(
    NotificationPreferences Function(NotificationPreferences) change,
  ) async {
    final previous = state.preferences;
    final next = change(previous);
    if (next == previous) return;
    final revision = ++_revision;
    state = NotificationPreferencesState(preferences: next, loaded: true);
    try {
      await _repo.savePreferences(next);
    } catch (e) {
      debugPrint('[Push] guardar preferencias: $e');
      // Solo revierte si nadie cambió otra cosa mientras tanto.
      if (mounted && revision == _revision) {
        state = NotificationPreferencesState(
          preferences: previous,
          loaded: true,
          saveFailed: true,
        );
      }
    }
  }
}

final notificationPreferencesProvider = StateNotifierProvider<
  NotificationPreferencesNotifier,
  NotificationPreferencesState
>((ref) => NotificationPreferencesNotifier(
  ref.watch(notificationsRepositoryProvider),
));

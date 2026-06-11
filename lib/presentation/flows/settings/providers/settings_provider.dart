import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/presentation/flows/settings/states/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyNotifications = 'settings_notifications_enabled';
const _keyPriceAlerts = 'settings_price_alerts_enabled';

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier(this._prefs) : super(const SettingsState());

  final SharedPreferences _prefs;

  Future<void> init() async {
    state = state.copyWith(
      notificationsEnabled: _prefs.getBool(_keyNotifications) ?? true,
      priceAlertsEnabled: _prefs.getBool(_keyPriceAlerts) ?? true,
      isLoading: false,
    );
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _prefs.setBool(_keyNotifications, value);
    state = state.copyWith(notificationsEnabled: value);
  }

  Future<void> setPriceAlertsEnabled(bool value) async {
    await _prefs.setBool(_keyPriceAlerts, value);
    state = state.copyWith(priceAlertsEnabled: value);
  }
}

final settingsProvider =
    StateNotifierProvider.autoDispose<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(ref.watch(sharedPreferencesProvider)),
);

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const settingsThemeModeKey = 'settings_theme_mode';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs) : super(read(_prefs));

  final SharedPreferences _prefs;

  /// El tema que eligió el usuario en Ajustes ([ThemeMode.system] si nunca
  /// eligió). También lo usa el loader del arranque, antes de Riverpod.
  static ThemeMode read(SharedPreferences prefs) {
    final index = prefs.getInt(settingsThemeModeKey);
    if (index == null || index < 0 || index >= ThemeMode.values.length) {
      return ThemeMode.system;
    }
    return ThemeMode.values[index];
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt(settingsThemeModeKey, mode.index);
    state = mode;
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.watch(sharedPreferencesProvider));
});

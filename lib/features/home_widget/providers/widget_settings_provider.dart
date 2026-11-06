import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/config/supabase/supabase_auth_service.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Claves del `SharedPreferences` PRIVADO de la app (nunca del
/// almacenamiento compartido con el widget).
abstract final class WidgetPrefsKeys {
  /// bool, default `false`: "Ocultar posiciones en el widget".
  static const positionsHidden = 'widget_positions_hidden';

  /// El ajuste de la versión anterior ("Ocultar montos"). Solo se lee, para
  /// migrar: ver [readPositionsHidden].
  static const legacyAmountsHidden = 'widget_amounts_hidden';

  /// Lectura única del ajuste (la app y el refresco de fondo): la clave
  /// nueva o, si falta, la vieja. Quien pidió ocultar montos pidió
  /// privacidad: `true` migra a `true` (el ajuste nuevo es más estricto y lo
  /// puede apagar).
  static bool readPositionsHidden(SharedPreferences prefs) =>
      prefs.getBool(positionsHidden) ??
      prefs.getBool(legacyAmountsHidden) ??
      false;

  /// Id del usuario dueño del widget. Lo lee el refresco de fondo (no tiene
  /// sesión) para saber de quién es el caché de la Home. Se borra al cerrar
  /// sesión.
  static const ownerUid = 'widget_owner_uid';

  /// Idioma ('es' | 'en') con el que se escribió el último snapshot: el
  /// refresco de fondo no tiene el idioma de la app.
  static const lang = 'widget_lang';

  /// Lo último que se registró en `widget_presence` (tamaños instalados).
  static const presence = 'widget_presence_sizes';

  /// Aperturas de la app contadas para ofrecer el widget (int).
  static const promptOpens = 'widget_prompt_opens';

  /// Veces que se ofreció solo (int, tope 2).
  static const promptShown = 'widget_prompt_shown';

  /// Cuándo fue la última oferta automática (ms UTC).
  static const promptLastAt = 'widget_prompt_last_at';

  /// Todas las del estado de la oferta (se borran al cerrar sesión).
  static const promptKeys = [promptOpens, promptShown, promptLastAt];
}

/// El ajuste "Ocultar posiciones en el widget". Al construirse migra la
/// clave vieja (solo la app escribe la migración; el isolate de fondo solo
/// lee con el fallback, sin carreras).
class WidgetPositionsHiddenNotifier extends StateNotifier<bool> {
  WidgetPositionsHiddenNotifier(this._prefs)
    : super(WidgetPrefsKeys.readPositionsHidden(_prefs)) {
    unawaited(_migrate());
  }

  final SharedPreferences _prefs;

  Future<void> _migrate() async {
    if (_prefs.containsKey(WidgetPrefsKeys.positionsHidden)) return;
    final legacy = _prefs.getBool(WidgetPrefsKeys.legacyAmountsHidden);
    if (legacy == null) return;
    await _prefs.setBool(WidgetPrefsKeys.positionsHidden, legacy);
    await _prefs.remove(WidgetPrefsKeys.legacyAmountsHidden);
  }

  Future<void> setHidden(bool hidden) async {
    state = hidden;
    await _prefs.setBool(WidgetPrefsKeys.positionsHidden, hidden);
  }
}

final widgetPositionsHiddenProvider = StateNotifierProvider<
  WidgetPositionsHiddenNotifier,
  bool
>((ref) => WidgetPositionsHiddenNotifier(ref.watch(sharedPreferencesProvider)));

/// El id del usuario con sesión, o `null` (sin sesión o sin Supabase, como
/// en los tests). Una función, para leerlo al momento.
final widgetCurrentUserIdProvider = Provider<String? Function()>(
  (ref) => () {
    try {
      return ref.read(supabaseAuthServiceProvider).currentUser?.id;
    } catch (_) {
      return null;
    }
  },
);

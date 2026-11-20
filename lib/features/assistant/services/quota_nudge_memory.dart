import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Recuerda en qué meses ya se mostró la línea de cuota baja del chat, por
/// usuario: una sola vez por mes UTC (el mismo corte que `_current_usage_month`
/// del servidor). Vive en el teléfono: si el usuario cambia de teléfono la
/// puede ver dos veces en el mes, y es aceptable para una línea.
///
/// Guarda una lista de `"<userId>:YYYY-MM"` en [prefsKey]. Sin
/// `SharedPreferences` (tests de otras pantallas) queda en memoria.
class QuotaNudgeMemory {
  QuotaNudgeMemory([this._prefs]) {
    _entries.addAll(_prefs?.getStringList(prefsKey) ?? const []);
  }

  static const prefsKey = 'quota_nudge_shown';

  final SharedPreferences? _prefs;
  final _entries = <String>{};

  /// `"<userId>:YYYY-MM"` con el mes en UTC.
  static String entryFor(String userId, DateTime now) {
    final utc = now.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    return '$userId:${utc.year}-$month';
  }

  bool wasShown(String userId, DateTime now) =>
      _entries.contains(entryFor(userId, now));

  /// Marca el mes como mostrado. La memoria cambia en el acto (dos pedidos
  /// seguidos no muestran la línea dos veces); la escritura puede fallar sin
  /// consecuencias. Descarta los meses anteriores: ya no se consultan.
  Future<void> markShown(String userId, DateTime now) async {
    final current = entryFor(userId, now);
    final month = current.substring(current.lastIndexOf(':') + 1);
    _entries
      ..removeWhere((e) => !e.endsWith(':$month'))
      ..add(current);
    try {
      await _prefs?.setStringList(prefsKey, _entries.toList());
    } catch (_) {}
  }
}

final quotaNudgeMemoryProvider = Provider<QuotaNudgeMemory>((ref) {
  SharedPreferences? prefs;
  try {
    prefs = ref.read(sharedPreferencesProvider);
  } catch (_) {
    // Sin override (tests de otras pantallas): en memoria.
  }
  return QuotaNudgeMemory(prefs);
});

/// El reloj de la línea de cuota; los tests lo reemplazan.
final quotaNudgeClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

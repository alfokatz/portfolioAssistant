import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const settingsHapticsEnabledKey = 'settings_haptics_enabled';

/// Patrones disponibles usando solo `HapticFeedback` de Flutter (sin
/// CoreHaptics / VibrationEffect nativos).
enum PortyHapticPattern { selection, light, medium, heavy, doubleLight }

/// Vibración que acompaña cada palabra del texto de Porty mientras se tipea.
/// `selectionClick` es el "tick" más seco y corto de los dos candidatos
/// (`lightImpact` tiene más cuerpo): en ráfagas de ~10/s se siente como
/// textura en vez de golpes. Cambiar acá si en device se prefiere el otro.
const streamTickPattern = PortyHapticPattern.selection;

/// Cooldown mínimo entre ticks de streaming — el typewriter completa una
/// palabra cada ~100-150ms a 40 chars/s, pero palabras cortas ("a", "el")
/// pueden caer más juntas; esto evita saturar.
const streamTickCooldown = Duration(milliseconds: 100);

/// Vibración al terminar de revelarse cada componente GenUI, por nombre de
/// componente del catálogo (`CatalogItemContext.type`). Los componentes que
/// no estén acá no vibran.
const componentHapticPatterns = <String, PortyHapticPattern>{
  // Movimiento / cambio brusco.
  'QaTickerMove': PortyHapticPattern.heavy,
  'QaTopMovers': PortyHapticPattern.heavy,
  // Informativos neutros (datos, listas, charts).
  'QaTickerSnapshot': PortyHapticPattern.medium,
  'QaMetricStrip': PortyHapticPattern.medium,
  'QaEarningsCalendar': PortyHapticPattern.medium,
  'QaPeriodChange': PortyHapticPattern.medium,
  'QaConcentrationBar': PortyHapticPattern.medium,
  'QaPnLBreakdown': PortyHapticPattern.medium,
  'QaPositionList': PortyHapticPattern.medium,
  'QaClosedPositionList': PortyHapticPattern.medium,
  'QaInvestOption': PortyHapticPattern.medium,
  'QaBudgetSplit': PortyHapticPattern.medium,
  'QaGoalCard': PortyHapticPattern.medium,
  'QaProjectionStrip': PortyHapticPattern.medium,
  'QaProjectionChart': PortyHapticPattern.medium,
  'QaMilestoneList': PortyHapticPattern.medium,
  'QaComparisonRow': PortyHapticPattern.medium,
  // Texto / noticias.
  'QaAnswerText': PortyHapticPattern.light,
  'QaNewsSummary': PortyHapticPattern.light,
  // Avisos / pedidos de atención.
  'QaTipBanner': PortyHapticPattern.doubleLight,
  'QaInvestConfirm': PortyHapticPattern.doubleLight,
};

/// Único punto que dispara haptics de Porty: chequea el setting del usuario
/// antes de cada llamada, así ningún widget tiene que conocer el flag. Si el
/// usuario apagó las vibraciones a nivel sistema, `HapticFeedback` ya es un
/// no-op por su cuenta.
///
/// Todas las llamadas son fire-and-forget (no se awaitean): el canal de
/// plataforma es asíncrono y no debe frenar el frame que las dispara.
class PortyHapticsService {
  PortyHapticsService({
    required this.enabled,
    DateTime Function()? clock,
    Future<void> Function(PortyHapticPattern)? performer,
  }) : _clock = clock ?? DateTime.now,
       _performer = performer ?? _perform;

  bool enabled;
  final DateTime Function() _clock;
  final Future<void> Function(PortyHapticPattern) _performer;
  DateTime? _lastStreamTick;

  /// Busca el servicio en el `ProviderScope` ancestro sin crashear si no
  /// hay uno (widgets testeados en aislamiento) — devuelve `null` y el
  /// caller simplemente no vibra.
  static PortyHapticsService? maybeOf(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<
          UncontrolledProviderScope
        >();
    final scope = element?.widget as UncontrolledProviderScope?;
    return scope?.container.read(portyHapticsServiceProvider);
  }

  /// Una palabra nueva apareció en el stream del texto de Porty.
  void streamTick() {
    if (!enabled) return;
    final now = _clock();
    final last = _lastStreamTick;
    if (last != null && now.difference(last) < streamTickCooldown) return;
    _lastStreamTick = now;
    _performer(streamTickPattern);
  }

  /// El componente [componentType] del catálogo terminó de revelarse.
  void componentRevealed(String componentType) {
    if (!enabled) return;
    final pattern = componentHapticPatterns[componentType];
    if (pattern != null) _performer(pattern);
  }

  static Future<void> _perform(PortyHapticPattern pattern) async {
    switch (pattern) {
      case PortyHapticPattern.selection:
        await HapticFeedback.selectionClick();
      case PortyHapticPattern.light:
        await HapticFeedback.lightImpact();
      case PortyHapticPattern.medium:
        await HapticFeedback.mediumImpact();
      case PortyHapticPattern.heavy:
        await HapticFeedback.heavyImpact();
      case PortyHapticPattern.doubleLight:
        await HapticFeedback.lightImpact();
        await Future<void>.delayed(const Duration(milliseconds: 90));
        await HapticFeedback.lightImpact();
    }
  }
}

class HapticsEnabledNotifier extends StateNotifier<bool> {
  HapticsEnabledNotifier(this._prefs)
    : super(_prefs.getBool(settingsHapticsEnabledKey) ?? true);

  final SharedPreferences _prefs;

  Future<void> setEnabled(bool value) async {
    await _prefs.setBool(settingsHapticsEnabledKey, value);
    state = value;
  }
}

/// Setting "Vibraciones al responder" — global (no autoDispose) porque lo
/// lee el chat aunque la pantalla de configuración no esté montada, mismo
/// patrón que `themeModeProvider`.
final hapticsEnabledProvider =
    StateNotifierProvider<HapticsEnabledNotifier, bool>((ref) {
      return HapticsEnabledNotifier(ref.watch(sharedPreferencesProvider));
    });

/// Instancia estable (conserva el estado del throttle) que se entera de los
/// cambios del setting en vez de recrearse.
final portyHapticsServiceProvider = Provider<PortyHapticsService>((ref) {
  final service = PortyHapticsService(enabled: ref.read(hapticsEnabledProvider));
  ref.listen<bool>(
    hapticsEnabledProvider,
    (_, next) => service.enabled = next,
  );
  return service;
});

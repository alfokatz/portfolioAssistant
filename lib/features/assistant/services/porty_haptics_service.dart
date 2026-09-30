import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:portfolio_assistant/infraestructure/managers/preferences_manager_impl.dart';
import 'package:portfolio_assistant/shared/utils/provider_lookup.dart';
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

/// Cooldown del tick de scrub sobre un gráfico: en rangos largos hay más de
/// un punto por pixel y un drag rápido cruzaría decenas por frame.
const scrubTickCooldown = Duration(milliseconds: 35);

/// Toque que acompaña la entrada de cada widget de una respuesta, en el
/// mismo frame en que empieza a moverse. `lightImpact`: con cuerpo
/// suficiente para sentirse como "llegó algo", sin llegar a golpe.
const widgetEntryPattern = PortyHapticPattern.light;

/// Cierre al terminar de entrar el último widget: `mediumImpact`, un
/// escalón más firme que los toques de entrada, como un punto final. La
/// alternativa probada en papel es `selection` (más seco y liviano que los
/// toques): cambiar acá si en device se siente mejor.
const answerCompletePattern = PortyHapticPattern.medium;

/// Respuesta de solo texto: el toque leve de siempre al terminar de tipear.
const textAnswerPattern = PortyHapticPattern.light;

/// Tocar algo bloqueado por plan: el "tick" seco de selección, en el mismo
/// frame del toque — confirma que se registró aunque la hoja tarde.
const lockedTapPattern = PortyHapticPattern.selection;

/// La hoja de paywall terminó de abrirse: un toque leve, el mismo cuerpo que
/// la entrada de un widget (algo "llegó"), nunca más fuerte.
const paywallOpenedPattern = PortyHapticPattern.light;

/// Las secciones de Gold se desbloquearon en el lugar tras comprar: el
/// mismo cierre que una respuesta completa ("listo").
const goldUnlockedPattern = PortyHapticPattern.medium;

/// Tope de toques por widget en una respuesta. Con el cierre, una
/// respuesta nunca pasa de 4 vibraciones.
const maxWidgetEntryTicks = 3;

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
  DateTime? _lastScrubTick;

  /// Busca el servicio en el `ProviderScope` ancestro sin crashear si no
  /// hay uno (widgets testeados en aislamiento) — devuelve `null` y el
  /// caller simplemente no vibra.
  static PortyHapticsService? maybeOf(BuildContext context) =>
      readProviderOrNull(context, portyHapticsServiceProvider);

  /// Una palabra nueva apareció en el stream del texto de Porty.
  void streamTick() {
    if (!enabled) return;
    final now = _clock();
    final last = _lastStreamTick;
    if (last != null && now.difference(last) < streamTickCooldown) return;
    _lastStreamTick = now;
    _performer(streamTickPattern);
  }

  /// El dedo cruzó de un punto al siguiente scrubeando un gráfico.
  void scrubTick() {
    if (!enabled) return;
    final now = _clock();
    final last = _lastScrubTick;
    if (last != null && now.difference(last) < scrubTickCooldown) return;
    _lastScrubTick = now;
    _performer(PortyHapticPattern.selection);
  }

  /// El widget [index] (de [total]) de una respuesta arrancó su entrada.
  /// Con más widgets que [maxWidgetEntryTicks], vibran solo algunos,
  /// repartidos parejo (el primero y el último siempre).
  void widgetEntryStarted({required int index, required int total}) {
    if (!enabled || !ticksOnWidget(index, total)) return;
    _performer(widgetEntryPattern);
  }

  /// El último widget de la respuesta terminó de entrar.
  void answerRevealCompleted() {
    if (!enabled) return;
    _performer(answerCompletePattern);
  }

  /// Una respuesta de solo texto terminó de tipearse.
  void textAnswerRevealed() {
    if (!enabled) return;
    _performer(textAnswerPattern);
  }

  /// Se tocó un bloque o chip bloqueado por plan.
  void lockedTap() {
    if (!enabled) return;
    _performer(lockedTapPattern);
  }

  /// Se abrió la hoja de paywall.
  void paywallOpened() {
    if (!enabled) return;
    _performer(paywallOpenedPattern);
  }

  /// Las secciones de Gold de una card se desbloquearon tras comprar.
  void goldUnlocked() {
    if (!enabled) return;
    _performer(goldUnlockedPattern);
  }

  /// Si el widget [index] de [total] vibra al entrar, respetando
  /// [maxWidgetEntryTicks].
  @visibleForTesting
  static bool ticksOnWidget(int index, int total) {
    if (index < 0 || index >= total) return false;
    if (total <= maxWidgetEntryTicks) return true;
    for (var tick = 0; tick < maxWidgetEntryTicks; tick++) {
      final chosen = (tick * (total - 1) / (maxWidgetEntryTicks - 1)).round();
      if (chosen == index) return true;
    }
    return false;
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
  final service = PortyHapticsService(
    enabled: ref.read(hapticsEnabledProvider),
  );
  ref.listen<bool>(hapticsEnabledProvider, (_, next) => service.enabled = next);
  return service;
});
